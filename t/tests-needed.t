#!/usr/bin/perl

use strict;
use Test::More 'no_plan';

ok('err1.t', "connect to one js, it's down immediately, no other options, fail");
ok('err2.t', "connect to one js, submit job, no reply in 'timeout' seconds, fail, job then succeeds right after, ignore it");
ok('err3.t', "connect to one js, it's down immediately, try another, no retry count, it succeeds");
ok('err4.t', "connect to one js, it times out connecting, try another, it succeeds");

ok('', "submit a bunch of jobs to one js, one worker, first sleeps, kill js, get errors, resubmit all to other js");
ok('', "submit a bunch of jobs to one js, one worker, first sleeps, kill worker, .... ?");




