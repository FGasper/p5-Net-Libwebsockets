package Net::Libwebsockets::X::WebSocketClose;

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Net::Libwebsockets::X::WebSocketClose - Non-success WebSocket close

=head1 DESCRIPTION

This class represents a WebSocket close whose code is not a recognized
success state: 1000, or empty.

Note that high-range close codes (e.g., 4xxx) also trigger this, so if
your application is going to be sending those, be sure to catch this error
and handle it accordingly.

=cut

#----------------------------------------------------------------------

use parent 'Net::Libwebsockets::X::Base';

#----------------------------------------------------------------------

sub _new {
    my ($class, $code, $reason) = @_;

    my $str = length($reason) ? "WebSocket closed $code ($reason)" : "WebSocket closed $code without a reason";

    return $class->SUPER::_new($str, code => $code, reason => $reason);
}

1;
