use strict;
our $Bin;
use FindBin qw( $Bin );
use File::Spec;
use Gearman::Client;
use Storable qw( freeze );
use Test::More tests => 1;

use constant PORT => 9000;
our @Children;

END { kill_children() }

start_server(PORT);
start_server(PORT + 1);

## Sleep, wait for servers to start up before connecting workers.
sleep 2;

start_worker(PORT);
start_worker(PORT + 1);

my $client = Gearman::Client->new;
$client->job_servers('127.0.0.1:' . PORT);
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
    my($port) = @_;
    my $worker = File::Spec->catfile($Bin, 'worker.pl');
    start_child([ $worker, '-p', $port ]);
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
