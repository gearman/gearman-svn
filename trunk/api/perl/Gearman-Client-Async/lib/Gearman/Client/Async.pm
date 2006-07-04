#TODO: fail_after_idle
#TODO: find out what fail_after_idle means in this context

package Gearman::Client::Async;

=head1 NAME

Gearman::Client::Async - Asynchronous client module for Gearman for Danga::Socket servers

=head1 SYNOPSIS

    use Gearman::Client::Async;

    # Instantiate a new Gearman::Client::Async object.
    $client = Gearman::Client::Async->new(
        job_servers => [ '127.0.0.1', '192.168.0.1:123' ],
    );

    # Overwrite job server list with a new one.
    $client->set_job_servers( '10.0.0.1' );

    # Read list of job servers out of the client.
    $arrayref = $client->job_servers;
    @array = $client->job_servers;

    # Start a task
    $task = Gearman::Task->new(...); # with callbacks, etc
    $client->add_task( $task );

=cut

use strict;
use warnings;
use Carp qw(croak);

use fields (
            'job_servers',   # arrayref of Gearman::Client::Async::Connection objects
            );

use Gearman::Objects;
use Gearman::Task;
use Gearman::JobStatus;
use Gearman::Client::Async::Connection;

use vars qw($VERSION);

$VERSION = "0.00_01";

sub DEBUGGING () { 0 }

sub new {
    my ($class, %opts) = @_;
    my $self = $class;
    $self = fields::new($class) unless ref $self;

    $self->{job_servers} = [];

    my $js = delete $opts{job_servers};
    $self->set_job_servers(@$js) if $js;

    croak "Unknown parameters: " . join(", ", keys %opts) if %opts;
    return $self;
}

# set job servers, without shutting down dups, and shutting down old ones gracefully
sub set_job_servers {
    my Gearman::Client::Async $self = shift;

    my %being_set; # hostspec -> 1
    %being_set = map { $_, 1 } @_;

    my %exist;   # hostspec -> existing conn
    foreach my $econn (@{ $self->{job_servers} }) {
        my $spec = $econn->hostspec;
        if ($being_set{$spec}) {
            $exist{$spec} = $econn;
        } else {
            $econn->close_when_finished;
        }
    }

    my @newlist;
    foreach (@_) {
        push @newlist, $exist{$_} || Gearman::Client::Async::Connection->new( hostspec => $_ );
    }
    $self->{job_servers} = \@newlist;
}

# getter
sub job_servers {
    my Gearman::Client::Async $self = shift;
    croak "Not a setter" if @_;
    my @list = map { $_->hostspec } @{ $self->{job_servers} };
    return wantarray ? @list : \@list;
}

sub add_task {
    my Gearman::Client::Async $self = shift;
    my Gearman::Task $task = shift;

    my @job_servers = grep { $_->alive } @{$self->{job_servers}};

    warn "Alive servers: " . @job_servers . " out of " . @{$self->{job_servers}} . "\n" if DEBUGGING;
    unless (@job_servers) {
        $task->fail;
        return;
    }

    my $js;
    if (defined( my $hash = $task->hash )) {
        # Task is hashed, use key to fetch job server
        $js = @job_servers[$hash % @job_servers];
    }
    else {
        # Task is not hashed, random job server
        $js = @job_servers[int( rand( @job_servers ))];
    }

    # TODO Fix this violation of object privacy.
    $task->{taskset} = $self;

    $js->add_task( $task );
}

1;
__END__
