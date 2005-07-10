use strict;
our $Bin;
use FindBin qw( $Bin );
use File::Spec;
use Gearman::Client;
use Storable qw( freeze );
use Test::More tests => 1;
use IO::Socket::INET;

use constant PORT => 9000;
our @Children;

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
$client->job_servers('127.0.0.1:' . PORT, '127.0.0.1:' . (PORT + 1));
my $tasks = $client->new_task_set;
my $sum;
my $handle = $tasks->add_task(sum => freeze([ 3, 5 ]), {
    on_complete => sub { $sum = ${ $_[0] } }
});
$tasks->wait;
is($sum, 8, 'Sum is 8');

sub start_server {
    my($port) = @_;
    my $server = File::Spec->catfile($Bin, '..', 'server', 'gearmand');
    start_child([ $server, '-p', $port ]);
}

sub start_worker {
    my($port, $num) = @_;
    my $worker = File::Spec->catfile($Bin, 'worker.pl');
    my $servers = join ',',
                  map '127.0.0.1:' . (PORT + $_),
                  0..$num-1;
    start_child([ $worker, '-s', $servers ]);
}

sub start_child {
    my($cmd) = @_;
    my $pid = fork();
    die $! unless defined $pid;
    unless ($pid) {
        exec 'perl', '-Iblib/lib', '-Ilib', @$cmd or die $!;
    }
    push @Children, $pid;
}

sub kill_children {
    kill INT => @Children;
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
