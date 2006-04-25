# $Id: Base.pm 21 2006-04-21 05:20:33Z itz $

package Mail::Sort::Base;

no warnings qw(digit);

use FileHandle 2.00;
use POSIX 1.03 qw(close pipe strftime WIFSIGNALED WTERMSIG O_CREAT O_EXCL EEXIST);
use Config;
use IPC::Open2;
use Mail::Sort::Dedupe qw(probe);

use strict;
use v5.6.0;

my %signo = do { my $i = 0; map {$_, $i++} split(' ', $Config{sig_name}) };

# Where is sendmail?
my ($sendmail) = grep -x, ('/usr/sbin/sendmail', '/usr/lib/sendmail', '/sbin/sendmail', '/lib/sendmail');

my $tag_pat = qr{^([^\x00-\x1f\x7f-\xff :]+):};

sub _copy_from_array {
    my $self = shift;
    if ( @_ && $_[0] =~ m( ^From\s+(\S+) )x ) {
        $self->{envelope_from} = $1;
        $self->{_from_mbox} = 1;
        shift;
    }
    $self->{head} = [ ];
    my $line = shift;
    while (defined $line && $line =~ m($tag_pat)) {
        $line .= shift while @_ and $_[0] =~ m(^[ \t]+[^ \t]);
        push @{$self->{head}}, $line;
        $line = shift;
    }
    die "Malformed mail" if defined $line and $line ne "\n";
    $self->{body} = \@_;
}

sub _copy_from_fh {
    my ($self, $fh) = splice (@_, 0, 2);
    my $line = $fh->getline;
    if (defined $line && $line =~ m( ^From\s+(\S+) )x ) {
        $self->{envelope_from} = $1;
        $self->{_from_mbox} = 1;
        $line = $fh->getline;
    }
    $self->{head} = [ ];
    while (defined $line && $line =~ m($tag_pat)) {
        my $cline = $fh->getline;
        while (defined $cline && $cline =~ m(^[ \t]+[^ \t])) {
            $line .= $cline;
            $cline = $fh->getline;
        }
        push @{$self->{head}}, $line;
        undef $line;
        $line = $cline if defined $cline;
    }
    die "Malformed mail" if defined $line and $line ne "\n";
    $self->{body} = [ ];
    $line = $fh->getline if defined $line;
    while (defined $line) {
        push @{$self->{body}}, $line;
        $line = $fh->getline;
    }
}

sub _copy_from_self {
    my ($self, $parent) = splice (@_, 0, 2);
    my ($readp, $writep) = POSIX::pipe;
    die "$!" unless defined $readp and defined $writep;
    my ($readfh, $writefh) = (FileHandle->new_from_fd ($readp), FileHandle->new_from_fd ($writep));
    $parent->_print_to_fh ($writefh, 1);
    $writefh->close ();
    &_copy_from_fh ($self, $readfh);
    $readfh->close ();
}

