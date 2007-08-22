package FileSend::Rsync;

sub send_file {
    my ($class, $source, $dest) = @_;

    my $rv = system("rsync", '-r', '-P', '--size-only', $source, $dest);

    unless ($rv) {
        print "okay\n";
    } else {
        print "error\n";
    }
}

1;
