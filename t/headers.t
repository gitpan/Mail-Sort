#$Id: headers.t,v 1.1 2001/09/11 01:02:37 itz Exp $

use Test;

BEGIN { plan tests => 29 };

use Mail::Sort;

@data=(
       "From: me_myself_I\@localhost\n",
       "X-Strange: one two-three four_five six.seven\@eight\n",
       "X-Multiline: line one\n",
       " line two\n",
       "To: you_vous_Vy\@nowhere.one.org\n",
       "Sender: my_own_list\@nowhere.two.org\n",
       "\n",
       "From Myself, blah blah blah, this is a really stupid test message.\n",
       "Another line,\n",
       "\n",
       "and an empty one for fun.\n",
       );

$sort = new Mail::Sort(\@data, test => 1, logfile => '/dev/null');

@matches = $sort->header_match('from', 'myself');
ok($#matches, 0);
ok($matches[0], $data[0]);

@matches = $sort->header_match('From', 'Myself');
ok($#matches, -1);

@matches = $sort->header_match('from', 'm._(m.)');
ok($#matches, 0);
ok($matches[0], $data[0]);
ok($sort->match_group(1), 'my');

@matches = $sort->header_start('to', 'you');
ok($#matches, 0);
ok($matches[0], $data[4]);

@matches = $sort->header_start('to', 'vous');
ok($#matches, -1);

@matches = $sort->header_start('x-multiline', 'line one');
ok($#matches, 0);
$first_multi = $data[2];
chomp $first_multi;
ok($matches[0], join('', $first_multi, $data[3]));

@matches = $sort->header_start('x-multiline', 'line two');
ok($#matches, -1);

@matches = $sort->header_match('x-multiline', 'one line');
ok($#matches, 0);
ok($matches[0], join('', $first_multi, $data[3]));

@matches = $sort->destination_match('(one)');
ok($#matches, 0);
ok($matches[0], $data[4]);
ok($sort->match_group(1), 'one');

@matches = $sort->destination_match('two');
ok($#matches, -1);

@matches = $sort->destination_address('nowhere');
ok($#matches, 0);
ok($matches[0], $data[4]);

@matches = $sort->destination_address('vous_vy');
ok($#matches, -1);

@matches = $sort->destination_word('vous');
ok($#matches, 0);
ok($matches[0], $data[4]);

@matches = $sort->destination_word('ou');
ok($#matches, -1);

@matches = $sort->sender_match('((own_)?list)', '\s*(?:my_)?');
ok($#matches, 0);
ok($matches[0], $data[5]);
ok($sort->match_group(1), 'own_list');
ok($sort->match_group(2), 'own_');
ok(!defined $sort->match_group(3));
