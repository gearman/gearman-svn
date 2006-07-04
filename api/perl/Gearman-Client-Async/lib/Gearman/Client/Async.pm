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
    $client->job_servers( '10.0.0.1' );

    # Read list of job servers out of the client.
    $arrayref = $client->job_servers;
    @array = $client->job_servers;

    # Start a task
    $task = Gearman::Task->new(...); # with callbacks, etc
    $client->add_task( $task );

    # Shutdown all job server connections, so we can destruct.
    $client->shutdown;

    # Better examples forthcoming, see tests or something.

=cut

use strict;
use warnings;

use IO::Handle;
use Socket qw(IPPROTO_TCP TCP_NODELAY SOL_SOCKET);

use fields qw(job_servers);

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

    $self->job_servers(@{ $opts{job_servers} })
        if $opts{job_servers};

    return $self;
}

# getter/setter
sub job_servers {
    my Gearman::Client::Async $self = shift;

    my $job_servers = $self->{job_servers};

    if (@_) {
        # Maybe we shouldn't do this, then existing tasks can finish and the connection will close on its own?
        $self->shutdown;

        @$job_servers = ();

        foreach (@_) {
            my $server = Gearman::Client::Async::Connection->new( hostspec => $_ );
            if ($server) {
                push @$job_servers, $server;
            }
            else {
                warn "Job Server '$_' failed to initialize, bad hostspec?\n";
            }
        }
    }

    my @list = map {$_->hostspec} @$job_servers unless @_;

    return @list if wantarray;
    return [@list];
}

sub shutdown {
    my Gearman::Client::Async $self = shift;

    foreach (@{$self->{job_servers}}) {
        $_->close( "Shutdown" );
    }
}

sub add_task {
    my Gearman::Client::Async $self = shift;
    my Gearman::Task $task = shift;

    my @job_servers = grep { $_->alive } @{$self->{job_servers}};

    warn "Alive servers: " . @job_servers . " out of " . @{$self->{job_servers}} . "\n" if DEBUGGING;

    if (@job_servers) {
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
    else {
        $task->fail;
    }
}

1;
__END__
