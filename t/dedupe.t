#$Id: deliver.t 2 2006-02-18 04:34:40Z itz $

use Test;

BEGIN { plan tests => 16 * 6 + 16 * 6 + 1 * 6 + 7 * 6};

use Mail::Sort::Dedupe;

my @ids = qw(ait2cieKaeFa0phu QuaeR9usheiphang Adeekaey4uquim9i tath0vieZa7ushef
ohfush3pooZee1zo haigoo5UceixaiKa Pee5Ohthohghee0b yi1aH7aitaeka6op
geiJohdo8Lae7ieG Aic7HutheeJi6wok UuSh6giangiec8za joeWu1eQu6ZieBaz
eo9ohyew7Ue6laix otai6Shoxuvou0ei du3xunohef0eeGe7 Wi2jaengo5wuD4aS
Ixeilahta3ohz7ot eicahJ7tahXoomoo Ig4Weish6ena2yai Theighee4pie6ahz
Ohquai0eekaipeiV eiNu7aik2toleaPh ahghi6kaMeiheCat oJo6fiel8eishav3);

my $aux_line = "16 8 0\n";

my $fh = FileHandle->new (">test.aux");
defined $fh or die "$!";
$fh->print ($aux_line);
$fh->close;

my ($high_water, $low_water, $current, $first_id, $last_id, $found);

for my $i (0..15) {
    $found = probe ($ids[$i], 'test');
    ok(!$found);
    $fh = FileHandle->new ("<test.aux");
    defined $fh or die  "$!";
    $aux_line = $fh->getline;
    $fh->close;
    chomp, ($high_water, $low_water, $current, $first_id, $last_id) = split 
        for ($aux_line);
    ok ($high_water == 16);
    ok ($low_water == 8);
    ok ($current == $i + 1);
    ok ($first_id eq $ids[0]);
    ok ($last_id eq $ids[$i]);
}

for my $i (0..15) {
    $found = probe ($ids[$i], 'test');
    ok($found);
    $fh = FileHandle->new ("<test.aux");
    defined $fh or die  "$!";
    $aux_line = $fh->getline;
    $fh->close;
    chomp, ($high_water, $low_water, $current, $first_id, $last_id) = split 
        for ($aux_line);
    ok ($high_water == 16);
    ok ($low_water == 8);
    ok ($current == 16);
    ok ($first_id eq $ids[0]);
    ok ($last_id eq $ids[15]);
}

for my $i (16) {
    $found = probe ($ids[$i], 'test');
    ok(!$found);
    $fh = FileHandle->new ("<test.aux");
    defined $fh or die  "$!";
    $aux_line = $fh->getline;
    $fh->close;
    chomp, ($high_water, $low_water, $current, $first_id, $last_id) = split 
        for ($aux_line);
    ok ($high_water == 16);
    ok ($low_water == 8);
    ok ($current == 8);
    ok ($first_id eq $ids[9]);
    ok ($last_id eq $ids[16]);
}

for my $i (17..23) {
    $found = probe ($ids[$i], 'test');
    ok(!$found);
    $fh = FileHandle->new ("<test.aux");
    defined $fh or die  "$!";
    $aux_line = $fh->getline;
    $fh->close;
    chomp, ($high_water, $low_water, $current, $first_id, $last_id) = split 
        for ($aux_line);
    ok ($high_water == 16);
    ok ($low_water == 8);
    ok ($current == $i - 8);
    ok ($first_id eq $ids[9]);
    ok ($last_id eq $ids[$i]);
}

unlink ('test.aux');
unlink ('test.db');
