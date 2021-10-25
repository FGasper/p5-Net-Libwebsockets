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
    diag "Server listening on port $port";

    my $client = Mojo::IOLoop::Client->new;

    my ($res, $rej);

    my $promise = Mojo::Promise->new( sub {
        ($res, $rej) = @_;
    } );

    $client->on(connect => sub {
        $res->($_[1]);
    } );
    $client->on(error => sub {
        $rej->($_[1]);
    } );

    $client->connect(address => '127.0.0.1', port => $port);

    my $err;
    $promise->then(
        sub { diag "Connected OK" },
        sub { $err = $_[1] },
    )->wait(),

    die "Connect failed: $err" if $err;

    return;
}

1;
