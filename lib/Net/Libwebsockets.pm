package Net::Libwebsockets;

use strict;
use warnings;

our $VERSION;

use XSLoader ();

BEGIN {
    $VERSION = '0.01_01';
    XSLoader::load();
}

=encoding utf-8

=head1 NAME

Net::Libwebsockets - L<libwebsockets|https://libwebsockets.org/> in Perl

=head1 SYNOPSIS

WebSocket with L<AnyEvent>:

    my $cv = AE::cv();

    Net::Libwebsockets::WebSocket::Client::connect(
        url   => 'wss://echo.websocket.org',
        event => 'AnyEvent',
    )->then(
        sub ($courier) {
            $courier->send_text( $characters );
            $courier->send_binary( $bytes );

            # If a message arrives for a type that has no listener,
            # a warning is thrown.
            $courier->on_text( sub ($characters) { .. } );
            $courier->on_binary( sub ($bytes) { .. } );

            return $courier->done_p();
        },
    )->finally($cv);

    # $connect_p resolves when the WS handshake completes successfully.
    # The value is an object, called a “courier”, that ferries messages
    # between the caller and the peer.

    my $done_p = $connect_p->then(


    );

    # This promise finishes when the connection is done:
    #   - On successful close: resolve with [ $code, $reason ]
    #
    #   - On non-success close: promise rejects with
    #       Net::Libwebsockets::X::WebSocket::BadClose.
    #
    #   - On connection error: promise rejects with
    #       a string that describes the failure.
    #
    $done_p->then(
        sub ($status_reason_ar) { say 'WebSocket finished OK' },
        sub ($err) {
            warn "WebSocket non-success: $err";
        },
    );

=head1 DESCRIPTION

Several CPAN modules implement the
L<WebSocket|https://www.rfc-editor.org/rfc/rfc6455.html> protocol for
use in Perl, but as of this writing they all implement the entire protocol
in pure Perl.

This module provides a WebSocket implementation for Perl via XS and
L<libwebsockets|https://libwebsockets.org/> (aka “LWS”), a lightweight C
library.

=head1 STATUS

This module is B<EXPERIMENTAL>, but it should be useful enough
to play with.

Note the following:

=over

=item * This library needs LWS version 4.3.0 or later.

=item * Some LWS builds lack WebSocket compression support.

=item * Logging configuration is global for now. A later version of
this library will support LWS’s per-instance logging.

=back

=head1 SEE ALSO

Other CPAN WebSocket implementations include:

=over

=item * L<Net::WebSocket>

=item * L<Mojolicious>

=item * L<Net::Async::WebSocket> (No compression support)

=item * L<AnyEvent::WebSocket::Client>

=item * L<AnyEvent::WebSocket::Server>

=item * L<Protocol::WebSocket>

=back

=cut

1;
