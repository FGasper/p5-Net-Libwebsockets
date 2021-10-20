#!/usr/bin/env perl

use strict;
use warnings;

use Test::More;
use Test::FailWarnings;
use Test::Deep;

use Net::Libwebsockets::WebSocket::Client;

BEGIN {
    eval 'use Mojo::Server::Daemon; 1' or plan skip_all => $@;
}

use Mojolicious::Lite;

# Normal action
websocket '/' => sub {
    my ($c) = shift;

    $c->on(
        message => sub {
            if ($_[1] > 100) {
                # server closes:
                $c->finish();
            }
            else {
                $c->send( $_[1] + 1 );
            }
        },
    );
};

# Connect application with web server and start accepting connections
my $daemon = Mojo::Server::Daemon->new(app => app, listen => ['http://*:0']);

$daemon->on(request => sub {
    my ($daemon, $tx) = @_;

    diag "====== Server received request\n";

    $tx->resume;
} );

$daemon->start;

my ($port) = @{ $daemon->ports() };

diag "Port: $port";

my $done_p = Net::Libwebsockets::WebSocket::Client::connect(
    url => "ws://localhost:$port",
    event => 'Mojolicious',
    on_ready => sub {
        my ($ws) = @_;

        $ws->on_text( sub {
            my ($ws, $msg) = @_;
            $ws->send_text( 1 + $msg );
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
