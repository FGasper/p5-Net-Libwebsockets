package Net::Libwebsockets::Loop::IOAsync;

use strict;
use warnings;

use parent 'Net::Libwebsockets::Loop';

use Scalar::Util;

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

    my $loop = $self->{'loop'};

    $loop->later( sub { $self->set_timer() } );

    # return omitted to save an op
}

sub set_timer {
    my ($self) = @_;

    my $timeout_ms = $self->{'context_package'}->can('get_timeout')->($self->{'lws_context'});

    print "==== new timeout: $timeout_ms ms\n";

    my $weak_self = $self;
    Scalar::Util::weaken($weak_self);

    my $loop = $self->{'loop'};

    $loop->unwatch_time($self->{'timer'}) if $self->{'timer'};

    $self->{'timer'} = $loop->watch_time(
        after => $timeout_ms / 1000,
        code => sub {
            $weak_self && $weak_self->set_timer();
        },
    );
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
