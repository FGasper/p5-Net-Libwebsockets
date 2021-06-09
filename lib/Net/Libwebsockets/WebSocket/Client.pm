package Net::Libwebsockets::WebSocket::Client;

use strict;
use warnings;

use Carp       ();
use URI::Split ();

use Net::Libwebsockets ();
use Promise::XS ();

my @_REQUIRED = qw( url event );

sub connect {
    my (%opts) = @_;

    my @missing = grep { !$opts{$_} } @_REQUIRED;
    die "Need: @missing" if @missing;

    my ($url, $event, $tls_opt) = @opts{'url', 'event', 'tls'};

    my ($scheme, $auth, $path, $query) = URI::Split::uri_split($url);

    if ($scheme ne 'ws' && $scheme ne 'wss') {
        Carp::croak "Bad URL scheme ($scheme); use ws or wss";
    }

    $path .= "?$query" if defined $query && length $query;

    $auth =~ m<\A (.+?) (?: : ([0-9]+))? \z>x or do {
        Carp::croak "Bad URL authority ($auth)";
    };

    my ($hostname, $port) = ($1, $2);

    my $tls_flags = ($scheme eq 'ws') ? 0 : Net::Libwebsockets::LCCSCF_USE_SSL;

    $port ||= $tls_flags ? 443 : 80;

    $tls_flags |= $tls_opt if $tls_opt;

    my $deferred = Promise::XS::deferred();

    my $loop_obj = _get_loop_obj($event);

    my $wsc = $class->_new($hostname, $port, $path, $tls_flags, $loop_obj, $deferred);

    return $deferred->promise()->finally( sub { undef $wsc } );
}

sub _get_loop_obj {
    my ($event) = @_;

    my @args;

    if ('ARRAY' eq ref $event) {
        ($event, @args) = @$event;
    }

    require "Net/Libwebsockets/Loop/$event.pm";
    my $event_ns = "Net::Libwebsockets::Loop::$event";

    return $event_ns->new(__PACKAGE__, @args);
}

1;
