#!/usr/bin/env perl

use strict;
use warnings;

use Test::More;
use Test::FailWarnings;
use Test::Deep;

use Net::Libwebsockets::WebSocket::Client;
use Net::Libwebsockets::Logger;

use Promise::XS;
$Promise::XS::DETECT_MEMORY_LEAKS = 1;

BEGIN {
    eval 'use AnyEvent; 1' or plan skip_all => $@;
    eval 'use AnyEvent::Socket; 1' or plan skip_all => $@;
    eval 'use AnyEvent::WebSocket::Server; 1' or plan skip_all => $@;
}

my %scratch;

my @tests = (
    [
        'client closes immediately w/ failure',
        sub {
            use utf8;

            my ($ws) = @_;

            $ws->close(1001, 'éé');
        },
        undef,
        undef,
        sub {
            my ($err) = @_;

            cmp_deeply(
                $err,
                all(
                    Isa('Net::Libwebsockets::X::WebSocketClose'),
                    methods(
                        [ get => 'code' ] => Net::Libwebsockets::CLOSE_STATUS_GOINGAWAY,
                        [ get => 'reason' ] => do { use utf8; 'éé' },
                    ),
                ),
                'expected rejection',
            ) or diag explain $err;
        },
    ],
);

#----------------------------------------------------------------------

my $server = AnyEvent::WebSocket::Server->new();

my $port;

my $be_the_server;

my $tcp_server;
$tcp_server = tcp_server(
    '127.0.0.1',
    0,
    sub {
        my ($fh) = @_;

        $server->establish($fh)->cb(sub {
            my $connection = eval { shift->recv };

            if($@) {
                warn "Invalid connection request: $@\n";
                close($fh);
                return;
            }

            if ($be_the_server) {
                $be_the_server->($connection);
            }
            else {
                $connection->on(finish => sub {
                    undef $connection;
                });
            }
        });
    },
    sub {
        $port = $_[2];
    },
);

diag "port: $port";

for my $t_ar (@tests) {
    my ($label, $client, $server, $pass_cr, $fail_cr) = @$t_ar;

    $be_the_server = $server;

    %scratch = ();

    note $label;

    my @logs;

    my $logger = Net::Libwebsockets::Logger->new(
        callback => sub { push @logs, [@_] },
        level => 0b1111111111111,
    );

    my $cv = AnyEvent->condvar();

    Net::Libwebsockets::WebSocket::Client::connect(
        url => "ws://127.0.0.1:$port",
        event => 'AnyEvent',
        logger => $logger,
        on_ready => $client || sub { },
    )->then(
        $pass_cr || sub {
            fail "unexpected success: $_[0]";
        },
        $fail_cr || sub {
            fail "unexpected failure: $_[0]";
        },
    )->finally($cv);

    $cv->recv();
}

done_testing;
