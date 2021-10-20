#!/usr/bin/env perl

use strict;
use warnings;

use Test::More;
use Test::FailWarnings;
use Test::Deep;

eval 'use Mojo::IOLoop; 1' or plan skip_all => $@;

use Net::Libwebsockets::WebSocket::Client ();

my $url = 'ws://hshcshsmhmasasdfvjds.madvhsgdjndm';

my $done_p = Net::Libwebsockets::WebSocket::Client::connect(
    url => $url,
    event => 'Mojolicious',
    on_ready => sub {
        my ($ws) = @_;
        $ws->close();
    },
)->then(
    sub { fail 'Should fail!' },
    sub {
        my $err = shift;

        cmp_deeply(
            $err,
            Isa('Net::Libwebsockets::X::ConnectionFailed'),
            'Expected failure',
        );
    },
);

Mojo::IOLoop->timer(
    5,
    sub {
        warn 'timed out';
        Mojo::IOLoop->stop();
    },
);

$done_p->finally(
    sub { Mojo::IOLoop->stop() },
);

Mojo::IOLoop->start();

done_testing;
