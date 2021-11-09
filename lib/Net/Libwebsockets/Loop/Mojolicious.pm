package Net::Libwebsockets::Loop::Mojolicious;

use strict;
use warnings;

use feature 'current_sub';

use parent 'Net::Libwebsockets::Loop';

use Mojo::IOLoop ();

use Net::Libwebsockets ();
use Net::Libwebsockets::Loop::FD ();

use constant DEBUG => 0;

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

    DEBUG && printf STDERR "%s, FD %d\n", (caller 0)[3], $fd;

    my $fh = Net::Libwebsockets::Loop::FD::fd_to_fh($fd);

    my $ctx = $self->{'lws_context'};

    my $set_timer_cr = $self->_get_set_timer_cr();

    $self->{'fd_watching'}{$fd} = Net::Libwebsockets::_LWS_EV_READ;
    $self->{'fd_handle'}{$fd} = $fh;

    Mojo::IOLoop->singleton->reactor->io(
        $fh,
        sub {
            if ($_[1]) {
                DEBUG && printf STDERR "%s - FD %d readable\n", __PACKAGE__, $fd;
                Net::Libwebsockets::_lws_service_fd_write($ctx, $fd);
            }
            else {
                DEBUG && printf STDERR "%s - FD %d writable\n", __PACKAGE__, $fd;
                Net::Libwebsockets::_lws_service_fd_read($ctx, $fd);
            }

            $set_timer_cr->();
        },
    )->watch($fh, 1);

    return;
}

sub add_to_fd {
    my $fh = $_[0]->{'fd_handle'}{$_[1]} or do {
        die "Can’t add polling ($_[2]) to FD ($_[1]) that isn’t added!";
    };

    if (DEBUG) {
        if ($_[2] & Net::Libwebsockets::_LWS_EV_READ) {
            DEBUG && printf STDERR "%s, FD %d - read\n", (caller 0)[3], $_[1];
        }
        if ($_[2] & Net::Libwebsockets::_LWS_EV_WRITE) {
            DEBUG && printf STDERR "%s, FD %d - write\n", (caller 0)[3], $_[1];
        }
    }

    @_ = ($fh, $_[0]->{'fd_watching'}{$_[1]} |= $_[2]);

    goto &_refresh_watch;
}

sub remove_from_fd {
    my $fh = $_[0]->{'fd_handle'}{$_[1]} or return;

    if (DEBUG) {
        if ($_[2] & Net::Libwebsockets::_LWS_EV_READ) {
            DEBUG && printf STDERR "%s, FD %d - read\n", (caller 0)[3], $_[1];
        }
        if ($_[2] & Net::Libwebsockets::_LWS_EV_WRITE) {
            DEBUG && printf STDERR "%s, FD %d - write\n", (caller 0)[3], $_[1];
        }
    }

    @_ = ($fh, $_[0]->{'fd_watching'}{$_[1]} ^= $_[2]);

    goto &_refresh_watch;
}

sub _refresh_watch {
    Mojo::IOLoop->singleton->reactor->watch(
        $_[0],
        $_[1] & Net::Libwebsockets::_LWS_EV_READ,
        $_[1] & Net::Libwebsockets::_LWS_EV_WRITE,
    );
}

sub remove_fd {
    my ($self, $fd) = @_;

    if (my $fh = delete $self->{'fd_handle'}{$fd}) {
        delete $self->{'fd_watching'}{$fd};

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
