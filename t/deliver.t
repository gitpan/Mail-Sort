#$Id: deliver.t 22 2006-04-21 05:21:00Z itz $

use Test;

BEGIN { plan tests => 17 };

use Mail::Sort;

@data=(
       "From someone\@somewhere Thu Oct 25 16:23:40 2001\n",
       "From: me_myself_I\@localhost\n",
       "X-Strange: one two-three four_five six.seven\@eight\n",
       "X-Multiline: line one\n",
       " line two\n",
       "To: you_vous_Vy\@nowhere.one.org\n",
       "Subject: deliver test\n",
       "Sender: my_own_list\@nowhere.two.org\n",
       "\n",
       ">From Myself, blah blah blah, this is a really stupid test message.\n",
       "Another line,\n",
       "\n",
       "and an empty one for fun.\n",
       "\n"
       );

#normal delivery
$sort = new Mail::Sort(\@data, logfile => '/dev/null', loglevel => 4); 
ok($sort->{envelope_from}, 'someone@somewhere');
$sort->deliver('>test1~', keep => 1);
$fh = new FileHandle('test1~', '<');
die "$!" unless (defined $fh);
@lines = $fh->getlines();
$fh->close();
unlink 'test1~';

unshift @lines, $data[0];
ok($#lines, $#data);
ok(join('',@lines), join('',@data));

#delivery in mbox format
$sort->deliver('>test2~', keep => 1, mbox => 1);
$fh = new FileHandle('test2~', '<');
die "$!" unless (defined $fh);
@lines = $fh->getlines();
$fh->close();
unlink 'test2~';

ok($lines[$#lines], "\n");
ok($#lines, $#data);
ok(join('',@lines[1..$#lines]), join('',@data[1..$#data]));
ok($lines[0] =~ /^From someone\@somewhere [A-Z][a-z]+ [A-Z][a-z]+ [0-9]?[0-9] [0-9][0-9]:[0-9][0-9]:[0-9][0-9] [0-9]+$/);

#test delivery to a pipe
$sort->deliver("| cat >test3~", keep => 1);
$fh = new FileHandle('test3~', '<');
die "$!" unless (defined $fh);
@lines = $fh->getlines();
$fh->close();
unlink 'test3~';

unshift @lines, $data[0];
ok($#lines, $#data);
ok(join('',@lines), join('',@data));

#test normal constructor
$sort->deliver(">test4~", keep => 1);
$fh = new FileHandle('test4~', '<');
$clone = new Mail::Sort($fh, logfile => '/dev/null', loglevel => 4);
$fh->close();
unlink 'test4~';
ok(join('',@{$sort->{head}}), join('',@{$clone->{head}}));
ok(join('',@{$sort->{body}}), join('',@{$clone->{body}}));

#test From escaping
shift @data;
$sort = new Mail::Sort(\@data, logfile => '/dev/null', loglevel => 4); 
$sort->deliver(">test5~", keep => 1, mbox => 1);
$fh = new FileHandle('test5~', '<');
die "$!" unless (defined $fh);
@lines = $fh->getlines();
$fh->close();
unlink 'test5~';

ok($#lines, $#data + 2);
ok($lines[0] =~ /^From /);
ok($lines[$#lines], "\n");
ok(join('',@lines[1..8]), join('',@data[0..7]));
ok($lines[9], '>' . $data[8]);
ok(join('',@lines[10..$#data+1]), join('',@data[9..$#data]));
