package FileSend::SCP;

use Net::SCP;

sub send_file {
    my ($class, $source, $dest) = @_;

    my $scp = Net::SCP->new;
    print "scp: $source => $dest: ";
    my $rv = $scp->scp($source, $dest);
    if ($rv) {
        print "okay\n";
    } else {
        print $scp->{errstr} . "\n";
    }
}

1;
