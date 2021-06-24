package Net::Libwebsockets::Loop::IOAsync;

use strict;
use warnings;

use parent 'Net::Libwebsockets::Loop';

use lib '/Users/felipe/code/p5-IO-FDSaver/lib';
use IO::FDSaver;

use feature 'current_sub';

use Net::Libwebsockets ();

use IO::Async::Handle ();

sub new {
    my ($class, $ctx_pkg, $loop) = @_;

    return bless {
        pid => $$,
        context_package => $ctx_pkg,
        loop => $loop,
    }, $class;
}

sub start_timer {
    my ($self) = @_;

    my $ctx = $self->{'lws_context'} or die "need lws_context!";

    my $pkg = $self->{'context_package'};

    my $get_timeout_cr = $pkg->can('get_timeout');

    my $timer_sr = \$self->{'timer'};

    my $timeout_ms;

    my $loop = $self->{'loop'};

    $loop->later( sub {
        $timeout_ms = $get_timeout_cr->($ctx);

        print "==== new timeout: $timeout_ms ms\n";

        $loop->unwatch_time($$timer_sr) if $$timer_sr;

        $$timer_sr = $loop->watch_time(
            after => $timeout_ms / 1000,

            # Per LWS’s custom event loop example, there’s nothing to *do*
            # on timeout except just start the loop again.
            code => __SUB__,
        );
    } );

    # return omitted to save an op
}

sub add_fd {
    my ($self, $fd) = @_;

    my $fh = ($self->{'io_fdsaver'} ||= IO::FDSaver->new())->get_fh($fd);

    my $ctx_sr = \$self->{'lws_context'};

    my $on_readable_cr = $self->{'context_package'}->can('lws_service_fd_read');
    my $on_writable_cr = $self->{'context_package'}->can('lws_service_fd_write');

    $self->{'fd_handle'}{$fd} = IO::Async::Handle->new(
        handle => $fh,
        on_read_ready => sub { $on_readable_cr->($$ctx_sr, $fd) },
        on_write_ready => sub { $on_writable_cr->($$ctx_sr, $fd) },

        want_readready => 1,
        want_writeready => 0,
    );

    $self->{'loop'}->add( $self->{'fd_handle'}{$fd} );

    # return omitted to save an op
}

sub add_to_fd {
    my ($self, $fd, $flags) = @_;

    my $handle = $self->{'fd_handle'}{$fd} or do {
        die "Can’t add polling ($flags) to FD ($fd) that isn’t added!";
    };

    if ($flags & Net::Libwebsockets::LWS_EV_READ) {
        $handle->want_readready(1);
    }

    if ($flags & Net::Libwebsockets::LWS_EV_WRITE) {
        $handle->want_writeready(1);
    }

    # return omitted to save an op
}

sub remove_from_fd {
    my ($self, $fd, $flags) = @_;

    if (my $handle = $self->{'fd_handle'}{$fd}) {
        if ($flags & Net::Libwebsockets::LWS_EV_READ) {
            $handle->want_readready(0);
        }

        if ($flags & Net::Libwebsockets::LWS_EV_WRITE) {
            $handle->want_writeready(0);
        }
    }
    else {
        warn "removing poll $flags from non-polled FD $fd";
    }

    # return omitted to save an op
}

sub remove_fd {
    my ($self, $fd) = @_;

    if (my $handle = delete $self->{'fd_handle'}{$fd}) {
        $self->{'loop'}->remove($handle);
    }
    else {
        warn "LWS wants to remove non-polled FD $fd";
    }

    # return omitted to save an op
}

sub DESTROY {
    my ($self) = @_;

    if ($self->{'timer'}) {
        $self->{'loop'}->unwatch_time($self->{'timer'});
        undef $self->{'timer'};
    }

    return $self->SUPER::DESTROY();
}

1;
