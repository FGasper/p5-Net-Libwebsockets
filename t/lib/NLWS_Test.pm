package NLWS_Test;

use strict;
use warnings;
use autodie;

use Socket;

sub loopback_can_serve {
    socket my $s, Socket::AF_INET, Socket::SOCK_STREAM, 0;

    bind $s, Socket::pack_sockaddr_in(0, "\x7f\0\0\1");
    listen $s, 1;

    my ($port) = Socket::unpack_sockaddr_in(getsockname $s);

    socket my $c, Socket::AF_INET, Socket::SOCK_STREAM, 0;

    my $ok = eval {
        connect $c, Socket::pack_sockaddr_in($port, "\x7f\0\0\1");
        1;
    };

    return 1 if $ok;

    warn;
    return 0;
}

1;
