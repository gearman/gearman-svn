package Gearman::Client::Async::Connection;
use strict;
use warnings;

use Danga::Socket;
use base 'Danga::Socket';
use fields (
            'state',
            'waiting',
            'need_handle', # arrayref of Gearman::Task objects which
                           # have been submitted but need handles.
            'parser',
            'hostspec',   # scalar: "host:ip"
            'to_send',
            'deadtime',
            );

use constant S_DISCONNECTED => \ "disconnected";
use constant S_CONNECTING   => \ "connecting";
use constant S_READY        => \ "ready";

use Carp qw(croak);
use Gearman::Task;
use Gearman::Util;

use IO::Handle;
use Socket qw(PF_INET IPPROTO_TCP TCP_NODELAY SOL_SOCKET SOCK_STREAM);

sub DEBUGGING () { 1 }

sub new {
    my Gearman::Client::Async::Connection $self = shift;

    my %opts = @_;

    $self = fields::new( $self ) unless ref $self;

    $self->{hostspec}    = delete( $opts{hostspec} ) or
        croak("hostspec required");

    $self->{state}       = S_DISCONNECTED;
    $self->{waiting}     = {};
    $self->{need_handle} = [];
    $self->{to_send}     = [];
    $self->{deadtime}    = 0;

    croak "Unknown parameters: " . join(", ", keys %opts) if %opts;
    return $self;
}

sub close_when_finished {
    my Gearman::Client::Async::Connection $self = shift;
    # FIXME: implement
}

sub hostspec {
    my Gearman::Client::Async::Connection $self = shift;

    return $self->{hostspec};
}

sub connect {
    my Gearman::Client::Async::Connection $self = shift;

    $self->{state} = S_CONNECTING;

    my ($host, $port) = split /:/, $self->{hostspec};
    $port ||= 7003;

    socket my $sock, PF_INET, SOCK_STREAM, IPPROTO_TCP;
    IO::Handle::blocking($sock, 0);
    setsockopt($sock, IPPROTO_TCP, TCP_NODELAY, pack("l", 1)) or die;

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

    if ($self->{state} == S_CONNECTING) {
        $self->{state} = S_READY;
    }

    my $tasks = $self->{to_send};

    if (@$tasks and $self->{state} == S_READY) {
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
    unless (defined $input) {
        $self->close( "EOF" );
        return;
    }

    $self->{parser}->parse_data( $input );
}

sub event_err {
    my Gearman::Client::Async::Connection $self = shift;

    if (DEBUGGING and $self->{state} == S_CONNECTING) {
        warn "Jobserver, $self->{hostspec} ($self) has failed to connect properly\n";
    }

    $self->mark_dead;
    $self->close( "error" );
}

sub close {
    my Gearman::Client::Async::Connection $self = shift;
    my $reason = shift;

    if ($self->{state} != S_DISCONNECTED) {
        $self->{state} = S_DISCONNECTED;
        $self->SUPER::close( $reason );
    }

    $self->_requeue_all;
}

sub mark_dead {
    my Gearman::Client::Async::Connection $self = shift;
    $self->{deadtime} = time + 10;
}

sub alive {
    my Gearman::Client::Async::Connection $self = shift;
    return $self->{deadtime} <= time;
}

sub add_task {
    my Gearman::Client::Async::Connection $self = shift;
    my Gearman::Task $task = shift;

    if ($self->{state} == S_DISCONNECTED) {
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
        if ($self->{state} != S_READY) {
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

    # FIXME: flip these two lines?
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

    $self->{_conn} = shift;

    return $self;
}

sub on_packet {
    my $self = shift;
    my $packet = shift;

    $self->{_conn}->process_packet( $packet );
}

sub on_error {
    my $self = shift;

    $self->{_conn}->mark_unsafe;
    $self->{_conn}->close;
}


1;
