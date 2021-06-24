package Net::Libwebsockets::Loop;

use strict;
use warnings;

sub new {
    my ($class, $ctx_pkg) = @_;

    return bless {
        pid => $$,
        context_package => $ctx_pkg,
    }, $class;
}

sub set_lws_context {
    my ($self, $ctx) = @_;

    $self->{'lws_context'} = $ctx;

    $self->start_timer();

    return;
}

sub DESTROY {
    my ($self) = @_;

    $self->_xs_pre_destroy($self->{'lws_context'});

warn "======= destroying $self\n";
    if ($$ == $self->{'pid'} && 'DESTRUCT' eq ${^GLOBAL_PHASE}) {
        warn "Destroying $self at global destruction; possible memory leak!\n";
    }

    return;
}

1;
