#!/usr/bin/perl

use strict;
use FindBin qw($Bin);
use Test::More;

$ENV{PERL5LIB} .= ":$Bin/../../Gearman/lib";
use lib "$Bin/../../Gearman/lib";
use lib "$Bin/../../../../server/lib";

use Gearman::Server;
use Gearman::Client::Async;

my $server = Gearman::Server->new();
$server->start_worker('t/worker.pl');

my $client = Gearman::Client::Async->new(job_servers => [ $server ], exceptions => 1);

my $good = 0;
my $status;

plan tests => 1;

Danga::Socket->AddTimer(0, sub {
    $client->add_task( Gearman::Task->new( "throw_exception" => \ "bother", {
        on_complete => sub {
            diag "COMPLETE: [@_]\n";
        },
        on_retry => sub {
            diag "RETRY: [@_]\n";
        },
        on_fail => sub {
            $good++;
            $client->add_task(Gearman::Task->new("shutdown"));
            diag "FAIL: [@_]\n";
        },
        on_exception => sub {
            $good++;
            diag "EXCEPTION: [@_]\n";
        },
    } ) );
});

Danga::Socket->AddTimer(4.0, sub {
     die "Timeout, test fails";
});

Danga::Socket->SetPostLoopCallback(sub {
    if ($good >= 2) {
        pass("Got both responses");
        return 0;
    }
    return 1;
});

Danga::Socket->EventLoop();

# vim: filetype=perl
