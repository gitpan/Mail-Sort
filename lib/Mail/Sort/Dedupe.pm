# $Id: Dedupe.pm 7 2006-02-18 16:00:01Z itz $

package Mail::Sort::Dedupe;

@ISA = qw(Exporter);
@EXPORT = qw(probe);

use FileHandle 2.00;
use DB_File 1.811;

sub _read_aux_file {
    my $auxpath = $_[0];
    my $auxfh = FileHandle->new ("<$auxpath");
    defined $auxfh or die "$auxpath: $!";
    chomp, return split for ($auxfh->getline);
}

sub _write_aux_file {
    my ($high_water, $low_water, $current, $first_id, $last_id, $auxpath) = @_;
    my $auxfh = FileHandle->new (">$auxpath");
    defined $auxfh or die "$auxpath: $!";
    $auxfh->printf ("%d %d %d %s %s\n", $high_water, $low_water, $current,
                    $first_id, $last_id);
}

sub probe {
    my ($id, $path) = @_;
    my ($auxpath, $dbpath, $found) = ($path . '.aux', $path . '.db', 0);
    my ($high_water, $low_water, $current, $first_id, $last_id) =
        _read_aux_file ($auxpath);
    tie my %id_db, 'DB_File', $dbpath, O_CREAT|O_RDWR, 0600, $DB_HASH
        or die "$dbpath: $!";
    if ($current == 0) {
        $id_db{$id} = $first_id = $last_id = $id;
        $current = 1;
    } 
    elsif ($id_db{$id}) {
        $found = 1;
    } 
    else {
        $id_db{$last_id} = $id_db{$id} = $id;
        $last_id = $id;
        ++$current;
    }
    if ($current > $high_water) {
        while ($current > $low_water) {
            my $next_id = $id_db{$first_id};
            delete $id_db{$first_id};
            $first_id = $next_id;
            --$current;
        }
    }
    untie %id_db;
    _write_aux_file ($high_water, $low_water, $current, $first_id, $last_id, $auxpath);
    return $found;
}

1;
