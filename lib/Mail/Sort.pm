# $Id: Sort.pm,v 1.1 2006/02/15 05:18:05 itz Exp $

package Mail::Sort;

@ISA = qw(Exporter);
@EXPORT = qw(TEMPFAIL DELIVERED);

no warnings qw(digit);

$VERSION = '$Date: 2006/02/15 05:18:05 $ '; $VERSION =~ s|^\$Date:\s*([0-9]{4})/([0-9]{2})/([0-9]{2})\s.*|\1.\2.\3| ;


use FileHandle 2.00;
use Mail::Internet 1.33;
use Mail::Header 1.19;
use POSIX 1.03 qw(close strftime WIFSIGNALED WTERMSIG O_CREAT O_EXCL EEXIST);
use Config;

use constant TEMPFAIL	=> 75;
use constant DELIVERED	=> 0;
use strict;
use v5.6.0;

our %signo = do { my $i = 0; map {$_, $i++} split(' ', $Config{sig_name}) };

# Where is sendmail?  $Config{sendmail} cannot be relied on - on my
# machine the Perl binary package maintainer set it to '', even though
# there is a perfectly good /usr/sbin/sendmail (and it is in fact a
# required part of the system).  Let's try it both ways.

our ($sendmail) = grep -x, ($Config{sendmail}, '/usr/sbin/sendmail', '/usr/lib/sendmail');

our %objkeys = map {$_, 1} qw(test logfile loglevel lockwait locktries callback envelope_from from_line);

sub _copy_from_array {
    my $self = shift;
    if ( $_[0] =~ m( ^From\s+(\S+) )x ) {
        $self->{envelope_from} = $1;
        $self->{from_line} = $_[0];
        shift;
    }
    $self->{obj} = new Mail::Internet(\@_, Modify => 0) or exit TEMPFAIL;
}

sub new {
    my $self = { };
    my $class = shift;

    for (ref $_[0]) {
        /^Mail::Internet/ and $self->{obj} = shift, last;
        /^ARRAY/          and &_copy_from_array($self, @{shift @_}), last;
        /^FileHandle/     and &_copy_from_array($self, shift->getlines), last;
        my $fh = new FileHandle;
        if (!$fh->fdopen(0, '<')) {
            $self->log(0, "$!");
            exit TEMPFAIL;
        }
        &_copy_from_array($self, $fh->getlines);
    }

  VAL:    
    while(1) {
        my ($arg, $val) = splice(@_, 0, 2);
        defined $val or last VAL;
        $self->{$arg} = $val, next VAL if $objkeys{$arg};
        &log($self, 1, "$arg is not a valid key for new Mail::Sort::new");
    }

    $self->{'logfile'} ||= '/dev/null';
    $self->{'loglevel'} ||= 1;
    $self->{'lockwait'} ||= 5;
    $self->{'locktries'} ||= 10;
    $self->{'envelope_from'} ||= "$ENV{LOGNAME}\@localhost";
    $self->{'from_line'} ||= &make_from_line ($self);
    
    my $head = $self->{obj}->head->dup(); # create a dup because we'll modify this one
    $head->modify(0);
    $head->unfold();
    $self->{head} = $head->header;
    $self->{body} = $self->{obj}->body;
    $self->{all_matches} = [ ];
    $self->{matches} = [ ];
    $self->{_sendmail} = $sendmail;
    $self->{_signo} = \%signo;
    bless $self, $class;
}

sub _save_match {
    my ($self, $line) = @_;
    $self->log(3, $line, 'header match');
    my @matches = ( );
    for (my $i = 0; $i <= $#-; $i++) {
        $matches[$i] = substr($line, $-[$i], $+[$i] - $-[$i]) if defined $-[$i];
    }
    push @{$self->{all_matches}}, \@matches;
    1;
}

