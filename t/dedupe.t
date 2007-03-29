#$Id: deliver.t 2 2006-02-18 04:34:40Z itz $

use Test;

BEGIN { plan tests => 16 * 3 + 3 };

use Mail::Sort::Dedupe;
use FileHandle;

my @ids = qw(ait2cieKaeFa0phu QuaeR9usheiphang Adeekaey4uquim9i tath0vieZa7ushef
ohfush3pooZee1zo haigoo5UceixaiKa Pee5Ohthohghee0b yi1aH7aitaeka6op
geiJohdo8Lae7ieG Aic7HutheeJi6wok UuSh6giangiec8za joeWu1eQu6ZieBaz
eo9ohyew7Ue6laix otai6Shoxuvou0ei du3xunohef0eeGe7 Wi2jaengo5wuD4aS
Ixeilahta3ohz7ot);

my $test_d = "test.d." . `date +%Y%m%d%H%M%S`;
chomp $test_d;

for my $i (0..15) {
    $found = probe ($ids[$i], $test_d, clean_period => 5, ttl => 10);
    ok(!$found);
}

for my $i (0..15) {
    $found = probe ($ids[$i], $test_d, clean_period => 5, ttl => 10);
    ok($found);
}

sleep (3);

for my $i (16) {
    $found = probe ($ids[$i], $test_d, clean_period => 5, ttl => 10);
    ok(!$found);
}

sleep (8);

for my $i (16) {
    $found = probe ($ids[$i], $test_d, clean_period => 5, ttl => 10);
    ok($found);
}

for my $i (0..15) {
    $found = probe ($ids[$i], $test_d, clean_period => 5, ttl => 10);
    ok(!$found);
}

for my $i (16) {
    $found = probe ($ids[$i], $test_d, clean_period => 5, ttl => 10);
    ok($found);
}

system ("rm -rf $test_d");
