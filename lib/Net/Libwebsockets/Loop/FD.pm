package Net::Libwebsockets::Loop::FD;

use strict;
use warnings;

use POSIX ();

sub fd_to_fh {
    my $perl_fd = POSIX::dup($_[0]) or die "dup(FD $_[0]): $!";

    open( my $fh, '+<&=', $perl_fd ) or die "open(FD $perl_fd): $!";

    return $fh;
}

1;
