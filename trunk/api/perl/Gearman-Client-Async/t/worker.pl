#!/usr/bin/perl

use strict;
use lib "$ENV{HOME}/cvs/wcmtools/gearman/lib";
use Gearman::Worker;
my $worker = Gearman::Worker->new;
$worker->job_servers('127.0.0.1:9000', '127.0.0.1:9001');

$worker->register_function("sleep_for" => sub {
    my $job = shift;
    my $arg = $job->arg;

    my $res = rand();
    $job->set_status(0, $arg);
    for my $i (1..$arg) {
        select(undef,undef,undef,0.25);
        $job->set_status($i, $arg);
    }
    return $res;
});

$worker->work while 1;

