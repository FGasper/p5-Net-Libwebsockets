package CheckTCP;

use strict;
use warnings;

use Test::More;

sub via_mojo {
    require Mojo::IOLoop::Client;
    require Mojo::IOLoop::Server;
    require Mojo::Promise;

    my $server = Mojo::IOLoop::Server->new;
    $server->listen(
        address => '127.0.0.1',
        port => 0,
    );
    $server->start();

    my $port = $server->port();
    diag __PACKAGE__ . ": Server listening on port $port";

    my $client = Mojo::IOLoop::Client->new;

    my ($res, $rej);

    my $promise = Mojo::Promise->new( sub {
        ($res, $rej) = @_;
    } );

    $client->on(connect => sub {
        $res->($_[1]);
    } );
    $client->on(error => sub {
diag explain [@_];
        $rej->($_[1]);
    } );

    $client->connect(address => '127.0.0.1', port => $port);

    my $err;
    $promise->then(
        sub { diag __PACKAGE__ . ": Connected OK" },
        sub { $err = $_[0] },
    )->wait(),

    die __PACKAGE__ . ": Connect failed: $err" if $err;

    return;
}

1;
