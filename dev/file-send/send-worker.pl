#!/usr/bin/perl

package FileSend;

use strict;
use Gearman::Worker;
use FileSend;
use Storable;

my $worker = FileSend->gearman_worker(\&send_file);

sub send_file {
    my $job = shift;

    my $args = Storable::thaw(${$job->argref});

    use Data::Dumper;
    print Dumper($args);

    $job->set_status(0, 1);

    my $backend = $args->{backend};
    my $source  = $args->{source};
    my $dest    = $args->{dest};
    
    warn "source: $source, dest: $dest\n";
    "FileSend::$backend"->send_file($source, $dest);
    sleep 1;

    $job->set_status(1, 1);
}
