#!/usr/bin/perl -w
use strict;

use Gearman::Worker;
use Storable qw( thaw );
use Getopt::Long qw( GetOptions );

GetOptions(
    'p|port=i' => \my($port),
);
die "usage: $0 <port>" unless $port;

my $worker = Gearman::Worker->new;
$worker->job_servers('127.0.0.1:' . $port);
$worker->register_function(sum => sub {
    my $sum = 0;
    $sum += $_ for @{ thaw($_[0]->arg) };
    $sum;
});
$worker->work while 1;
