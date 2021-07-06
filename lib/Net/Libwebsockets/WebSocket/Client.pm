package Net::Libwebsockets::WebSocket::Client;

use strict;
use warnings;

use Carp       ();
use URI::Split ();

use Net::Libwebsockets ();
use Promise::XS ();

my @_REQUIRED = qw( url event );
my %_KNOWN = map { $_ => 1 } (
    @_REQUIRED,
    'subprotocols',
    'compression',
    'headers',
    'tls',
    'ping_interval', 'ping_timeout',
);

my %DEFAULT = (
    ping_interval => 30,
    ping_timeout => 299,
);

sub _validate_subprotocol {
    my $str = shift;

    if (!length $str) {
        Carp::croak "Subprotocol must be nonempty";
    }

    my $valid_yn = ($str !~ tr<\x21-\x7e><>c);
    $valid_yn = ($str !~ tr|()<>@,;:\\"/[]?={}||);

    if (!$valid_yn) {
        Carp::croak "“$str” is not a valid WebSocket subprotocol name";
    }

    return;
}

sub connect {
    my (%opts) = @_;

    my @missing = grep { !$opts{$_} } @_REQUIRED;
    Carp::croak "Need: @missing" if @missing;

    my @extra = sort grep { !$_KNOWN{$_} } keys %opts;
    Carp::croak "Unknown: @extra" if @extra;

    # Tolerate ancient perls that lack “//=”:
    !defined($opts{$_}) && ($opts{$_} = $DEFAULT{$_}) for keys %DEFAULT;

    my ($url, $event, $tls_opt, $headers, $subprotocols) = @opts{'url', 'event', 'tls', 'headers', 'subprotocols'};

    if ($subprotocols) {
        _validate_subprotocol($_) for @$subprotocols;
    }

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

        for my $i ( 0 .. $#headers_copy ) {
            utf8::downgrade($headers_copy[$i]);

            # Weirdly, LWS adds the space between the key & value
            # but not the trailing colon. So let’s add it.
            #
            $headers_copy[$i] .= ':' if !($i % 2);
        }
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

    _new(
        $hostname, $port, $path,
        _compression_to_ext($opts{'compression'}),
        $subprotocols ? join(', ', $subprotocols) : undef,
        \@headers_copy,
        $tls_flags,
        @opts{'ping_interval', 'ping_timeout'},
        $loop_obj,
        $connected_d,
    );

    return $connected_d->promise();
}

sub _validate_deflate_max_window_bits {
    my ($argname, $val) = @_;

    if ($val < 8 || $val > 15) {
        Carp::croak "Bad $argname (must be within 8-15): $val";
    }

    return;
}

sub _deflate_to_string {
    my (%args) = @_;

    my @params;

    my $indicated_cmwb;

    for my $argname (%args) {
        my $val = $args{$argname};
        next if !defined $val;

        if ($argname eq 'local_context_mode') {
            if ($val eq 'no_takeover') {
                push @params, 'client-no-context-takeover';
            }
            elsif ($val ne 'takeover') {
                Carp::croak "Bad “$argname”: $val";
            }
        }
        elsif ($argname eq 'peer_context_mode') {
            if ($val eq 'no_takeover') {
                push @params, 'server-no-context-takeover';
            }
            elsif ($val ne 'takeover') {
                Carp::croak "Bad “$argname”: $val";
            }
        }
        elsif ($argname eq 'local_max_window_bits') {
            _validate_deflate_max_window_bits($argname, $val);

            $indicated_cmwb = 1;

            push @params, "client-max-window-bits=$val";
        }
        elsif ($argname eq 'peer_max_window_bits') {
            _validate_deflate_max_window_bits($argname, $val);

            push @params, "server-max-window-bits=$val";
        }
        else {
            Carp::croak "Bad deflate arg: $argname";
        }
    }

    # Always announce support for this:
    push @params, 'client-max-window-bits' if !$indicated_cmwb;

    return join( '; ', 'permessage-deflate', @params );
}

sub _croak_bad_compression {
    my $name = shift;

    Carp::croak("Unknown compression name: $name");
}

sub _compression_to_ext {
    my ($comp_in) = @_;

    my @exts;

    if (defined $comp_in) {
        if (my $reftype = ref $comp_in) {
            if ('ARRAY' ne $reftype) {
                Carp::croak("`compression` must be a string or arrayref, not $comp_in");
            }

            for (my $a = 0; $a < @$comp_in; $a++) {
                my $extname = $comp_in->[$a] or Carp::croak('Missing `compression` item!');

                if ($extname eq 'deflate') {
                    my $next = $comp_in->[1 + $a];
                    if ($next && 'HASH' eq ref $next) {
                        $a++;
                        push @exts, _deflate_to_string(%$next);
                    }
                }
                else {
                    _croak_bad_compression($extname);
                }
            }
        }
        elsif ($comp_in eq 'deflate') {
            push @exts, [ deflate => _deflate_to_string() ];
        }
        else {
            _croak_bad_compression($comp_in);
        }
    }
    elsif (Net::Libwebsockets::NLWS_LWS_HAS_PMD) {
        push @exts, [ deflate => _deflate_to_string() ];
    }
    else {
        return undef;
    }

    if (@exts && !Net::Libwebsockets::NLWS_LWS_HAS_PMD) {
        Carp::croak "This Libwebsockets lacks WebSocket compression support";
    }

    return \@exts;
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

    return $event_ns->new(@args);
}

1;
