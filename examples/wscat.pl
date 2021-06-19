#!/usr/bin/env perl

use strict;
use warnings;

use experimental 'signatures';

use AnyEvent;
use AnyEvent::Handle;

use Net::Libwebsockets::WebSocket::Client ();

use IO::SigGuard;

# TODO: beef up
my $url = $ARGV[0] or die "Need URL! (Try: ws://echo.websocket.org)\n";

my $cv = AE::cv();

$_->blocking(0) for (\*STDIN, \*STDOUT);

print STDERR "read event: " . Net::Libwebsockets::LWS_EV_READ . $/;
print STDERR "write event: " . Net::Libwebsockets::LWS_EV_WRITE . $/;

Net::Libwebsockets::WebSocket::Client::connect(
    url => $url,
    event => 'AnyEvent',
)->then(
    sub ($ws) {
print STDERR "============ connected!!\n";

        # 1. Anything we receive from WS should go to STDOUT:

        my $out = AnyEvent::Handle->new(
            fh => \*STDOUT,
            # omitting on_error for brevity
        );

        $ws->on_binary(
            sub ($msg) {
                $out->push_write($msg);
            },
        );

        # 2. Anything we receive from STDIN should go to WS:

        my $in_w;
        $in_w = AnyEvent->io(
            fh => \*STDIN,
            poll => 'r',
            cb => sub {
                my $in = IO::SigGuard::sysread( \*STDIN, my $buf, 65536 );

                if ($in) {
                    $ws->send_binary($buf);
                }
                else {
                    undef $in_w;

                    my $close_code;

                    if (!defined $in) {
                        warn "read(STDIN): $!";
                        $close_code = 1011;
                    }
                    else {
                        $close_code = 1000;
                    }

                    $ws->close($close_code);
                }
            },
        );

        return $ws->done_p();
    },
)->then(
    $cv,
    sub { $cv->croak() }
);

$cv->recv();
