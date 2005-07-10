use strict;
our $Bin;
use FindBin qw( $Bin );
use File::Spec;
use Gearman::Client;
use Storable qw( freeze );
use Test::More tests => 11;
use IO::Socket::INET;
use POSIX qw( :sys_wait_h );

use constant PORT => 9000;
our %Children;

END { kill_children() }

start_server(PORT);
start_server(PORT + 1);

## Sleep, wait for servers to start up before connecting workers.
wait_for_port(PORT);
wait_for_port(PORT + 1);

## Look for 2 job servers, starting at port number PORT.
start_worker(PORT, 2);
start_worker(PORT, 2);

my $client = Gearman::Client->new;
isa_ok($client, 'Gearman::Client');
$client->job_servers('127.0.0.1:' . PORT, '127.0.0.1:' . (PORT + 1));

eval { $client->do_task(sum => []) };
like($@, qr/scalar or scalarref/, 'do_task does not accept arrayref argument');

my $out = $client->do_task(sum => freeze([ 3, 5 ]));
is($$out, 8, 'do_task returned 8 for sum');

my $tasks = $client->new_task_set;
isa_ok($tasks, 'Gearman::Taskset');
my $sum;
my $failed = 0;
my $completed = 0;
my $handle = $tasks->add_task(sum => freeze([ 3, 5 ]), {
    on_complete => sub { $sum = ${ $_[0] } },
    on_fail => sub { $failed = 1 }
});
$tasks->wait;
is($sum, 8, 'add_task/wait returned 8 for sum');
is($failed, 0, 'on_fail not called on a successful result');

## Test some failure conditions:
## Normal failure (worker returns undef or dies within eval).
is($client->do_task('fail'), undef, 'Job that failed naturally returned undef');
## Worker process exits.
is($client->do_task('fail_exit'), undef,
    'Job that failed via exit returned undef');

## The fail_exit just killed off a worker--make sure it gets respawned.
respawn_children();

## Worker process times out (takes longer than fail_after_idle seconds).
TODO: {
    todo_skip 'fail_after_idle is not yet implemented', 1;
    is($client->do_task('sleep', 5, { fail_after_idle => 3 }), undef,
        'Job that timed out after 3 seconds returns failure (fail_after_idle)');
}

my $tasks = $client->new_task_set;
$completed = 0;
$failed = 0;
my $handle = $tasks->add_task(fail => '', {
    on_complete => sub { $completed = 1 },
    on_fail => sub { $failed = 1 },
});
$tasks->wait;
is($completed, 0, 'on_complete not called on failed result');
is($failed, 1, 'on_fail called on failed result');

sub respawn_children {
    for my $pid (keys %Children) {
        if (waitpid $pid, WNOHANG) {
            if ($Children{$pid} eq 'W') {
                ## Right now we can only restart workers.
                start_worker(PORT, 2);
            }
        }
    }
}

sub start_server {
    my($port) = @_;
    my $server = File::Spec->catfile($Bin, '..', 'server', 'gearmand');
    my $pid = start_child([ $server, '-p', $port ]);
    $Children{$pid} = 'S';
}

sub start_worker {
    my($port, $num) = @_;
    my $worker = File::Spec->catfile($Bin, 'worker.pl');
    my $servers = join ',',
                  map '127.0.0.1:' . (PORT + $_),
                  0..$num-1;
    my $pid = start_child([ $worker, '-s', $servers ]);
    $Children{$pid} = 'W';
}

sub start_child {
    my($cmd) = @_;
    my $pid = fork();
    die $! unless defined $pid;
    unless ($pid) {
        exec 'perl', '-Iblib/lib', '-Ilib', @$cmd or die $!;
    }
    $pid;
}

sub kill_children {
    kill INT => keys %Children;
}

sub wait_for_port {
    my($port) = @_;
    my $start = time;
    while (1) {
	my $sock = IO::Socket::INET->new(PeerAddr => "127.0.0.1:$port");
	return 1 if $sock;
	select undef, undef, undef, 0.25;
	die "Timeout waiting for port $port to startup" if time > $start + 5;
    }
}
