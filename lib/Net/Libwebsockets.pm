package Net::Libwebsockets;

use strict;
use warnings;

our $VERSION;

use XSLoader ();

BEGIN {
    $VERSION = '0.02';
    XSLoader::load( __PACKAGE__, $VERSION );
}

=encoding utf-8

=head1 NAME

Net::Libwebsockets - L<libwebsockets|https://libwebsockets.org> in Perl

=head1 SYNOPSIS

WebSocket with L<AnyEvent> (L<IO::Async> is supported, too):

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

    # This promise finishes when the connection is done.
    # On successful close it resolves with [ $code, $reason ];
    # see the documentation for failure-case behavior.
    #
    $done_p->then(
        sub ($status_reason_ar) { say 'WebSocket finished OK' },
        sub ($err) {
            warn "WebSocket non-success: $err";
        },
    )->finally($cv);

Look at L<Net::Libwebsockets::WebSocket::Client> for documentation
of the above.

=head1 DESCRIPTION

This module provides a Perl binding to
L<libwebsockets|https://libwebsockets.org/> (aka “LWS”), a C
library that provides client and server implementations of
L<WebSocket|https://www.rfc-editor.org/rfc/rfc6455.html>
and L<HTTP/2|https://httpwg.org/specs/rfc7540.html>, among other
protocols.

=head1 STATUS

This module currently only implements WebSocket, and only as a client.
(cf. L<Net::Libwebsockets::WebSocket::Client>)
This is all B<EXPERIMENTAL>, so all interfaces are subject to change,
and any part of it can blow up in any way at any time.

That said, it’s been in development for some time, and it should be
useful enough to play with. Error reporting and memory-leak detection
have received especial care. LWS itself is used on tens of millions
of devices, so any issues you encounter will likely be solvable readily
by fixing this little module rather than delving into LWS.

Note the following:

=over

=item * LWS version 4.3.0 or later is required.
(As of this writing that’s the latest release.)

=item * Some LWS builds lack useful stuff like WebSocket compression
or non-blocking DNS queries. If in doubt, check your build.

=back

=head1 BUILDING

This module, as of this writing, needs a newer LWS build than most OSes
provide. To use Net::Libwebsockets, then, you may need to build your own
LWS, then link this module against that build. To simplify that,
you can define a C<LWS_BUILD_DIR> environment variable when you run
this module’s provided F<Makefile.PL> script. C<LWS_BUILD_DIR> tells
F<Makefile.PL> where to find your custom LWS build, which avoids the
need to install your custom build globally.

As of this writing
L<LWS’s upstream main branch|https://github.com/warmcat/libwebsockets/tree/main>
includes several useful fixes & improvements beyond what the latest
release provides. It is thus recommended to build from that branch.

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

=head1 MEMORY LEAK DETECTION

Most objects here emit a warning if their DESTROY()
method runs at global-destruction time. This usually means either you
stored such an object in a global, or you have a memory leak. To silence
the warning in the former case, just clear your global at END time.
In the latter case, fix your code. :)

=head1 SEE ALSO

Other CPAN WebSocket implementations include:

=over

=item * L<Net::WebSocket> - Maximum flexibility.

=item * L<Mojolicious> - Maximum simplicity.

=item * L<Net::WebSocket::Server> - Server implementation only.
(No relation to L<Net::WebSocket>!)

=item * L<Net::Async::WebSocket> - WebSocket for L<IO::Async>

=item * L<AnyEvent::WebSocket::Client> - L<AnyEvent> WS server

=item * L<AnyEvent::WebSocket::Server>  - L<AnyEvent> WS client

=item * L<Protocol::WebSocket> - Early, bare-bones, used in some of the
others.

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

Most of this distribution’s controls lie in submodules; however,
the present package does expose some functionality of its own:

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
