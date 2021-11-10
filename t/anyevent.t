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
    eval 'use Protocol::WebSocket::Frame; 1' or plan skip_all => $@;
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

    [
        'server sends fragmented messages',
        sub {
            my ($ws) = @_;

            $ws->on_binary( sub {
                push @{$scratch{'messages'}}, $_[1];
            } );
        },
        sub {
            diag 'in server';

            my ($connection) = @_;

            my $handle = $connection->handle();

            $handle->push_write(
                Protocol::WebSocket::Frame->new(
                    buffer => 'two-',
                    type => 'binary',
                    fin => 0,
                    masked => 1,
                )->to_bytes()
            );

            $handle->push_write(
                Protocol::WebSocket::Frame->new(
                    buffer => 'part',
                    type => 'continuation',
                    fin => 1,
                    masked => 1,
                )->to_bytes()
            );

            # ------------------------------

            my @frames = (
                [
                    buffer => 'three-',
                    type => 'binary',
                    fin => 0,
                ],
                [
                    buffer => 'paaaa',
                    type => 'continuation',
                    fin => 0,
                ],
                [
                    buffer => 'rt',
                    type => 'continuation',
                    fin => 1,
                ],
            );

            for (@frames) {
                $_ = Protocol::WebSocket::Frame->new(
                    @$_,
                    masked => 1,
                )->to_bytes()
            }

            use Data::Dumper;
            $Data::Dumper::Useqq = 1;
            print STDERR Dumper \@frames;

warn if !eval {
use lib '/Users/felipe/code/p5-Net-Websocket/lib';
use lib '/Users/felipe/code/p5-IO-Framed/lib';
use Net::WebSocket::Parser;
use IO::Framed;

for my $f (@frames) {
    pipe my $rfh, my $wfh;
    syswrite $wfh, $f;
    close $wfh;
    my $iof = IO::Framed->new($rfh);
    my $parse = Net::WebSocket::Parser->new($iof);
    my $frame = $parse->get_next_frame();
print STDERR Dumper [$frame, $frame->get_payload()];
}
1; };

            $handle->push_write($_) for @frames;

            $connection->close(1000);
        },
        sub {
            my ($code_reason) = @_;

            is_deeply(
                \%scratch,
                {
                    messages => [
                        'two-part',
                        'three-part',
                    ],
                },
                'expected messages',
            ) or do {
                require Data::Dumper;
                local $Data::Dumper::Useqq = 1;
                diag Data::Dumper::Dumper(\%scratch);
            };

            is_deeply(
                $code_reason,
                [ Net::Libwebsockets::CLOSE_STATUS_NORMAL, q<> ],
                'close status',
            );
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
