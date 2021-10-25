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

    my $failed;

    $client->on(connect => sub {
        diag __PACKAGE__ . ": Connected OK";
        $res->();
    } );
    $client->on(error => sub {
        $failed = 1;
        diag __PACKAGE__ . ": Connect failed: $_[1]";
        $res->();
    } );

    $client->connect(
        address => '127.0.0.1',
        port => $port,
    );

    $promise->wait();

    die 'Failed connect' if $failed;

    return;
}

1;
