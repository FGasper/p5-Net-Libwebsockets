#!/usr/bin/env perl

use strict;
use warnings;

use Test::More;
use Test::FailWarnings;
use Test::Deep;

eval 'use AnyEvent; 1' or plan skip_all => $@;

use Net::Libwebsockets::WebSocket::Client ();

my $url = 'ws://hshcshsmhmasasdfvjds.madvhsgdjndm';

my $cv = AnyEvent->condvar();

Net::Libwebsockets::WebSocket::Client::connect(
    url => $url,
    event => 'AnyEvent',
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
)->finally($cv);

my $timer = AnyEvent->timer(
    after => 5,
    cb => sub { $cv->croak('timed out') },
);

$cv->recv();

done_testing;
