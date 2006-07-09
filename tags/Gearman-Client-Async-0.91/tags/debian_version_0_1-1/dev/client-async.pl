#!/usr/bin/perl

use strict;
use lib "$ENV{HOME}/cvs/wcmtools/gearman/lib";
use Gearman::Client::Danga;
my $client = Gearman::Client::Danga->new;
$client->job_servers('127.0.0.1');

my $counter = 0;

$client->add_task( Gearman::Task->new( "sleep_for" => \"5", {
    on_complete => sub {
        my $res = shift;
        print "GOT: $$res\n";
	$counter++;
    },
    on_status => sub {
	print "STATUS: [@_]\n";
    },
    on_retry => sub {
	print "RETRY: [@_]\n";
    },
    on_fail => sub {
	print "FAIL: [@_]\n";
    },
    retry_count => 5,
} ) );

$client->add_task( Gearman::Task->new( "sleep_for" => \"3", {
    on_complete => sub {
        my $res = shift;
        print "GOT: $$res\n";
	$counter++;
    },
    on_status => sub {
	print "STATUS: [@_]\n";
    },
    on_retry => sub {
	print "RETRY: [@_]\n";
    },
    on_fail => sub {
	print "FAIL: [@_]\n";
    },
    retry_count => 5,
} ) );

use Data::Dumper;

sub add_timer {
	Danga::Socket->AddTimer( .4, sub {
		print "Danga::Socket timer fired: $counter\n";
		if ($counter >= 2) {
			$client->shutdown();
			Danga::Socket->AddTimer( 1, sub { print "GAH!\n"; } );
		}
		else {
			add_timer();
		}
#		print "WatchedSockets: " . Dumper(Danga::Socket->DescriptorMap()) . "\n";
	} );
}

add_timer();

Danga::Socket->EventLoop();

print "done.\n";



__END__
# running a single task
my $result_ref = $client->do_task("sleep_for", "3");
print "got = $$result_ref\n";
