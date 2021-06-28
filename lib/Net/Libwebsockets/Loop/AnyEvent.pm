package Net::Libwebsockets::Loop::AnyEvent;

use strict;
use warnings;

use feature 'current_sub';

use parent 'Net::Libwebsockets::Loop';

use AnyEvent ();

use Net::Libwebsockets ();

sub _do_later {
    shift;
    &AnyEvent::postpone;
};

sub _create_set_timer_cr {
    my ($self) = @_;

    my $ctx = $self->{'lws_context'} or die "No lws_context!";
    my $timer_sr = \$self->{'timer'};

    return sub {
        $$timer_sr = AnyEvent->timer(
            after => Net::Libwebsockets::get_timeout($ctx) / 1000,
            cb => __SUB__,
        );
    };
}

sub add_fd {
    $_[2] = Net::Libwebsockets::LWS_EV_READ;

    goto &add_to_fd;
}

sub add_to_fd {
    my ($self, $fd, $flags) = @_;

    my $ctx = $self->{'lws_context'} or die "No lws_context!";

    my $set_timer_cr = $self->_get_set_timer_cr();

    if ($flags & Net::Libwebsockets::LWS_EV_READ) {
        $self->{$fd}[0] = AnyEvent->io(
            fh => $fd,
            poll => 'r',
            cb => sub {
                Net::Libwebsockets::lws_service_fd_read($ctx, $fd);
                &$set_timer_cr;
            },
        );
    }

    if ($flags & Net::Libwebsockets::LWS_EV_WRITE) {
        $self->{$fd}[1] = AnyEvent->io(
            fh => $fd,
            poll => 'w',
            cb => sub {
                Net::Libwebsockets::lws_service_fd_write($ctx, $fd);
                &$set_timer_cr;
            },
        );
    }

    # return omitted to save an op
}

sub remove_from_fd {
    my ($self, $fd, $flags) = @_;

    if ($flags & Net::Libwebsockets::LWS_EV_READ) {
        delete $self->{$fd}[0];
#        delete $self->{$fd}[0] or do {
#            warn "LWS asked to drop nonexistent reader for FD $fd\n";
#        };
    }

    if ($flags & Net::Libwebsockets::LWS_EV_WRITE) {
        delete $self->{$fd}[1];
#        delete $self->{$fd}[1] or do {
#            warn "LWS asked to drop nonexistent writer for FD $fd\n";
#        };
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
