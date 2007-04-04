# $Id: Dedupe.pm 36 2007-04-04 02:45:22Z itz $

package Mail::Sort::Dedupe;

@ISA = qw(Exporter);
@EXPORT = qw(probe);

use File::Slurp;
use Config;
use GDBM_File;
use DB_File;
use File::Spec::Functions qw(catfile);
use File::Path qw(mkpath rmtree);
use Mail::Sort qw(VERSION);
use strict;

use constant
{
    ONE_DAY => 60 * 60 * 24,
    ONE_WEEK => 60 * 60 * 24 * 7,
};

sub new {
    my $class = shift;
    my $self = { @_ };
    $self->{clean_period} ||= ONE_DAY;
    $self->{ttl} ||= ONE_WEEK;
    $self->{now} ||= time;

    $self->{dbfile} = catfile ($self->{path}, 'db');
    $self->{cleanfile} = catfile ($self->{path}, 'cleantime');
    my $db_create_mode;
    if ($Config{osname} =~ /bsd|darwin|dragonfly/i) {
        $self->{backend} = 'GDBM_File';
        $self->{tiemode} = &GDBM_WRITER|&GDBM_NOLOCK;
        $db_create_mode = &GDBM_NEWDB|&GDBM_NOLOCK;
    } else {
        $self->{backend} = 'DB_File';
        $self->{tiemode} = O_RDWR;
        $db_create_mode = O_RDWR|O_CREAT|O_TRUNC;
    }
    my ($first_compat, $last_compat) = (20070404, $Mail::Sort::VERSION);
    my $compat_file = catfile ($self->{path}, $self->{backend} . '_VERSION');
    my $need_create = 1;
    if (-f $compat_file) {
        my $compat = +read_file ($compat_file);
        $need_create = 0 if $first_compat <= $compat && $compat <= $last_compat;
    }
    if ($need_create) {
        rmtree ($self->{path}), mkpath ($self->{path}, 0, 0700) if $self->{path};
        write_file ($self->{cleanfile}, $self->{now} + $self->{clean_period});
        tie my %id_db, $self->{backend}, $self->{dbfile}, $db_create_mode, 0600
            or die "$self->{dbfile}: $!";
        untie %id_db;
        write_file ($compat_file, $Mail::Sort::VERSION);
    }
    bless $self, $class;
}

sub probe_and_record {
    my $self = $_[0];
    tie my %id_db, $self->{backend}, $self->{dbfile}, $self->{tiemode}, 0600
        or die "$self->{dbfile}: $!";
    my $result = exists $id_db{$self->{id}};
    $id_db{$self->{id}} = $self->{now};
    my $cleantime = read_file ($self->{cleanfile});
    chomp $cleantime;
    if ($self->{now} > $cleantime) {
        while (my ($k_id, $v_time) = each %id_db) {
            delete $id_db{$k_id} if ((+$v_time + $self->{ttl}) < $self->{now});
        }
        $cleantime += $self->{clean_period};
        $cleantime = $self->{now} + $self->{clean_period} if ($cleantime <= $self->{now});
        write_file ($self->{cleanfile}, $cleantime);
    }
    untie %id_db;
    return $result;
}

sub probe_only {
    my $self = $_[0];
    tie my %id_db, $self->{backend}, $self->{dbfile}, $self->{tiemode}, 0600
        or die "$self->{dbfile}: $!";
    my $result = exists $id_db{$self->{id}};
    untie %id_db;
    return $result;
}

sub record_only {
    my $self = $_[0];
    tie my %id_db, $self->{backend}, $self->{dbfile}, $self->{tiemode}, 0600
        or die "$self->{dbfile}: $!";
    $id_db{$self->{id}} = $self->{now};
    my $cleantime = read_file ($self->{cleanfile});
    chomp $cleantime;
    if ($self->{now} > $cleantime) {
        while (my ($k_id, $v_time) = each %id_db) {
            delete $id_db{$k_id} if ((+$v_time + $self->{ttl}) < $self->{now});
        }
        $cleantime += $self->{clean_period};
        $cleantime = $self->{now} + $self->{clean_period} if ($cleantime <= $self->{now});
        write_file ($self->{cleanfile}, $cleantime);
    }
    untie %id_db;
}

# functional interface for backward compatibility
sub probe {
    my ($id, $path) = splice(@_, 0, 2);
    my $obj = Mail::Sort::Dedupe->new (id => $id, path => $path, @_);
    return $obj->probe_and_record;
}

1;
