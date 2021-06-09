package Net::Libwebsockets;

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Net::Libwebsockets

=head1 SYNOPSIS

    my $ws_p = Net::Libwebsockets::WebSocket::connect(
        'wss://echo.websocket.org',
        [ 'protocol1', 'protocol2', .. ],   # optional
        { default => 'default' },           # optional
    );

    my $done_p = $ws_p->then( sub ($courier) {

        $courier->send_text( $characters );
        $courier->send_binary( $bytes );

        # If a message arrives for a type that has no listener,
        # a warning is thrown.
        $courier->on_text( sub ($characters) { .. } );
        $courier->on_binary( sub ($bytes) { .. } );

        # This promise finishes when the connection is done:
        #   - On success: promise resolves with the WS close “reason”
        #
        #   - On non-success close: promise rejects with
        #       Net::Libwebsockets::X::BadClose. (This includes
        #       the case where the WS close lacks a status code.)
        #
        #   - On connection error: promise rejects with
        #       a string that describes the failure.
        #
        # NB: EVEN ON SUCCESS, if there’s no promise that can handle
        # the failure states, a warning is thrown. This is by design
        # to discourage insufficient error checking.
        #
        return $courier->done_p();
    } );


=cut

our $VERSION;

use XSLoader ();

BEGIN {
    $VERSION = '0.01_01';
    XSLoader::load();
}

1;
