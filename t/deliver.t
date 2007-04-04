#$Id: deliver.t 36 2007-04-04 02:45:22Z itz $

use Test;

BEGIN { plan tests => 20 };

use Mail::Sort;
use File::Path;

@data=(
       "From someone\@somewhere Thu Oct 25 16:23:40 2001\n",
       "From: me_myself_I\@localhost\n",
       "X-Strange: one two-three four_five six.seven\@eight\n",
       "X-Multiline: line one\n",
       " line two\n",
       "To: you_vous_Vy\@nowhere.one.org\n",
       "Subject: deliver test\n",
       "Sender: my_own_list\@nowhere.two.org\n",
       "Date: Sun, 01 Apr 2007 20:38:01 -0400\n",
       "Message-ID: <akaeghoe6Uvu.mail-sort\@unicorn.ahiker.homeip.net>\n",
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
ok(join('',@lines[1..10]), join('',@data[0..9]));
ok($lines[11], '>' . $data[10]);
ok(join('',@lines[12..$#data+1]), join('',@data[11..$#data]));

#test deduping
$dedupe_dir = "test.d." . `date +%Y%m%d%H%M%S`;
chomp $dedupe_dir;
$sort = new Mail::Sort(\@data, logfile => '/dev/null', loglevel => 4, auto_dedupe => $dedupe_dir);
$sort->deliver(">test6~", keep => 1);
$sort->deliver(">test7~", keep => 1);
$sort = new Mail::Sort(\@data, logfile => '/dev/null', loglevel => 4, auto_dedupe => $dedupe_dir);
$sort->deliver(">test8~", keep => 1);

ok(-f 'test6~');
ok(-f 'test7~');
ok(not -f 'test8~');

unlink('test6~');
unlink('test7~');
unlink('test8~');

rmtree ($dedupe_dir) if -d $dedupe_dir;
