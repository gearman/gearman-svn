#!/usr/bin/perl -w
use strict;

use Gearman::Worker;
use Storable qw( thaw );
use Getopt::Long qw( GetOptions );

GetOptions(
    's|servers=s', \my($servers),
);
die "usage: $0 -s <servers>" unless $servers;
my @servers = split /,/, $servers;

my $worker = Gearman::Worker->new;
$worker->job_servers(@servers);
$worker->register_function(sum => sub {
    my $sum = 0;
    $sum += $_ for @{ thaw($_[0]->arg) };
    $sum;
});
$worker->work while 1;
