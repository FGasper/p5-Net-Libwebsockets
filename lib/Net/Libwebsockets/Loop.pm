package Net::Libwebsockets::Loop;

use strict;
use warnings;

sub new {
    my ($class, $ctx_pkg) = @_;

    return bless { context_package => $ctx_pkg }, $class;
}

sub set_lws_context {
    my ($self, $ctx) = @_;

    $self->{'lws_context'} = $ctx;

    return;
}

1;
