# $Id: Sort.pm,v 1.26 2002/03/23 00:36:08 itz Exp $

package Mail::Sort;

@ISA = qw(Exporter);
@EXPORT = qw(TEMPFAIL DELIVERED);

no warnings qw(digit);

$VERSION = '$Date: 2002/03/23 00:36:08 $ '; $VERSION =~ s|^\$Date:\s*([0-9]{4})/([0-9]{2})/([0-9]{2})\s.*|\1.\2.\3| ;


use FileHandle 2.00;
use Mail::Internet 1.33;
use Mail::Header 1.19;
use POSIX 1.03 qw(close strftime WIFSIGNALED WTERMSIG O_CREAT O_EXCL EEXIST);
use Config;

use constant TEMPFAIL	=> 75;
use constant DELIVERED	=> 0;
use strict;
use v5.6.0;

sub new {
    my $class = shift;

    my $self     =  {
        test     => 0,
        logfile  => '/dev/null',
        loglevel => 1,
        lockwait => 5,
        locktries => 10,
        callback => undef,
        envelope_from => "$ENV{LOGNAME}\@localhost",
        };

    bless $self, $class;
    
    my $fh;
    if (ref $_[0] eq 'Mail::Internet') {
        $self->{obj} = shift;
    } elsif (ref $_[0] eq 'ARRAY') {
        my @copy = @{$_[0];};    # stupid Mail::Internet clobbers input array!
        shift;
        if ($copy[0] =~ /^From\s+(\S+)/) {
            $self->{envelope_from} = $1;
            shift @copy;
        }
        $self->{obj} = new Mail::Internet(\@copy, Modify => 0) or exit TEMPFAIL;
    } else {
        if (ref $_[0] eq 'FileHandle') {
            $fh = shift;
        } else {
            $fh = new FileHandle;
            if (!$fh->fdopen(0, '<')) {
                $self->log(0, "$!");
                exit TEMPFAIL;
            }
        }
        my @copy = $fh->getlines();
        if ($copy[0] =~ /^From\s+(\S+)/) {
            $self->{envelope_from} = $1;
            shift @copy;
        }
        $self->{obj} = new Mail::Internet(\@copy, Modify => 0) or exit TEMPFAIL;
    }
    
    my ($arg, $val) = (shift, shift);
    while (defined $arg and defined $val) {
        if (!grep { $_ eq $arg } (keys %{$self})) {
             $self->log(1, "$arg is not a valid key for new Mail::Sort::new");
        } else {
            $self->{$arg} = $val;
        }
        ($arg, $val) = (shift, shift);
    }

    $self->{signo} = { };
    my $i = 0;
    foreach my $n (split(' ', $Config{sig_name})) {
        $self->{signo}->{$n} = $i;
        $i++;
    }
    
    my $head = $self->{obj}->head->dup(); # create a dup because we'll modify this one
    $head->modify(0);
    $head->unfold();
    $self->{head} = $head->header;

    $self->{body} = $self->{obj}->body;

    $self->{matches} = [ ];
    return $self;
}

sub _save_match {
    my ($self, $line, $pat, $fold) = @_;
    my $ok = 0;
    if (($fold and $line =~ /$pat/i)
        or (!$fold and $line =~ /$pat/)) {
        $ok = 1;
        no strict 'refs';
        for (my $i = 1; $i < 50; $i++) {
            if (defined $$i) {
                $self->{matches}->[$i] = $$i;
            } else {
                $self->{matches}->[$i] = undef;
            }
        }
    } 
    $ok;
}

sub header_match {
    my ($self, $tag, $pattern, $context) = @_;
    $self->{matches} = [ ];
    if (!defined $pattern) { $pattern = ''; }
    if (!defined $context) { $context = '.*'; }
    my @match;
    if ($tag =~ /[A-Z]/ ) {
        @match = grep {$self->_save_match($_,"^$tag:$context$pattern", 0)} @{$self->{head}};
    } else {
        @match = grep {$self->_save_match($_,"^$tag:$context$pattern", 1)} @{$self->{head}};
    }
    if (@match) {
        foreach my $m (@match) {
            my $chomped = $m;
            chomp $chomped;
            $self->log(3, $chomped, 'header match');
        }
    }
    return @match;
}

sub match_group {
    my ($self, $index) = @_;
    return $self->{matches}->[$index];
}

sub header_start {
    my ($self, $tag, $pattern) = @_;
    return $self->header_match($tag, $pattern, '\s*');
}

our $dest_regexp =
    '(?:(?:original-)?(?:resent-)?(?:to|cc|bcc)|(?:x-envelope|apparently(?:-resent)?)-to)';

