#$Id: log.t,v 1.3 2002/03/29 07:23:52 itz Exp $

use Test;

BEGIN { plan tests => 7 };

use Mail::Sort;
use FileHandle 2.00;

@data=(
       "From: me_myself_I\@localhost\n",
       "X-Strange: one two-three four_five six.seven\@eight\n",
       "X-Multiline: line one\n",
       " line two\n",
       "To: you_vous_Vy\@nowhere.one.org\n",
       "Subject: logging test\n",
       "Sender: my_own_list\@nowhere.two.org\n",
       "\n",
       "From Myself, blah blah blah, this is a really stupid test message.\n",
       "Another line,\n",
       "\n",
       "and an empty one for fun.\n",
       );

$pid = open PIPE, "|-"; # talking to myself!
if ($pid) {
    #parent
    my $pipe = new FileHandle;
    $pipe->fdopen(\*PIPE, "a") or die "died :( $!";

    $sort = new Mail::Sort(\@data, test => 1, logfile => $pipe, loglevel => 4); 
    $sort->log(4, 'blah');
    $sort->log(4, 'eeek', 'argh');

    $pipe->flush();

    $sort = new Mail::Sort(\@data, logfile => $pipe, loglevel => 3);
    $sort->log(4, 'ouch');

    #some real logs now

    $sort->header_match('from', 'myself');
    $sort->deliver("| cat >/dev/null", label => 'hmph', keep => 1);
    $sort->forward("$ENV{LOGNAME}\@localhost", label => 'heck', keep => 1);
    $sort->ignore('barf');
} else {
    #child
    my @logs = <STDIN>;
    my $pid = getppid();
    my $log_regexp = "^[A-Z][a-z][a-z]\\s+[0-9][0-9]\\s+[0-9][0-9]:[0-9][0-9]:[0-9][0-9]\\s+\\[$pid\\]\\s+";
    ok($#logs, 5);
    ok($logs[0] =~ /${log_regexp}blah$/);
    ok($logs[1] =~ /${log_regexp}\(argh\)\s+eeek$/);
    ok($logs[2] =~ /${log_regexp}\(header match\)\s+$data[0]/);
    ok($logs[3] =~ /${log_regexp}\(hmph\)\s+delivering\s+to\s+|\s+cat\s+>\/dev\/null$/);
    ok($logs[4] =~ /${log_regexp}\(heck\)\s+(delivering|smtp forwarding)/);
    ok($logs[5] =~ /${log_regexp}\(barf\)\s+delivering/);
}
