#$Id: deliver.t,v 1.3 2001/10/25 23:42:25 itz Exp $

use Test;

BEGIN { plan tests => 9 };

use Mail::Sort;
use Config;

@data=(
       "From someone\@somewhere Thu Oct 25 16:23:40 2001\n",
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

#normal delivery
$sort = new Mail::Sort(\@data, logfile => '/dev/null', loglevel => 4); 
ok($sort->{envelope_from} eq 'someone@somewhere');
$status = $sort->deliver('>test1~', keep => 1);
$fh = new FileHandle('test1~', '<');
die "$!" unless (defined $fh);
@lines = $fh->getlines();
$fh->close();
unlink 'test1~';

ok($status);
unshift @lines, $data[0];
ok($#lines == $#data);
ok(join('',@lines) eq join('',@data));

#test delivery to a pipe
$status = $sort->deliver("| $Config{cat} >test3~", keep => 1);
$fh = new FileHandle('test3~', '<');
die "$!" unless (defined $fh);
@lines = $fh->getlines();
$fh->close();
unlink 'test3~';

ok($status);
unshift @lines, $data[0];
ok($#lines == $#data);
ok(join('',@lines) eq join('',@data));

#something that should fail
$status = $sort->deliver("| $Config{sh} -c 'exit 1'", keep => 1);
ok(!$status);

#test forwarding
$status = $sort->forward("$ENV{LOGNAME}\@localhost", keep => 1);
ok($status);


