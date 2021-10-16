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

Net::Libwebsockets - L<libwebsockets|https://libwebsockets.org> in Perl

=head1 SYNOPSIS

WebSocket with L<AnyEvent>:

    my $cv = AE::cv();

    my $done_p = Net::Libwebsockets::WebSocket::Client::connect(
        url   => 'wss://echo.websocket.org',
        event => 'AnyEvent',
        on_ready => sub ($courier) {

            # $courier ferries messages between the caller and the peer:

            $courier->send_text( $characters );
            $courier->send_binary( $bytes );

            # If a message arrives for a type that has no listener,
            # a warning is thrown.
            $courier->on_text( sub ($characters) { .. } );
            $courier->on_binary( sub ($bytes) { .. } );
        },
    );

    # This promise finishes when the connection is done:
    #   - On successful close: resolve with [ $code, $reason ]
    #
    #   - On non-success close: promise rejects with
    #       Net::Libwebsockets::X::WebSocketClose.
    #
    #   - On connection error: promise rejects with
    #       a string that describes the failure.
    #
    $done_p->then(
        sub ($status_reason_ar) { say 'WebSocket finished OK' },
        sub ($err) {
            warn "WebSocket non-success: $err";
        },
    )->finally($cv);

=head1 DESCRIPTION

This module provides a Perl binding to
L<libwebsockets|https://libwebsockets.org/> (aka “LWS”), a lightweight C
library that provides client and server implementations of
L<WebSocket|https://www.rfc-editor.org/rfc/rfc6455.html>
and L<HTTP/2|https://httpwg.org/specs/rfc7540.html>, among other
protocols.

=head1 STATUS

This module currently only implements WebSocket, and only as a client.
It is B<EXPERIMENTAL>, but it should be useful enough to play with.

Note the following:

=over

=item * LWS version 4.3.0 or later is required.

=item * Some LWS builds lack WebSocket compression support.

=back

=head1 EVENT LOOP SUPPORT

This module supports most of Perl’s popular event loops via either
L<IO::Async> or L<AnyEvent>.

=head1 LOGGING

LWS historically configured its logging globally; i.e., all LWS contexts
within a process shared the same logging configuration.

LWS 4.3.0 introduced context-specific logging alongside the old
global-state functions. As of this writing, though, most of LWS’s internal
logger calls still use the older functions, which means those log
statements will go out however the global logging is configured, regardless
of whether there’s a context-specific logging configuration for a given
action. Conversion of existing log statements is ongoing.

This library supports both LWS’s old/global and new/contextual logging.
See L<Net::Libwebsockets::Logger> and C<set_log_level()> below for more
details.

=head1 ERRORS

Most of this module’s error classes extend L<X::Tiny::Base>. Errors that
are more likely to be programmer misuse than runtime failure are more apt
to be simple strings.

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

=head1 CONSTANTS

This package exposes the following constants. For their meanings
see LWS’s documentation.

=over

=item * C<HAS_PMD> - A boolean that indicates whether
WebSocket compression (i.e., L<per-message deflate|https://datatracker.ietf.org/doc/html/rfc7692#page-12>, or C<PMD>) is available.

=item * Log levels: C<LLL_ERR> et al. (L<See here for the others.|https://libwebsockets.org/lws-api-doc-master/html/group__log.html>)

=item * TLS/SSL-related: C<LCCSCF_ALLOW_SELFSIGNED>, C<LCCSCF_SKIP_SERVER_CERT_HOSTNAME_CHECK>, C<LCCSCF_ALLOW_EXPIRED>, C<LCCSCF_ALLOW_INSECURE>

=back

=head1 FUNCTIONS

Most of this distribution’s functionality lies in submodules; however,
this package does expose some controls of its own:

=head2 set_log_level( $LEVEL )

Sets LWS’s global log level, which is the bitwise-OR of the log-level
constants referenced above. For example, to see only errors and warnings
you can do:

    Net::Libwebsockets::set_log_level(
        Net::Libwebsockets::LLL_ERR | Net::Libwebsockets::LLL_WARN
    );

LWS allows setting a callback to direct log output to someplace other
than STDERR. This library, though, does not (currently?) support that
except via contextual logging (L<Net::Libwebsockets::Logger>).

=cut

1;
