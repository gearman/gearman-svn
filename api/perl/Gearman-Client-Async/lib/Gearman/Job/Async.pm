#!/usr/bin/perl

package Gearman::Job::Async;

use strict;
use warnings;
use Gearman::Worker; # to get Gearman::Job loaded
use base qw(Gearman::Job);
use fields qw();

sub set_status {
    my Gearman::Job::Async $self = shift;
    my ($nu, $de) = @_;

    $self->{jss}->announce_job_status($self->{handle}, $nu, $de);
    return 1;
}

sub complete {
    my Gearman::Job::Async $self = shift;
    my $ret_ref = shift;

    $self->{jss}->announce_job_complete($self->{handle}, $ret_ref);
}

sub fail {
    my Gearman::Job::Async $self = shift;

    $self->{jss}->announce_job_fail($self->{handle});
}

1;
