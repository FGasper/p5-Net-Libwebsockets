package Net::Libwebsockets::Loop;

use strict;
use warnings;

sub new {
    my ($class) = @_;

    return bless {
        pid => $$,
    }, $class;
}

sub set_lws_context {
    my ($self, $ctx) = @_;

    $self->{'lws_context'} = $ctx;

    print "======= did set context: $ctx\n";

    #$self->start_timer();

    $self->_do_later( sub { $self->set_timer() } );

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
