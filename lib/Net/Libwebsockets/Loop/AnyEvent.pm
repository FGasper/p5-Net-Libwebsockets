package Net::Libwebsockets::Loop::AnyEvent;

use strict;
use warnings;

use feature 'current_sub';

use parent 'Net::Libwebsockets::Loop';

use AnyEvent ();

use Scalar::Util ();

use Net::Libwebsockets ();

sub start_timer {
    my ($self) = @_;

    AnyEvent::postpone( sub { $self->set_timer() } );
}

sub set_timer {
    my ($self) = @_;

    my $timeout_ms = $self->{'context_package'}->can('get_timeout')->($self->{'lws_context'});

    print "==== new timeout: $timeout_ms ms\n";

    my $weak_self = $self;
    Scalar::Util::weaken($weak_self);

    undef $self->{'timer'};
    $self->{'timer'} = AnyEvent->timer(
        after => $timeout_ms / 1000,
        cb => sub {
            $weak_self && $weak_self->set_timer();
        },
    );
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

sub DESTROY {
    my ($self) = @_;

    $self->{'timer'} = undef;

    return $self->SUPER::DESTROY();
}

1;