sub destination_match {
    my ($self, $pattern, $context) = @_;
    return $self->header_match($dest_regexp, $pattern, $context);
}

sub destination_address {
    my ($self, $address) = @_;
    return $self->destination_match($address, '(?:.*[^-a-z0-9_.])?');
}

sub destination_word {
    my ($self, $word) = @_;
    return $self->destination_match($word, '(?:.*[^a-z])?');
}

our $sender_regexp =
    '(?:(?:resent-)?sender|resent-from|return-path)';

sub sender_match {
    my ($self, $pattern, $context) = @_;
    return $self->header_match($sender_regexp, $pattern, $context); 
}

sub log {
    my ($self, $level, $what, $label) = @_;
    if ($label) {
        $what = '('.$label.') '.$what;
    }
    return unless $self->{logfile} and $level <= $self->{loglevel};

    if (!defined $self->{_logfh}) {
        if (ref $self->{logfile} eq 'FileHandle') {
            $self->{_logfh} = $self->{logfile};
        } else {
            $self->{_logfh} = new FileHandle('>>'.$self->{logfile});
        }
        if (!defined $self->{_logfh}) {
            warn "$!";
            exit TEMPFAIL;
        }
    }
    
    my $blurb = &strftime('%b %d %H:%M:%S', (localtime())).' ['.$$.'] '.$what."\n";
    $self->{_logfh}->print($blurb);
}

sub lock {
    my ($self, $lockfile) = @_;
    my $lock = POSIX::open($lockfile, POSIX::O_CREAT|POSIX::O_EXCL, 0444);
    my $tries = 1;
  CREAT:
    while ((!defined $lock) and ($tries < $self->{locktries})) {
        if ($! == POSIX::EEXIST) {
            if ($self->{callback}) {
                &{$self->{callback}}($lockfile, $tries);
            }
            sleep($self->{lockwait});
            $lock = POSIX::open($lockfile, POSIX::O_CREAT|POSIX::O_EXCL, 0444);
            $tries += 1;
            next CREAT;
        } else {
            $self->log(0, "lockfile $lockfile creation failed: $!");
            exit TEMPFAIL;
        }
    }

    if (!defined $lock) {
        $self->log(0, "cannot create lockfile $lockfile after $self->{locktries} tries");
        exit TEMPFAIL;
    }

    &POSIX::close($lock);
}

sub unlock {
    my ($self, $lockfile) = @_;
    unlink $lockfile;
}

sub deliver {
    my ($self, $target) = (shift, shift);
    my $keep = 0;
    my $lockfile = '';
    my $label = undef;

    if ($target =~ />>\s*(\S+)/ ) {
        my $subtarget = $1;
        $lockfile = $subtarget.'.lock';
    }

    my ($arg, $val) = (shift, shift);
    while (defined $arg and defined $val) {
        if ($arg eq 'keep') { $keep = $val; }
        elsif ($arg eq 'lockfile') { $lockfile = $val; }
        elsif ($arg eq 'label') { $label = $val; }
        else { $self->log(1, "$arg is not a valid key for Mail::Sort::deliver"); }
        ($arg, $val) = (shift, shift);
    }
    
    $self->log(2, "delivering to $target ; keep = $keep", $label);
    if ($lockfile) {
        $self->lock($lockfile);
    }
    local $? ;                  # make sure to get status of fh->close() below 
    my $fh = new FileHandle($target);
    if (!$fh) {
        $self->unlock($lockfile) if $lockfile;
        $self->log(0, "cannot deliver to $target: $!");
        exit TEMPFAIL unless $keep;
        return 0;
    }
    eval {
        local $SIG{PIPE} = sub { die 'just a SIGPIPE'; };
        $self->{obj}->print($fh);
    } unless $self->{test};
    $fh->close();
    $self->unlock($lockfile) if $lockfile;

    if ($@ and $@ ne 'just a SIGPIPE') {
        $self->log(0, "cannot deliver to $target: $@");
        exit TEMPFAIL unless $keep;
        return 0;
    }
    if ($? and (not WIFSIGNALED($?)
                or (WIFSIGNALED($?) and WTERMSIG($?) != $self->{signo}->{PIPE}))) {
        $self->log(0, "delivery subprocess exited with status $?");
        exit TEMPFAIL unless $keep;
        return 0;
    }

    exit DELIVERED unless $keep;
    return 1;
}

@Mail::Sort::sendmails = ('/usr/sbin/sendmail', '/usr/lib/sendmail');

