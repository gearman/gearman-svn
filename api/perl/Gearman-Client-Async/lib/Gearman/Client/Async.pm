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

use vars qw($VERSION);

$VERSION = "0.00_01";

sub DEBUGGING () { 1 }

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

    my @job_servers = grep { $_->safe } @{$self->{job_servers}};

    warn "Safe servers: " . @job_servers . " out of " . @{$self->{job_servers}} . "\n" if DEBUGGING;

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


package Gearman::Client::Async::Connection;

use strict;
use warnings;

use Danga::Socket;
use base 'Danga::Socket';
use fields qw(state waiting need_handle parser hostspec to_send deadtime);

use Gearman::Task;
use Gearman::Util;

use Socket qw(PF_INET IPPROTO_TCP SOCK_STREAM);

sub DEBUGGING () { 1 }

sub new {
    my Gearman::Client::Async::Connection $self = shift;

    my %opts = @_;

    $self = fields::new( $self ) unless ref $self;

    $self->{hostspec} = delete( $opts{hostspec} ) or return;

    $self->{state} = 'disconnected';
    $self->{waiting} = {};
    $self->{need_handle} = [];
    $self->{to_send} = [];
    $self->{deadtime} = 0;

    return $self;
}

sub hostspec {
    my Gearman::Client::Async::Connection $self = shift;

    return $self->{hostspec};
}

sub connect {
    my Gearman::Client::Async::Connection $self = shift;

    $self->{state} = 'connecting';

    my ($host, $port) = split /:/, $self->{hostspec};
    $port ||= 7003;

    socket my $sock, PF_INET, SOCK_STREAM, IPPROTO_TCP;
    IO::Handle::blocking($sock, 0);

    unless ($sock && defined fileno($sock)) {
        warn( "Error creating socket: $!\n" );
        return undef;
    }

    $self->SUPER::new( $sock );

    connect $sock, Socket::sockaddr_in( $port, Socket::inet_aton( $host ) );

    $self->{parser} = Gearman::ResponseParser::Async->new( $self );

    $self->watch_write( 1 );
    $self->watch_read( 1 );
}

sub event_write {
    my Gearman::Client::Async::Connection $self = shift;

    if ($self->{state} eq 'connecting') {
        $self->{state} = 'ready';
    }

    my $tasks = $self->{to_send};

    if (@$tasks and $self->{state} eq 'ready') {
        my $task = shift @$tasks;
        $self->write( $task->pack_submit_packet );
        push @{$self->{need_handle}}, $task;
        return;
    }

    $self->watch_write( 0 );
}

sub event_read {
    my Gearman::Client::Async::Connection $self = shift;

    my $input = $self->read( 128 * 1024 );

    if ($input) {
        $self->{parser}->parse_data( $input );
    }
    else {
        $self->close( "EOF" );
    }
}

sub event_err {
    my Gearman::Client::Async::Connection $self = shift;

    if (DEBUGGING and $self->{state} eq 'connecting') {
        warn "Jobserver, $self->{hostspec} ($self) has failed to connect properly\n";
    }

    $self->mark_unsafe;
    $self->close( "error" );
}

sub close {
    my Gearman::Client::Async::Connection $self = shift;
    my $reason = shift;

    if ($self->{state} ne 'disconnected') {
        $self->{state} = 'disconnected';
        $self->SUPER::close( $reason );
    }

    $self->_requeue_all;
}

sub mark_unsafe {
    my Gearman::Client::Async::Connection $self = shift;

    $self->{deadtime} = time + 10;
}

sub safe {
    my Gearman::Client::Async::Connection $self = shift;

    return $self->{deadtime} <= time;
}

sub add_task {
    my Gearman::Client::Async::Connection $self = shift;
    my Gearman::Task $task = shift;

    if ($self->{state} eq 'disconnected') {
        $self->connect;
    }

    $self->watch_write( 1 );

    push @{$self->{to_send}}, $task;
}

