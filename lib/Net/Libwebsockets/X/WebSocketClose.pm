package Net::Libwebsockets::X::WebSocketClose;

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Net::Libwebsockets::X::WebSocketClose - WebSocket non-success close

=head1 DESCRIPTION

This class represents a WebSocket close code other than 1000 or empty.

Note that high-range close codes (e.g., 4xxx) also trigger this, so if
your application is going to be sending those, be sure to catch this error
and handle it accordingly.

=cut

#----------------------------------------------------------------------

use parent 'Net::Libwebsockets::X::Base';

#----------------------------------------------------------------------

sub _new {
    my ($class, $close, $reason) = @_;

    my $str = length($reason) ? "WebSocket closed $close ($reason)" : "WebSocket closed $close without a reason";

    my $self = $class->SUPER::_new($str, $close, $reason);

    return bless $self, $class;
}

1;
