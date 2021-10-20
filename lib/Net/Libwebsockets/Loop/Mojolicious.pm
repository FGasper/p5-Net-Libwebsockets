package Net::Libwebsockets::Loop::Mojolicious;

use strict;
use warnings;

use feature 'current_sub';

use parent 'Net::Libwebsockets::Loop';

use Mojo::IOLoop ();

use Net::Libwebsockets ();
use Net::Libwebsockets::Loop::FD ();

sub _do_later {
    Mojo::IOLoop->next_tick( $_[1] );
};

sub _create_set_timer_cr {
    my ($self) = @_;

    my $ctx = $self->{'lws_context'} or die "No lws_context!";
    my $timer_sr = \$self->{'timer'};

    return sub {
        Mojo::IOLoop->singleton->reactor->remove($$timer_sr) if $$timer_sr;

        $$timer_sr = Mojo::IOLoop->timer(
            Net::Libwebsockets::_get_timeout($ctx) / 1000,
            __SUB__,
        );
    };
}

sub add_fd {
    my ($self, $fd) = @_;

    my $fh = Net::Libwebsockets::Loop::FD::fd_to_fh($fd);

    my $ctx = $self->{'lws_context'};

    my $set_timer_cr = $self->_get_set_timer_cr();

    Mojo::IOLoop->singleton->reactor->io(
        $fh,
        sub {
            if ($_[1]) {
                Net::Libwebsockets::_lws_service_fd_write($ctx, $fd);
            }
            else {
                Net::Libwebsockets::_lws_service_fd_read($ctx, $fd);
            }

            $set_timer_cr->();
        },
    )->watch($fh, 1);

    $self->{'fd_handle'}{$fd} = $fh;

    return;
}

sub add_to_fd {
    my $fh = $_[0]->{'fd_handle'}{$_[1]} or do {
        die "Can’t add polling ($_[2]) to FD ($_[1]) that isn’t added!";
    };

    Mojo::IOLoop->singleton->reactor->watch(
        $fh,
        $_[2] & Net::Libwebsockets::_LWS_EV_READ,
        $_[2] & Net::Libwebsockets::_LWS_EV_WRITE,
    );
}

sub remove_from_fd {

    if (my $fh = $_[0]->{'fd_handle'}{$_[1]}) {
        Mojo::IOLoop->singleton->reactor->watch(
            $fh,
            $_[2] ^ Net::Libwebsockets::_LWS_EV_READ,
            $_[2] ^ Net::Libwebsockets::_LWS_EV_WRITE,
        );
    }
    else {
        # warn "removing poll $flags from non-polled FD $fd";
    }
}

sub remove_fd {
    my ($self, $fd) = @_;

    if (my $fh = delete $self->{'fd_handle'}{$fd}) {
        Mojo::IOLoop->singleton->reactor->remove($fh);
    }
    else {
        # warn "LWS wants to remove non-polled FD $fd";
    }
}

sub _clear_timer {
    Mojo::IOLoop->singleton->reactor->remove($_[0]{'timer'}) if $_[0]{'timer'};
    undef $_[0]{'timer'};
}

1;
