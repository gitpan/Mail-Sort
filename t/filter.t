#$Id: headers.t 15 2006-04-06 05:52:40Z itz $

use Test;

BEGIN { plan tests => 6 };

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
       ">From Myself, blah blah blah, this is a really stupid test message.\n",
       "Another line,\n",
       "\n",
       "and an empty one for fun.\n",
       "\n"
       );

$sort = new Mail::Sort(\@data, test => 1, logfile => '/dev/null');

$sort->filter (['tail', '+5']);
ok(scalar @{$sort->{head}}, 3);
ok(scalar @{$sort->{body}}, 5);

@matches = $sort->header_match('x-strange');
ok($#matches, 0);
ok($matches[0], 2);
@headers = $sort->get_header(@matches);
ok($#headers, 0);
ok($headers[0], $data[6]);
