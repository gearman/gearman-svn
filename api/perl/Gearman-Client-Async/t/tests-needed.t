#!/usr/bin/perl

use strict;
use Test::More 'no_plan';

ok('err1.t', "connect to one js, it's down immediately, no other options, fail");
ok('', "connect to one js, it's down immediately, try another, no retry count");
ok('', "connect to one js, it times out, try another");
ok('', "connect to one js, it times out, no others, fail");
ok('', "connect to one js, submit job, no reply in 'fail_after' seconds, fail, job then succeeds right after, ignore it");
ok('', "submit a bunch of jobs to one js, they sleep, kill it, get errors, resubmit all to other");


