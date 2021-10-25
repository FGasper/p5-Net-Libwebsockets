#!/usr/bin/env perl

use strict;
use warnings;

use Test::More;
use Test::FailWarnings;
use Test::Deep;

use Net::Libwebsockets::WebSocket::Client;

use FindBin;
use lib "$FindBin::Bin/lib";
use CheckTCP;

eval { CheckTCP::via_mojo(); 1 } or plan skip_all => $@;

BEGIN {
    eval 'use Mojo::Server::Daemon; 1' or plan skip_all => $@;
}

#use lib './lib';
#use NLWS_Test;

#NLWS_Test::loopback_can_serve() or do {
#    plan skip_all => 'Loopback can’t serve … skipping test.';
#};

use Mojolicious::Lite;

# Normal action
websocket '/' => sub {
    my ($c) = shift;

    $c->on(
        message => sub {
            $_[0]->send( $_[1] + 1 );
        },
    );
};

# Connect application with web server and start accepting connections
my $daemon = Mojo::Server::Daemon->new(app => app, listen => ['http://127.0.0.1:0']);

$daemon->on(request => sub {
    my ($daemon, $tx) = @_;

    diag "====== Server received request\n";

    $tx->resume;
} );

$daemon->start;

my ($port) = @{ $daemon->ports() };

diag "Port: $port";

my $done_p = Net::Libwebsockets::WebSocket::Client::connect(
    url => "ws://127.0.0.1:$port",
    event => 'Mojolicious',
    on_ready => sub {
        my ($ws) = @_;

        $ws->on_text( sub {
            my ($ws, $msg) = @_;

            if ($_[1] > 100) {
                $ws->close();
            }
            else {
                $ws->send_text( 1 + $msg );
            }
        } );

        $ws->send_text(1);
    },
)->then(
    sub {
        my ($code, $reason) = @{ shift() };
        is( $code, Net::Libwebsockets::CLOSE_STATUS_NO_STATUS, 'code as expected' );
        is( $reason, q<>, 'reason as expected' );
    },
    sub {
        fail "unexpected failure: $_[0]";
    },
)->finally(
    sub { Mojo::IOLoop->stop(); },
);

Mojo::IOLoop->start();

done_testing;
