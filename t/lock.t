#$Id: lock.t 2 2006-02-18 04:34:40Z itz $

use Test;

BEGIN { plan tests => 5 };

use Mail::Sort;
use POSIX qw(SIGUSR1 SIG_BLOCK SIG_UNBLOCK sigprocmask);

sub callback {
    my ($lockfile, $tries) = @_;
    if ($tries >= 2) {
        kill('USR1', getppid());
    }
}

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

$sort = new Mail::Sort(\@data, test => 1, logfile => '/dev/null', loglevel => 4); 
# first try explicit lock creation
$sort->lock('test1~');
ok(-e 'test1~');
$sort->unlock('test1~');
ok(! -e 'test1~');

#test interlocking
$pid = open PIPE, "|-"; # talking to myself!
if ($pid) {
    #parent
    my $pipe = new FileHandle;
    $pipe->fdopen(\*PIPE, "a") or die "died :( $!";

    $sort = new Mail::Sort(\@data, test => 1, logfile => $pipe,
                           loglevel => 4, callback => \&callback); 
    $sort->lock('test2~');

    eval {
        my $sigusr1 = new POSIX::SigSet(POSIX::SIGUSR1);
        POSIX::sigprocmask(POSIX::SIG_BLOCK, $sigusr1);
        local $SIG{USR1} = sub { die "wake up -- USR1!"; };

        my $bastard = fork();
        if (!defined $bastard) {
            die "fork(): $!\n";
        }
        POSIX::sigprocmask(POSIX::SIG_UNBLOCK, $sigusr1);
        if ($bastard != 0) {
            #parent code
            pause();
        } else {
            #child code
            $sort->lock('test2~');
            $sort->log(4, 'after child lock');
            $sort->unlock('test2~');
            exit(0);
        }
    };

    #parent code after being signalled
    $sort->log(4, 'before parent unlock');
    $pipe->flush();
    $sort->unlock('test2~');

} else {
    #child
    my @logs = <STDIN>;
    ok($#logs, 1);
    ok($logs[0] =~ /parent unlock/);
    ok($logs[1] =~ /child lock/);
}
