package Net::Libwebsockets::WebSocket::Client;

use strict;
use warnings;

use Carp       ();
use URI::Split ();

use Net::Libwebsockets ();
use Promise::XS ();

my @_REQUIRED = qw( url event );
my %_KNOWN = map { $_ => 1 } (@_REQUIRED, 'headers', 'tls', 'ping_interval', 'ping_timeout');

my %DEFAULT = (
    ping_interval => 30,
    ping_timeout => 299,
);

sub connect {
    my (%opts) = @_;

    my @missing = grep { !$opts{$_} } @_REQUIRED;
    Carp::croak "Need: @missing" if @missing;

    my @extra = sort grep { !$_KNOWN{$_} } keys %opts;
    Carp::croak "Unknown: @extra" if @extra;

    # Tolerate ancient perls that lack “//=”:
    !defined($opts{$_}) && ($opts{$_} = $DEFAULT{$_}) for keys %DEFAULT;

    my ($url, $event, $tls_opt, $headers) = @opts{'url', 'event', 'tls', 'headers'};

    _validate_uint($_ => $opts{$_}) for sort keys %DEFAULT;

    my @headers_copy;

    if ($headers) {
        if ('ARRAY' ne ref $headers) {
            Carp::croak "“headers” must be an arrayref, not “$headers”!";
        }

        if (@$headers % 2) {
            Carp::croak "“headers” (@$headers) must have an even number of members!";
        }

        @headers_copy = $headers ? @$headers : ();
        utf8::downgrade($_) for @headers_copy;
    }

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

    my $connected_d = Promise::XS::deferred();

    my $loop_obj = _get_loop_obj($event);

    my $wsc = _new(
        $hostname, $port, $path,
        \@headers_copy,
        $tls_flags,
        @opts{'ping_interval', 'ping_timeout'},
        $loop_obj,
        $connected_d,
    );

    return $connected_d->promise()->finally( sub { undef $wsc } );
}

sub _validate_uint {
    my ($name, $specimen) = @_;

    if ($specimen =~ tr<0-9><>c) {
        die "Bad “$name”: $specimen\n";
    }

    return;
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
