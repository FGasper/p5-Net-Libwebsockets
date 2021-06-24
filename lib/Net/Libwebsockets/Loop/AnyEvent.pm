package Net::Libwebsockets::Loop::AnyEvent;

use strict;
use warnings;

use feature 'current_sub';

use parent 'Net::Libwebsockets::Loop';

use AnyEvent ();

use Net::Libwebsockets ();

sub start_timer {
    my ($self) = @_;

    my $ctx = $self->{'lws_context'} or die "need lws_context!";

    my $pkg = $self->{'context_package'};

    my $get_timeout_cr = $pkg->can('get_timeout');

    my $timer_sr = \$self->{'timer'};

    my $timeout_ms;

    AnyEvent::postpone( sub {
        $timeout_ms = $get_timeout_cr->($ctx);

        print "==== new timeout: $timeout_ms ms\n";

        $$timer_sr = AnyEvent->timer(
            after => $timeout_ms / 1000,

            # Per LWS’s custom event loop example, there’s nothing to *do*
            # on timeout except just start the loop again.
            cb => __SUB__,
        );
    } );
}

sub add_fd {
    $_[2] = Net::Libwebsockets::LWS_EV_READ;

    goto &add_to_fd;
}

sub add_to_fd {
    my ($self, $fd, $flags) = @_;

    my $ctx_sr = \$self->{'lws_context'};

    my $on_readable_cr = $self->{'context_package'}->can('lws_service_fd_read');
    my $on_writable_cr = $self->{'context_package'}->can('lws_service_fd_write');

    if ($flags & Net::Libwebsockets::LWS_EV_READ) {
        $self->{$fd}[0] = AnyEvent->io(
            fh => $fd,
            poll => 'r',
            cb => sub {
                $on_readable_cr->($$ctx_sr, $fd);
            },
        );
    }

    if ($flags & Net::Libwebsockets::LWS_EV_WRITE) {
        $self->{$fd}[1] = AnyEvent->io(
            fh => $fd,
            poll => 'w',
            cb => sub {
                $on_writable_cr->($$ctx_sr, $fd);
            },
        );
    }

    # return omitted to save an op
}

sub remove_from_fd {
    my ($self, $fd, $flags) = @_;

    if ($flags & Net::Libwebsockets::LWS_EV_READ) {
        delete $self->{$fd}[0] or do {
            warn "LWS asked to drop nonexistent reader for FD $fd\n";
        };
    }

    if ($flags & Net::Libwebsockets::LWS_EV_WRITE) {
        delete $self->{$fd}[1] or do {
            warn "LWS asked to drop nonexistent writer for FD $fd\n";
        };
    }

    # return omitted to save an op
}

sub remove_fd {
    my ($self, $fd) = @_;

    delete $self->{$fd};

    # return omitted to save an op
}

1;
