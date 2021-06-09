package Net::Libwebsockets::WebSocket::Client;

use strict;
use warnings;

use Carp       ();
use URI::Split ();

use Net::Libwebsockets ();

sub new {
    my ($class, $url, $protocols_ar, $opts_hr) = @_;

    my ($scheme, $auth, $path, $query) = URI::Split::uri_split($url);

    if ($scheme ne 'ws' && $scheme ne 'wss') {
        Carp::croak "Bad URL scheme ($scheme); use ws or wss";
    }

    $path .= "?$query" if defined $query && length $query;

    my $port;

    $auth =~ m<\A (.+?) (?: : ([0-9]+))? \z>x or do {
        Carp::croak "Bad URL authority ($auth)";
    };

    my ($hostname, $port = ($1, $2);

    my $tls_opts = ($scheme eq 'ws') ? 0 : Net::Libwebsockets::LCCSCF_USE_SSL;

    $port ||= $tls_opts ? 443 : 80;

    if (my $more_tls = $opts_hr && $opts_hr->{'tls'}) {
        $tls_opts |= $more_tls;
    }

    return $class->_new( $hostname, $port, $path, $tls_opts);

1;