sub _requeue_all {
    my Gearman::Client::Async::Connection $self = shift;

    my $to_send = $self->{to_send};
    my $need_handle = $self->{need_handle};
    my $waiting = $self->{waiting};

    $self->{to_send} = [];
    $self->{need_handle} = [];
    $self->{waiting} = {};

    while (@$to_send) {
        my $task = shift @$to_send;
        warn "Task $task in to_send queue during socket error, queueing for redispatch\n" if DEBUGGING;
        $task->fail;
    }

    while (@$need_handle) {
        my $task = shift @$need_handle;
        warn "Task $task in need_handle queue during socket error, queueing for redispatch\n" if DEBUGGING;
        $task->fail;
    }

    while (my ($shandle, $task) = each( %$waiting )) {
        warn "Task $task ($shandle) in waiting queue during socket error, queueing for redispatch\n" if DEBUGGING;
        $task->fail;
    }
}

sub process_packet {
    my Gearman::Client::Async::Connection $self = shift;
    my $res = shift;

    if ($res->{type} eq "job_created") {
        my Gearman::Task $task = shift @{ $self->{need_handle} } or
            die "Um, got an unexpected job_created notification";

        my $shandle = ${ $res->{'blobref'} };

        # did sock become disconnected in the meantime?
        if ($self->{state} ne 'ready') {
            $self->_fail_jshandle($shandle);
            return 1;
        }

        push @{ $self->{waiting}->{$shandle} ||= [] }, $task;
        return 1;
    }

    if ($res->{type} eq "work_fail") {
        my $shandle = ${ $res->{'blobref'} };
        $self->_fail_jshandle($shandle);
        return 1;
    }

    if ($res->{type} eq "work_complete") {
        ${ $res->{'blobref'} } =~ s/^(.+?)\0//
            or die "Bogus work_complete from server";
        my $shandle = $1;

        my $task_list = $self->{waiting}{$shandle} or
            die "Uhhhh:  got work_complete for unknown handle: $shandle\n";

        my Gearman::Task $task = shift @$task_list or
            die "Uhhhh:  task_list is empty on work_complete for handle $shandle\n";

        $task->complete($res->{'blobref'});
        delete $self->{waiting}{$shandle} unless @$task_list;

        warn "Jobs: " . scalar( keys( %{$self->{waiting}} ) ) . "\n" if DEBUGGING;

        return 1;
    }

    if ($res->{type} eq "work_status") {
        my ($shandle, $nu, $de) = split(/\0/, ${ $res->{'blobref'} });

        my $task_list = $self->{waiting}{$shandle} or
            die "Uhhhh:  got work_status for unknown handle: $shandle\n";

        # FIXME: the server is (probably) sending a work_status packet for each
        # interested client, even if the clients are the same, so probably need
        # to fix the server not to do that.  just put this FIXME here for now,
        # though really it's a server issue.
        foreach my Gearman::Task $task (@$task_list) {
            $task->status($nu, $de);
        }

        return 1;
    }

    die "Unknown/unimplemented packet type: $res->{type}";

}

# note the failure of a task given by its jobserver-specific handle
sub _fail_jshandle {
    my Gearman::Client::Async::Connection $self = shift;
    my $shandle = shift;

    my $task_list = $self->{waiting}->{$shandle} or
        die "Uhhhh:  got work_fail for unknown handle: $shandle\n";

    my Gearman::Task $task = shift @$task_list or
        die "Uhhhh:  task_list is empty on work_fail for handle $shandle\n";

    $task->fail;
    delete $self->{waiting}{$shandle} unless @$task_list;
}

package Gearman::ResponseParser::Async;

use strict;
use warnings;

use Gearman::ResponseParser;
use base 'Gearman::ResponseParser';

sub new {
    my $class = shift;

    my $self = $class->SUPER::new;

    $self->{_client} = shift;

    return $self;
}

sub on_packet {
    my $self = shift;
    my $packet = shift;

    $self->{_client}->process_packet( $packet );
}

sub on_error {
    my $self = shift;

    $self->{_client}->mark_unsafe;
    $self->{_client}->close;
}

1;
__END__