sub header_match {
    my ($self, $tag, $pattern, $context) = @_;
    defined $context or $context = '.*';
    defined $pattern or $pattern = '' ;
    $tag = '(?i)' . $tag unless $tag =~ m( [A-Z] )x;
    my $rx = qr(^$tag:$context$pattern);

    $self->{all_matches} = [ ];
    my @lines = grep { /$rx/ and &_save_match($self, $_) } @{$self->{head}};
    $self->{matches} = $self->{all_matches}->[$#lines];
    @lines;
}

sub match_group {
    my ($self, $index) = @_;
    $self->{matches}->[$index];
}

sub header_start {
    my ($self, $tag, $pattern) = @_;
    $self->header_match($tag, $pattern, '\s*');
}

sub destination_match {
    my ($self, $pattern, $context) = @_;
    $self->header_match
        ('(?:(?:original-)?(?:resent-)?(?:to|cc|bcc)|(?:x-envelope|apparently(?:-resent)?)-to)',
         $pattern, $context);
}

sub destination_address {
    my ($self, $address) = @_;
    $self->destination_match($address, '(?:.*[^-a-z0-9_.])?');
}

sub destination_word {
    my ($self, $word) = @_;
    $self->destination_match($word, '(?:.*[^a-z])?');
}

sub sender_match {
    my ($self, $pattern, $context) = @_;
    $self->header_match
        ('(?:(?:resent-)?sender|resent-from|return-path)',
         $pattern, $context); 
}

sub log {
    my ($self, $level, $what, $label) = @_;
    chomp $what;
    ($self->{logfile} and $level <= $self->{loglevel}) or return;

    $self->{_logfh} = ref $self->{logfile} eq 'FileHandle' ?
        $self->{logfile} : new FileHandle('>>'.$self->{logfile})
        unless exists $self->{_logfh};

    if (!defined $self->{_logfh}) {
        warn "$!";
        exit TEMPFAIL;
    }
    
    $self->{_logfh}->print(&strftime('%b %d %H:%M:%S', (localtime())),' [', $$ ,'] ');
    $self->{_logfh}->print('(', $label,') ') if $label;
    $self->{_logfh}->print($what, "\n");
}

sub lock {
    my ($self, $lockfile) = @_;
    my $lock;
  CREAT:
    for (my $tries = 1; $tries <= $self->{locktries}; $tries++) {
        $lock = POSIX::open($lockfile, POSIX::O_CREAT|POSIX::O_EXCL, 0444);
        last CREAT if defined $lock;
        if ($! == POSIX::EEXIST) {
            &{$self->{callback}}($lockfile, $tries) if $self->{callback};
            sleep($self->{lockwait});
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
    my ($self, $target) = splice(@_, 0, 2);
    my ($keep, $lockfile, $label, $mbox);
    $target =~ m( >>\s*(\S+) )x and $lockfile = $1 . '.lock';

  VAL:
    while (1) {
        my ($arg, $val) = splice(@_, 0, 2);
        defined $val or last VAL;
        for ($arg) {
            /^keep/		and $keep = $val,	next VAL;
            /^lockfile/         and $lockfile = $val,   next VAL;
            /^label/            and $label = $val,      next VAL;
            /^mbox/             and $mbox = $val,       next VAL;
            $self->log(1, "$arg is not a valid key for Mail::Sort::deliver");
        }
    }
    
    $self->log(2, "delivering to $target", $label);
    $self->lock($lockfile) if ($lockfile);

    my $write_st = 1;
    my $fh = new FileHandle($target);
    if (!$fh) {
        $self->log(0, "cannot deliver to $target: $!");
        $write_st = 0;
    } else {
        local ($SIG{PIPE}, $?) = 'IGNORE'; # make sure to get status of fh->close() below 
        if (!$self->{test}) {
            $write_st = $fh->print ($self->{from_line})
                if $mbox;
            $write_st = $self->{obj}->print($fh)
                if $write_st;
            my $last_line = scalar (@{$self->{body}}) - 1;
            $write_st = $fh->print ("\n")
                if $write_st && $mbox && $last_line >= 0
                && ${$self->{body}} [$last_line] ne "\n";
        }
        $fh->close();
        if ($? and (not WIFSIGNALED($?) or WTERMSIG($?) != $self->{_signo}->{PIPE})) {
            $self->log(0, "delivery subprocess exited with status $?");
            $write_st = 0;
        }
    }
    $self->unlock($lockfile) if $lockfile;
    exit ($write_st ? DELIVERED : TEMPFAIL) unless $keep;
    $write_st;
}

sub forward {
    my ($self, $target) = splice(@_, 0, 2);
    my ($keep, $label);

  VAL:
    while (1) {
        my ($arg, $val) = splice(@_, 0, 2);
        defined $val or last VAL;
        for ($arg) {
            /^keep/		and $keep = $val, next VAL;
            /^label/            and $label = $val, next VAL;
            $self->log(1, "$arg is not a valid key for Mail::Sort::forward");
        }
    }
    return $self->deliver(join('','| ', $self->{_sendmail}," -i $target"),
                          keep => $keep, label => $label) if $self->{_sendmail};

    $self->log(2, "smtp forwarding to $target", $label);
    my $status = $self->{test} or scalar($self->{obj}->smtpsend(To => $target));
    exit ($status ? DELIVERED : TEMPFAIL) unless $keep;
    $status;
}

sub ignore {
    my ($self, $label) = @_;
    $self->deliver(join('','| ', $Config{cat},' > /dev/null'),
                   label => $label); # literally :-)
}

sub make_from_line {
    my $self = $_[0];
    "$self->{envelope_from} " . &POSIX::strftime('%a %b %d %H:%M:%S %Y', localtime);
}

# various junk matching recipes
sub fake_received {
    my $self = $_[0];
    $self->header_match('received', '\[[[0-9.]*([03-9][0-9][0-9]|2[6-9][0-9]|25[6-9])')
        or $self->header_match('Received', 'from Unknown/Local')
        or $self->header_match('received', 'unknown host')
        or $self->header_match('Received', 'from HOST')
        or $self->header_match('Received', 'HELO HOST');
}

sub missing_required {
    my $self = $_[0];
    !$self->header_match('from') or !$self->header_match('date');
}

sub invalid_date {
    my $self = $_[0];
    !$self->header_match('date','(?:(?:Mon|Tue|Wed|Thu|Fri|Sat|Sun), )?[0-3 ]?[0-9] (?:Jan|Feb|Ma[ry]|Apr|Ju[nl]|Aug|Sep|Oct|Nov|Dec) (?:[12][901])?[0-9]{2} [0-2][0-9](?:\:[0-5][0-9]){1,2} (?:[+-][0-9]{4}|UT|[A-Z]{2,3}T)(?:\s+\(.*\))?');
}

sub overflow_attempt {
    my $self = $_[0];
    $self->header_match('received',
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
    $self->header_match('x-uidl')
        and !$self->header_start('x-uidl',"[ 	]*[0-9a-f]+[ 	]*\$");
}

sub oceanic_date {
    my $self = $_[0];
    $self->header_match('(date|received)','-0600 \(EST\)')
        or $self->header_match('date','[-+](?:1[4-9]\d\d|[2-9]\d\d\d)');
}

sub empty_header {
    my $self = $_[0];
    $self->header_start('(from|to|reply-to)', "[ 	]*[<>]*[ 	]*\$");
}

sub visible_bcc {
    my $self = $_[0];
    $self->header_match('bcc');
}

sub eight_bit_header {
    my $self = $_[0];
    $self->header_match('(from|subject)','[\x80-\xff][\x80-\xff][\x80-\xff][\x80-\xff]');
}

sub faraway_charset {
    my $self = shift;
    my $charsets_rx = '(' . join('|', @_) . ')';
    $self->header_start('(from|subject)',join('','=\?', $charsets_rx, '\?'))
        or $self->header_match('content-type',join('','charset="', $charsets_rx, '"'));
}

sub asian_origin {
    my $self = $_[0];
    $self->eight_bit_header() or $self->faraway_charset('iso-?2022-?jp', 'gb-?2312');
}

sub no_message_id {
    my $self = $_[0];
    not $self->header_start('message-id',"\\s*<\\s*[^> ][^>]*\\s*>\\s*(\\(added by [^<>()]+\\)\\s*)?\$");
}

sub strange_mime {
    my $self = $_[0];
    $self->header_match('MiME-Version');
}

sub subject_free_caps {
    my $self = $_[0];
    $self->header_match('Subject', '\bFREE\b');
}

sub subject_all_caps {
   my $self = $_[0];
   not $self->header_match('Subject','[a-z]');
}

sub subject_has_spaces {
    my $self = $_[0];
    $self->header_match('subject','( {6}|[\t])\S');
}

sub too_many_recipients {
    my ($self, $limit) = @_;
    $self->destination_match("(,.*){$limit}");
}

sub html_only {
    my $self = $_[0];
    $self->header_match('content-type','text/html');
}

sub address_as_realname {
    my $self = $_[0];
    $self->header_start('"([^"@]+\@[^"@]+)"\s+<\1>');
}

sub base64_text {
    my $self = $_[0];
    $self->header_match('content-type','text/plain')
        and $self->header_match('content-transfer-encoding','base64');
}

sub missing_mimeole {
    my $self = $_[0];
    $self->header_match('x-msmail-priority')
        # squirrelmail seems to insert this header, so make an exception for it
        and not $self->header_match('x-mailer','squirrelmail')
        and not $self->header_match('x-mimeole');
}

sub msgid_spam_chars {
    my $self = $_[0];
    $self->header_match('message-id','[:}{,!\/]');
}

sub from_ends_in_digit {
    my $self = $_[0];
    $self->header_match('from','\d\@');
}

sub received_by_smtpd32 {
    my $self = $_[0];
    $self->header_match('received','smtpd32');
}

# razor integration

sub razor_check {
    require Razor::String;
    require Razor::Config;
    require Razor::Client;

    my $self = $_[0];
    my @lines = ("\n", @{$self->{body}});
    my $hash = Razor::String::hash (\@lines);
    my $config = Razor::Config::findconf('razor.conf');
    my $client = Razor::Client->new ($config);
    my $reply = $client->check(sigs => [$hash]);
    defined $reply && return $reply->[0];
    $self->log(1, "razor check failed: $Razor::Client::errstr");
    0;
}

# spamassassin integration

sub spamassassin_check {
    require Mail::SpamAssassin;

    my $self = shift;
    my $checker = { @_ };
    Mail::SpamAssassin->new($checker);
    my $status = $checker->check_message_text($self->{obj}->as_string());
    my $total = $status->get_hits();
    my @hits = split /\s*,\s*/, $status->get_names_of_tests_hit();
    my $report = $status->get_report();
    my %hitlist = ('total' => $total);
    foreach (@hits) {
        $report =~ m( \n\s*SPAM:\s*$_\s*\((-?[0-9]+\.[0-9]+) )x ;
        $hitlist{$_} = $1;
    }
    $status->finish();
    return \%hitlist;
}

1;


