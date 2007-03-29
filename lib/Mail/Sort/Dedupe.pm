# $Id: Dedupe.pm 33 2007-03-29 15:14:43Z itz $

package Mail::Sort::Dedupe;

@ISA = qw(Exporter);
@EXPORT = qw(probe);

use File::Slurp;
use DB_File;

use constant
{
    ONE_DAY => 60 * 60 * 24,
    ONE_WEEK => 60 * 60 * 24 * 7,
};

sub probe {
    my ($id, $path) = splice(@_, 0, 2);
    my %params = @_;
    my ($clean_period, $ttl) = ($params{clean_period} || ONE_DAY, $params{ttl} || ONE_WEEK);
    my $now = time;
    mkdir ($path, 0700) || die "$!"
        unless -d $path;
    my $cleanfile = "$path/cleantime";
    write_file ($cleanfile, $now + $clean_period) unless -e $cleanfile;
    my $dbfile = "$path/db";
    tie my %id_db, 'DB_File', $dbfile, O_CREAT|O_RDWR, 0600, $DB_HASH
        or die "$dbfile: $!";
    my $result = exists $id_db{$id};
    $id_db{$id} = $now;
    my $cleantime = read_file ($cleanfile);
    chomp $cleantime;
    if ($now > $cleantime) {
        while (my ($k_id, $v_time) = each %id_db) {
            delete $id_db{$k_id} if ((+$v_time + $ttl) < $now);
        }
        $cleantime += $clean_period;
        $cleantime = $now + $clean_period if ($cleantime <= $now);
        write_file ($cleanfile, $cleantime);
    }
    untie %id_db;
    return $result;
}

1;
