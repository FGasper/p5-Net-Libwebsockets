package Net::Libwebsockets::X::WebSocketClose;

use strict;
use warnings;

use parent 'Net::Libwebsockets::X::Base';

sub _new {
    my ($class, $close, $reason) = @_;

    my $str = length($reason) ? "WebSocket closed $close ($reason)" : "WebSocket closed $close without reason";

    my $self = $class->SUPER::_new($str, $close, $reason);

    return bless $self, $class;
}

1;
