#!/usr/bin/perl

use strict;
our $Bin;
use FindBin qw( $Bin );
use lib "$Bin/../../Gearman/lib";
$ENV{PERL5LIB} .= ":$Bin/../../Gearman/lib";

use Gearman::Client::Async;

use Test::More;
use IO::Socket::INET;
use POSIX qw( :sys_wait_h );
use List::Util qw(first);;

use constant PORT => 9000;
our %Children;

END { kill_children() }

if (start_server(PORT)) {
    plan tests => 10;
} else {
    plan skip_all => "Can't find server to test with";
    exit 0;
}

start_server(PORT + 1);

## Sleep, wait for servers to start up before connecting workers.
wait_for_port(PORT);
wait_for_port(PORT + 1);

## Look for 2 job servers, starting at port number PORT.
start_worker(PORT, 2);
start_worker(PORT, 2);

my $client = Gearman::Client::Async->new;
$client->job_servers('127.0.0.1:' . (PORT + 1), '127.0.0.1:' . PORT);


diag( "Job Servers: ", $client->job_servers, "\n" );

my $counter = 0;

$client->add_task( Gearman::Task->new( "sleep_for" => \ "5", {
    on_complete => sub {
        my $res = shift;
        $counter++;
    },
    on_status => sub {
        pass(join "/", @_);
        diag "STATUS: [@_]\n";
    },
    on_retry => sub {
        print "RETRY: [@_]\n";
    },
    on_fail => sub {
        print "FAIL: [@_]\n";
    },
    retry_count => 5,
} ) );

$client->add_task( Gearman::Task->new( "sleep_for" => \ "3", {
    on_complete => sub {
        my $res = shift;
        $counter++;
    },
    on_status => sub {
        pass(join "/", @_);
        diag "STATUS: [@_]\n";
    },
    on_retry => sub {
        print "RETRY: [@_]\n";
    },
    on_fail => sub {
        fail(join "/", @_);
        print "FAIL: [@_]\n";
    },
    retry_count => 5,
} ) );

use Data::Dumper;

sub add_timer {
    Danga::Socket->AddTimer( .4, sub {

        if ($counter >= 2) {
            $client->shutdown();
            Danga::Socket->AddTimer( 1, sub {  exit;  } );
        }
        else {
            add_timer();
        }
#            print "WatchedSockets: " . Dumper(Danga::Socket->DescriptorMap()) . "\n";
    } );
  }


add_timer();

Danga::Socket->EventLoop();

print "done.\n";

sub start_server {
    my($port) = @_;
    my @loc = ("$Bin/../../../../server/gearmand",  # using svn
               '/usr/bin/gearmand',            # where some distros might put it
               '/usr/sbin/gearmand',           # where other distros might put it
               );
    my $server = first { -e $_ } @loc
        or return 0;

    my $pid = start_child([ $server, '-p', $port ]);
    $Children{$pid} = 'S';
    return 1;
}

sub start_worker {
    my($port, $num) = @_;
    my $worker = "$Bin/worker.pl";
    my $servers = join ',',
                  map '127.0.0.1:' . (PORT + $_),
                  0..$num-1;
    my $pid = start_child([ $worker, '-s', $servers ]);
    diag "Started worker on $pid";
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

__END__
# running a single task
my $result_ref = $client->do_task("sleep_for", "3");
print "got = $$result_ref\n";

