#$Id: headers.t 24 2006-10-19 04:49:31Z itz $

use Test;

BEGIN { plan tests => 70 };

use Mail::Sort;

@data=(
       "From: me_myself_I\@localhost\n",
       "X-Strange: one two-three four_five six.seven\@eight\n",
       "X-Multiline: line one\n",
       " line two\n",
       "To: you_vous_Vy\@nowhere.one.org\n",
       "Sender: my_own_list\@nowhere.two.org\n",
       "X-Strange: and a second incarnation\n",
       "\n",
       "From Myself, blah blah blah, this is a really stupid test message.\n",
       "Another line,\n",
       "\n",
       "and an empty one for fun.\n",
       );

$sort = new Mail::Sort(\@data, test => 1, logfile => '/dev/null');

@matches = $sort->header_match('from', 'myself');
ok($#matches, 0);
ok($matches[0], 0);

@matches = $sort->header_match('From', 'Myself');
ok($#matches, -1);

@matches = $sort->header_match('from', 'm._(m.)');
ok($#matches, 0);
ok($matches[0], 0);
ok($sort->match_group(1), 'my');

@matches = $sort->header_start('to', 'you');
ok($#matches, 0);
ok($matches[0], 3);

@matches = $sort->header_start('to', 'vous');
ok($#matches, -1);

@matches = $sort->header_start('x-multiline', 'line one');
ok($#matches, 0);
ok($matches[0], 2);

@matches = $sort->header_start('x-multiline', 'line two');
ok($#matches, -1);

@matches = $sort->header_match('x-multiline', 'one\n line');
ok($#matches, 0);
ok($matches[0], 2);

@matches = $sort->destination_match('(one)');
ok($#matches, 0);
ok($matches[0], 3);
ok($sort->match_group(1), 'one');

@matches = $sort->destination_match('two');
ok($#matches, -1);

@matches = $sort->destination_address('nowhere');
ok($#matches, 0);
ok($matches[0], 3);

@matches = $sort->destination_address('vous_vy');
ok($#matches, -1);

@matches = $sort->destination_word('vous');
ok($#matches, 0);
ok($matches[0], 3);

@matches = $sort->destination_word('ou');
ok($#matches, -1);

@matches = $sort->sender_match('((own_)?list)', '\s*(?:my_)?');
ok($#matches, 0);
ok($matches[0], 4);
ok($sort->match_group(1), 'own_list');
ok($sort->match_group(2), 'own_');
ok(!defined $sort->match_group(3));

@matches = $sort->header_match('x-strange');
ok($#matches, 1);
ok($matches[0], 1);
ok($matches[1], 5);
@headers = $sort->get_header(@matches);
ok($#headers, 1);
ok($headers[0], $data[1]);
ok($headers[1], $data[6]);

$imposing = "X-Strange: an imposing line\n";
$sort->add_header_at ($imposing, 1);
@matches = $sort->header_match('x-strange');
ok($#matches, 2);
ok($matches[0], 1);
ok($matches[1], 2);
ok($matches[2], 6);
@headers = $sort->get_header(@matches);
ok($#headers, 2);
ok($headers[0], $imposing);
ok($headers[1], $data[1]);
ok($headers[2], $data[6]);

$incubus = "X-Incubus: an injected line\n";
$sort->add_header_before ($incubus, 'x-strange', 1);
@matches = $sort->header_match ('x-incubus');
ok($#matches, 0);
ok($matches[0], 2);
@headers = $sort->get_header(@matches);
ok($#headers, 0);
ok($headers[0], $incubus);

$sort->delete_header_tag ('x-strange', 1);
@matches = $sort->header_match ('x-strange');
ok($#matches, 1);
ok($matches[0], 1);
ok($matches[1], 6);
 
$sort->replace_header_tag ("X-Incubus: an injected life\n", 'x-incubus', 0);
@matches = $sort->header_match ('x-incubus');
ok($#matches, 0);
ok($matches[0], 2);
@headers = $sort->get_header(@matches);
ok($#headers, 0);
ok($headers[0] =~ /injected life/);

sub xform {
    ${$_[0]} =~ s/injected life/injected line/g;
}

$sort->transform_header_tag(\&xform, 'x-incubus', 0);
@matches = $sort->header_match ('x-incubus');
ok($#matches, 0);
ok($matches[0], 2);
@headers = $sort->get_header(@matches);
ok($#headers, 0);
ok($headers[0] =~ /injected line/);

$sort->append_header ($incubus);
@deleted = $sort->delete_header_tag_all ('x-incubus');
ok($#deleted, 1);
ok($deleted[0], $incubus);
ok($deleted[1], $incubus);

@matches = $sort->header_match ('sender');
ok($#matches, 0);
$sender_idx = $matches[0];

$sender = "Sender: woo\@hoo\n";
$sort->append_header_and_rename ($sender);
@matches = $sort->header_match ('sender');
ok($#matches, 0);
ok($matches[0], $#{$sort->{head}});
@headers = $sort->get_header (@matches);
ok($#headers, 0);
ok($headers[0], $sender);
@matches = $sort->header_match ('x-original-sender');
ok($#matches, 0);
ok($matches[0], $sender_idx);
@headers = $sort->get_header (@matches);
ok($#headers, 0);
ok($headers[0], "X-Original-Sender: my_own_list\@nowhere.two.org\n");
