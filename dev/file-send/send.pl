#!/usr/bin/perl

use strict;
use FileSend;
use Gearman::Client;
use Storable;
use Getopt::Long;

# ./send.pl --transport=scp --dest=

my %opts = ();
GetOptions (\%opts, 
            "transport|t=s",
            "dest|d=s");

my @files = @ARGV;

my $backend = FileSend->backend_of_transport($opts{transport})
    or die "Unknown transport: $opts{transport}\n";

my $client = FileSend->gearman_client;

# waiting on a set of tasks in parallel
my $taskset = $client->new_task_set;

foreach my $file (@files) {

    my $args = Storable::nfreeze
        ({
            backend => $backend,
            source  => $file,
            dest    => $opts{dest},
        });

    $taskset->add_task( "send_file" => \$args, {
        # FIXME: status
        #on_status   => sub { print join(" / ", @_) . "\n" },
        on_complete => sub { print "$file\n" },
    });
}

$taskset->wait;

