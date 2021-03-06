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
    eval 'use Mojo::Server::Daemon; 1' or plan skip_all => $@;
}

use Mojolicious::Lite;

my ($daemon, $port) = _start_daemon();

my %scratch;

my @tests = (
    [
        'server closes immediately w/ failure',
        undef,
        sub {
            my ($c) = @_;

            use utf8;
            $_[0]->finish(1001, 'éé');
        },
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
            );
        },
    ],

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
            );
        },
    ],

    [
        'ping pong, client closes first (binary messages)',
        sub {
            my ($ws) = @_;

            $ws->on_binary( sub {
                my ($ws, $msg) = @_;

                if ($msg > 10) {
                    $ws->close();
                }
                else {
                    $ws->send_binary( 1 + $msg );
                }
            } );

            $ws->send_binary(1);
        },
        sub {
            my ($c) = shift;

            $c->on(
                message => sub {
                    $_[0]->send( { binary => $_[1] + 1 } );
                },
            );
        },
        sub {
            my ($code, $reason) = @{ shift() };
            is( $code, Net::Libwebsockets::CLOSE_STATUS_NO_STATUS, 'code as expected' );
            is( $reason, q<>, 'reason as expected' );
        },
    ],

    [
        'ping pong, server closes first (text messages)',
        sub {
            my ($ws) = @_;

            $ws->on_text( sub {
                my ($ws, $msg) = @_;
                $ws->send_text( 1 + $msg );
            } );

            $ws->send_text(1);
        },
        sub {
            my ($c) = shift;

            $c->on(
                message => sub {
                    my ($c, $payload) = @_;

                    if ($payload > 10) {
                        # server closes:
                        $c->finish();
                    }
                    else {
                        $c->send( $payload + 1 );
                    }
                },
            );
        },
        sub {
            my ($code, $reason) = @{ shift() };
            is( $code, Net::Libwebsockets::CLOSE_STATUS_NO_STATUS, 'code as expected' );
            is( $reason, q<>, 'reason as expected' );
        },
    ],

    [
        'server sends fragmented messages',
        sub {
            my ($ws) = @_;

            $ws->on_binary( sub {
                my ($ws, $msg) = @_;
                push @{ $scratch{'messages'} }, $msg;
            } );
        },

        sub {
            my ($c) = shift;

            $c->send(
                [ 0, (0) x 3, 2, 'two-' ],
            );

            $c->send(
                [ 1, (0) x 3, 0, 'part' ],
            );

            # --------------------

            $c->send(
                [ 0, (0) x 3, 2, 'three-' ],
            );

            $c->send(
                [ 0, (0) x 3, 0, 'pa' ],
            );

            $c->send(
                [ 1, (0) x 3, 0, 'rt' ],
            );

            # --------------------

            $c->send(
                [ 0, (0) x 3, 2, 'four-' ],
            );

            $c->send(
                [ 0, (0) x 3, 0, 'p' ],
            );

            $c->send(
                [ 0, (0) x 3, 0, 'a' ],
            );

            $c->send(
                [ 1, (0) x 3, 0, 'rt' ],
            );

            $c->finish();
        },

        sub {
            my ($code, $reason) = @{ shift() };

            is_deeply(
                \%scratch,
                {
                    messages => [
                        'two-part',
                        'three-part',
                        'four-part',
                    ],
                },
                'messages as expected',
            );

            is( $code, Net::Libwebsockets::CLOSE_STATUS_NO_STATUS, 'code as expected' );
            is( $reason, q<>, 'reason as expected' );
        },
    ],
);

for my $t_ar (@tests) {
    my ($label, $client, $server, $pass_cr, $fail_cr) = @$t_ar;

    note $label;

    my $route = websocket '/' => $server || sub {
        my $c = shift;

        # Mojo needs at least one listener or else it
        # fails weirdly.
        $c->on( close => sub { } );
    };

    my $logger = Net::Libwebsockets::Logger->new();

    my @event_settings = (
        [
            ('Mojolicious') x 2,
            sub { Mojo::IOLoop->start() },
            sub { Mojo::IOLoop->stop() },
        ],
    );

    if (eval { require IO::Async::Loop::Mojo }) {
        _rewrite_broken_later_method_rt_139999();

        my $loop = IO::Async::Loop::Mojo->new();
        push @event_settings, [
            'IO::Async',
            [ IOAsync => $loop ],
            sub { $loop->run() },
            sub { $loop->stop() },
        ];
    }
    else {
        note "Install IO::Async::Loop::Mojo to test IO::Async.";
    }

    for my $event_setting (@event_settings) {
        my ($label, $event_opt, $start_cr, $end_cr) = @$event_setting;

        %scratch = ();

        note "Event interface: $label";

        Net::Libwebsockets::WebSocket::Client::connect(
            url => "ws://127.0.0.1:$port",
            event => $event_opt,
            headers => [
                'X-Foo' => 'Bar',
            ],
            logger => $logger,
            on_ready => $client || sub { },
        )->then(
            $pass_cr || sub {
                fail "unexpected success: $_[0]";
            },
            $fail_cr || sub {
                fail "unexpected failure: $_[0]";
            },
        )->finally( $end_cr );

        $start_cr->();
    }

    $route->remove();
    app()->routes()->cache(Mojo::Cache->new);
}

done_testing;

#----------------------------------------------------------------------

# Connect application with web server and start accepting connections
sub _start_daemon {
    my $daemon = Mojo::Server::Daemon->new(
        app => app,
        listen => ['http://127.0.0.1:0'],
    );

    $daemon->on(request => sub {
        my ($daemon, $tx) = @_;

        diag "====== Server received request\n";

        $tx->resume;
    } );

    $daemon->start;

    my ($port) = @{ $daemon->ports() };

    diag "Port: $port";

    return ($daemon, $port);
}

sub _rewrite_broken_later_method_rt_139999 {
    no warnings ('once', 'redefine');
    *IO::Async::Loop::Mojo::later = sub {
        my ($self, $cb) = @_;

        $self->watch_time(
            after => 0,
            code => $cb,
        );
    };

    return;
}