sub new {
    my $self = { };
    my $class = shift;
    my %objkeys = map {$_, 1} qw(test logfile loglevel lockwait locktries callback envelope_from);

    for (ref $_[0]) {
        /^Mail::Sort/     and &_copy_from_self($self, shift), last;
        /^ARRAY/          and &_copy_from_array($self, @{shift @_}), last;
        /^FileHandle/     and &_copy_from_fh($self, shift), last;
        my $fh = new FileHandle;
        if (!$fh->fdopen(0, '<')) {
            $self->log(0, "$!");
            die "$!";
        }
        &_copy_from_fh($self, $fh);
    }

  VAL:    
    while(1) {
        my ($arg, $val) = splice(@_, 0, 2);
        defined $val or last VAL;
        $self->{$arg} = $val, next VAL if $objkeys{$arg};
        &log($self, 1, "$arg is not a valid key for new Mail::Sort::new");
    }

    $self->{_from_mbox} = 0 unless defined $self->{_from_mbox};
    $self->{logfile} ||= '/dev/null';
    $self->{loglevel} ||= 1;
    $self->{lockwait} ||= 5;
    $self->{locktries} ||= 10;
    $self->{envelope_from} ||= "$ENV{LOGNAME}\@localhost";
    
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
    if ($tag =~ m( [A-Z] )x) {
        $tag = '(?s)' . $tag;
    } else {
        $tag = '(?is)' . $tag;
    }
    my $rx = qr(^$tag:$context$pattern);
    my @head = @{$self->{head}};

    $self->{all_matches} = [ ];
    my @lines = grep { $head[$_] =~ $rx and &_save_match($self, $head[$_]) } (0..$#head);
    $self->{matches} = $self->{all_matches}->[$#lines];
    @lines;
}

sub get_header {
    my ($self, @indices) = @_;
    return map { ${$self->{head}}[$_] } @indices;
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

    defined $self->{_logfh} or die "$!";
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
        if ($! != POSIX::EEXIST) {
            $self->log(0, "lockfile $lockfile creation failed: $!");
            die "$!";
        }
        &{$self->{callback}}($lockfile, $tries) if $self->{callback};
        sleep($self->{lockwait});
    }

    if (!defined $lock) {
        $self->log(0, "cannot create lockfile $lockfile after $self->{locktries} tries");
        die "$!";
    }

    &POSIX::close($lock);
}

sub unlock {
    my ($self, $lockfile) = @_;
    unlink $lockfile;
}

sub _print_to_fh {
    my ($self, $fh, $mbox) = @_;
    $fh->print ($self->make_from_line) or die "$!" if $mbox;
    $fh->print ($_) or die "$!" for (@{$self->{head}});
    $fh->print ("\n") or die "$!";
    foreach my $bl (@{$self->{body}}) {
        my $line = $bl;
        $line =~ s{^(>*From )}{>$1} if $mbox && !$self->{_from_mbox};
        $fh->print ($line) or die "$!" ;
    }
    $fh->print ("\n") or die "$!" if $mbox && !$self->{_from_mbox};
    1;
}

sub filter {
    my ($self, $child_argv, $label) = @_;
    $self->log(2, "filtering with ${$child_argv}[0]", $label);
    my ($fout, $fin) = (FileHandle->new, FileHandle->new);
    local $SIG{PIPE} = 'IGNORE'; # make sure to get status of fh->close() below
    local $?;
    my $child = open2 ($fout, $fin, @{$child_argv});
    my $status = eval { $self->_print_to_fh ($fin, 0) };
    $fin->close ();
    $self->log(0, "cannot filter with ${$child_argv}[0]: $!"), die unless $status;
    $self->_copy_from_fh($fout);
    $fout->close();
    waitpid ($child, 0);
    if ($? and (not WIFSIGNALED($?) or WTERMSIG($?) != $self->{_signo}->{PIPE})) {
        $self->log(0, "filter subprocess exited with status $?");
        die "filter subprocess exited with status $?";
    }
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
    my $fh = new FileHandle($target);
    if (!$fh) {
        $self->unlock ($lockfile) if $lockfile;
        $self->log(0, "cannot deliver to $target: $!");
        die "$!";
    }
    local $SIG{PIPE} = 'IGNORE'; # make sure to get status of fh->close() below
    local $?;
    my $status = 1;
    $status = eval { $self->_print_to_fh ($fh, $mbox) } unless $self->{test};
    $fh->close();
    $self->unlock ($lockfile) if $lockfile;
    $self->log(0, "cannot deliver to $target: $!"), die unless $status;
    if ($? and (not WIFSIGNALED($?) or WTERMSIG($?) != $self->{_signo}->{PIPE})) {
        $self->log(0, "delivery subprocess exited with status $?");
        die "delivery subprocess exited with status $?";
    }
    exit 0 unless $keep;
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
    if (!$self->{_sendmail}) {
        $self->log (0, "no sendmail");
        die "no sendmail";
    }
    $self->deliver(join('','| ', $self->{_sendmail}," -i $target"),
                   keep => $keep, label => $label);
}

sub ignore {
    my ($self, $label) = @_;
    $self->deliver('> /dev/null', label => $label); # literally :-)
}

sub make_from_line {
    my $self = $_[0];
    "From $self->{envelope_from} " . &POSIX::strftime('%a %b %d %H:%M:%S %Y', localtime) . "\n";
}

sub add_header_at {
    my ($self, $line, $index, $label) = @_;
    $self->log(3, "adding header at $index", $label);
    splice (@{$self->{head}}, $index, 0, $line);
    $line;
}

sub append_header {
    my ($self, $line, $label) = @_;
    $self->log(3, "appending header", $label);
    push @{$self->{head}}, $line;
    $line;
}

sub append_header_if_absent {
    my ($self, $line, $label) = @_;
    $line =~ m($tag_pat) or die "Malformed header";
    my $tag = lc ($1);
    my @matches = $self->header_match ($tag);
    $self->append_header ($line, $label) unless @matches;
}

sub add_header_before {
    my ($self, $line, $tag, $index, $label) = @_;
    my @matches = $self->header_match ($tag);
    return undef unless $#matches >= $index;
    $self->add_header_at ($line, $matches[$index], $label);
}

sub add_header_after {
    my ($self, $line, $tag, $index, $label) = @_;
    my @matches = $self->header_match ($tag);
    return undef unless $#matches >= $index;
    $self->add_header_at ($line, $matches[$index] + 1, $label);
}

sub delete_header_at {
    my ($self, $index, $label) = @_;
    $self->log(3, "deleting header at $index", $label);
    splice (@{$self->{head}}, $index, 1);
}

sub delete_header_tag {
    my ($self, $tag, $index, $label) = @_;
    my @matches = $self->header_match ($tag);
    return undef unless $#matches >= $index;
    $self->delete_header_at ($matches[$index], $label);
}

sub delete_header_tag_all {
    my ($self, $tag, $label) = @_;
    my @matches = $self->header_match ($tag);
    my @deleted = map { ${$self->{head}}[$matches[$_]] } (0..$#matches);
    while (@matches) {
        $self->delete_header_at ($matches[0], $label);
        shift @matches;
        map { --$matches[$_] } (0..$#matches);
    }
    @deleted;
}

sub replace_header_at {
    my ($self, $line, $index, $label) = @_;
    $self->log(3, "replacing header at $index", $label);
    $self->{head}->[$index] = $line;
}

sub replace_header_tag {
    my ($self, $line, $tag, $index, $label) = @_;
    my @matches = $self->header_match ($tag);
    return undef unless $#matches >= $index;
    $self->replace_header_at ($line, $matches[$index], $label);
}

sub transform_header_at {
    my ($self, $xform, $index, $label) = @_;
    $self->log(3, "transforming header at $index", $label);
    &{$xform}(\$self->{head}->[$index]);
}

sub transform_header_tag {
    my ($self, $xform, $tag, $index, $label) = @_;
    my @matches = $self->header_match ($tag);
    return undef unless $#matches >= $index;
    $self->transform_header_at ($xform, $matches[$index], $label);
}

sub rename_header_at {
    my ($self, $newtag, $index, $label) = @_;
    $self->log(3, "renaming header at $index", $label);
    $self->{head}->[$index] =~ s{$tag_pat}{$newtag:};
}

sub rename_header_tag {
    my ($self, $newtag, $tag, $index, $label) = @_;
    my @matches = $self->header_match ($tag);
    return undef unless $#matches >= $index;
    $self->rename_header_at ($newtag, $matches[$index], $label);
}

sub rename_header_tag_all {
    my ($self, $newtag, $tag, $label) = @_;
    my @matches = $self->header_match ($tag);
    map { $self->rename_header_at ($newtag, $matches[$_], $label) } (0..$#matches);
}

sub append_header_and_rename {
    my ($self, $line, $label) = @_;
    $line =~ m($tag_pat) or die "Malformed header";
    my ($tag, $lctag) = ($1, lc ($1));
    $self->rename_header_tag_all ('X-Original-' . $tag, $lctag, $label);
    $self->append_header ($line, $label);
}

sub uniquify_tag_first {
    my ($self, $tag, $label) = @_;
    my @matches = $self->header_match ($tag);
    return () unless shift @matches;
    my @deleted = map { ${$self->{head}}[$matches[$_]] } (0..$#matches);
    while (@matches) {
        $self->delete_header_at ($matches[0], $label);
        shift @matches;
        map { --$matches[$_] } (0..$#matches);
    }
    @deleted;
}

sub uniquify_tag_last {
    my ($self, $tag, $label) = @_;
    my @matches = $self->header_match ($tag);
    return () unless pop @matches;
    my @deleted = map { ${$self->{head}}[$matches[$_]] } (0..$#matches);
    while (@matches) {
        $self->delete_header_at ($matches[0], $label);
        shift @matches;
        map { --$matches[$_] } (0..$#matches);
    }
    @deleted;
}

sub dedupe {
    my ($self, $path, $keep) = @_;
    return unless $self->header_match ('message-id', '(<[^\s>]+>)', '\s*');
    my $msgid = ${$self->{matches}} [1];
    my $lockpath = $path . '.lock';
    $self->lock ($lockpath);
    my $found = eval { probe ($msgid, $path) };
    $self->unlock ($lockpath);
    $self->log (0, "$@"), die unless defined $found;
    $self->ignore ('dedupe match') if $found && !$keep;
    $found;
}

1;


