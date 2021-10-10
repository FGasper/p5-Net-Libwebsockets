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

    #print "======= did set context: $ctx\n";

    $self->{'_set_timer_cr'} = $self->_create_set_timer_cr();

    $self->_do_later( $self->{'_set_timer_cr'} );

    return;
}

sub _get_set_timer_cr {
    return $_[0]->{'_set_timer_cr'} || die "no timer cr set!";
}

sub set_timer {
    my ($self) = @_;

    $self->{'_set_timer_cr'}->();
}

sub on_close {
    $_[0]->_clear_timer();
}

sub DESTROY {
    my ($self) = @_;

    $self->_clear_timer();

    if ($$ == $self->{'pid'} && 'DESTRUCT' eq ${^GLOBAL_PHASE}) {
        warn "Destroying $self at global destruction; possible memory leak!\n";
    }

    return;
}

1;