sub forward {
    my ($self, $target) = (shift, shift);
    my $keep = 0;
    my $label = undef;

    my ($arg, $val) = (shift, shift);
    while (defined $arg and defined $val) {
        if ($arg eq 'keep') { $keep = $val; }
        elsif ($arg eq 'label') { $label = $val; }
        else { $self->log(1, "$arg is not a valid key for Mail::Sort::forward"); }
        ($arg, $val) = (shift, shift);
    }

    # hmmm, we have a dilemma here.  we could send the message using
    # the Mail::Internet smtpsend method, but there may actually not
    # be a smtp listener on localhost (there often isn't on
    # dialup-hooked machines, unless people use fetchmail).  Or we
    # could pipe to sendmail or any of its clones, but where is
    # sendmail?  $Config{sendmail} cannot be relied on - on my machine
    # the Perl binary package maintainer set it to '', even though
    # there is a perfectly good /usr/sbin/sendmail (and it is in fact
    # a required part of the system).  Let's try it both ways.

    if ($Config{sendmail}) {
        return $self->deliver('| '.$Config{sendmail}." -i $target",
                              keep => $keep, label => $label);
    } else {
        #arrrgh, exactly as I feared, some systems don't have either the
        #config variable or SMTP.  Like my tester's system :-(
        my $real_sendmail = undef;
      SENDMAIL:
        foreach my $maybe_sendmail (@Mail::Sort::sendmails) {
            if (-x $maybe_sendmail) {
                $real_sendmail = $maybe_sendmail;
                last SENDMAIL;
            }
        }
        if ($real_sendmail) {
            return $self->deliver('| '.$real_sendmail." -i $target",
                                  keep => $keep, label => $label);
        } else {
            $self->log(2, "smtp forwarding to $target", $label);
            my $status = 1;
            $status = scalar($self->{obj}->smtpsend(To => $target)) unless $self->{test};
            exit ($status ? DELIVERED : TEMPFAIL) unless $keep;
            return $status;
        }
    }

}

sub ignore {
    my ($self, $label) = @_;
    $self->deliver('| '.$Config{cat}.' > /dev/null', label => $label); # literally :-)
}

sub make_from_line {
    my $self = $_[0];
    return "$self->{envelope_from} " . &POSIX::strftime('%a %b %d %H:%M:%S %Y', localtime);
}

# various junk matching recipes
sub fake_received {
    my $self = $_[0];
    return ($self->header_match('received', '\[[[0-9.]*([03-9][0-9][0-9]|2[6-9][0-9]|25[6-9])') or
            $self->header_match('Received', 'from Unknown/Local') or
            $self->header_match('received', 'unknown host') or
            $self->header_match('Received', 'from HOST') or
            $self->header_match('Received', 'HELO HOST'));
}

sub missing_required {
    my $self = $_[0];
    return !$self->header_match('from') or !$self->header_match('date');
}

sub overflow_attempt {
    my $self = $_[0];
    return $self->header_match('received',
'.....................................................\
..........................................................................\
..........................................................................\
..........................................................................\
..........................................................................\
..........................................................................\
..........................................................................\
..........................................................................\
..........................................................................\
..........................................................................\
..........................................................................\
..........................................................................\
..........................................................................\
..........................................................................');
}

sub bad_x_uidl {
    my $self = $_[0];
    return ($self->header_match('x-uidl') and
            !$self->header_start('x-uidl',"[ 	]*[0-9a-f]+[ 	]*\$"));
}

sub oceanic_date {
    my $self = $_[0];
    return $self->header_match('(date|received)','-0600 \(EST\)');
}

sub empty_header {
    my $self = $_[0];
    return $self->header_start('(from|to|reply-to)', "[ 	]*[<>]*[ 	]*\$");
}

sub visible_bcc {
    my $self = $_[0];
    return $self->header_match('bcc');
}

sub asian_origin {
    my $self = $_[0];
    return ($self->header_match('(from|subject)','(=\?gb2312\?|[\x80-\xff][\x80-\xff][\x80-\xff][\x80-\xff]|=[89][0-9A-F]=[89][0-9A-F]=[89][0-9A-F]=[89][0-9A-F])') or
            grep /[\x80-\xff][\x80-\xff][\x80-\xff][\x80-\xff]|=[89][0-9A-F]=[89][0-9A-F]=[89][0-9A-F]=[89][0-9A-F]/, @{$self->{body}} );
}

sub no_message_id {
    my $self = $_[0];
    return (not $self->header_start('message-id',"\\s*<\\s*[^> ][^>]*\\s*>\\s*(\\(added by [^<>()]+\\)\\s*)?\$"));
}

1;
