package FileSend;

use Class::Autouse qw(FileSend::SCP FileSend::Rsync);

sub gearman_servers {
    my $class = shift;

    # FIXME: need configuration
    return [ qw(127.0.0.1) ];
}

sub gearman_client {
    my $class = shift;

    return Gearman::Client->new( job_servers => [ $class->gearman_servers ]);
}

sub gearman_worker {
    my $class = shift;
    my $subref = shift;

    my $worker = Gearman::Worker->new( job_servers => $class->gearman_servers );
    $worker->register_function('send_file' => $subref);
    $worker->work while 1;
}

sub backend_of_transport {
    my $class = shift;
    my $backend_arg = shift;

    return {
        scp   => "SCP",
        rsync => "Rsync",
    }->{lc($backend_arg)};
}

1;
