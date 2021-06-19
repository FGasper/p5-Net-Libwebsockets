package Net::Libwebsockets::Loop::AnyEvent;

use strict;
use warnings;

use parent 'Net::Libwebsockets::Loop';

use AnyEvent ();

use Net::Libwebsockets ();

sub add_fd {
    $_[2] = Net::Libwebsockets::LWS_EV_READ;

    goto &add_to_fd;
}

sub add_to_fd {
    my ($self, $fd, $edits) = @_;
#print "add to FD: $fd ($edits)\n";

    my $ctx_sr = \$self->{'lws_context'};

    my $runner_cr = $self->{'context_package'}->can('lws_service_fd') or do {
        die "$self->{'context_package'} lacks lws_service_fd()!";
    };

    if ($edits & Net::Libwebsockets::LWS_EV_READ) {
        $self->{$fd}[0] = AnyEvent->io(
            fh => $fd,
            poll => 'r',
            cb => sub {
print STDERR "=== FD $fd is readable\n";
                $runner_cr->($$ctx_sr, $fd, Net::Libwebsockets::LWS_EV_READ);
            },
        );
    }

    if ($edits & Net::Libwebsockets::LWS_EV_WRITE) {
        $self->{$fd}[1] = AnyEvent->io(
            fh => $fd,
            poll => 'w',
            cb => sub {
print STDERR "=== FD $fd is writable\n";
warn if !eval {
use Data::Dumper;
$Data::Dumper::Deparse = 1;
print STDERR "===== in eval\n";
print STDERR Dumper $runner_cr;
                $runner_cr->($$ctx_sr, $fd, Net::Libwebsockets::LWS_EV_WRITE);
print STDERR "===== end eval\n";
1;
};
print STDERR "=== after FD $fd is writable\n";
            },
        );
    }

    # return omitted to save an op
}

sub remove_from_fd {
    my ($self, $fd, $edits) = @_;
#print "remove from FD: $fd ($edits)\n";

    if ($edits & Net::Libwebsockets::LWS_EV_READ) {
        delete $self->{$fd}[0] or do {
            warn "LWS asked to drop nonexistent reader for FD $fd\n";
        };
    }

    if ($edits & Net::Libwebsockets::LWS_EV_WRITE) {
        delete $self->{$fd}[1] or do {
            warn "LWS asked to drop nonexistent writer for FD $fd\n";
        };
    }

    # return omitted to save an op
}

sub remove_fd {
    my ($self, $fd) = @_;
print "remove FD: $fd\n";

    delete $self->{$fd};

    # return omitted to save an op
}

1;
