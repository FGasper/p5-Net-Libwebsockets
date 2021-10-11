void _destroy_my_perl_context (pTHX_ my_perl_context_t* my_perl_context) {
    if (my_perl_context->connect_d) {
        SvREFCNT_dec(my_perl_context->connect_d);
    }

    if (my_perl_context->message_content) {
        Safefree(my_perl_context->message_content);
    }

    SvREFCNT_dec(my_perl_context->abstract_loop->perlobj);
    Safefree(my_perl_context->abstract_loop);

    Safefree(my_perl_context);
}

void my_lws_context_destroy (pTHX_ struct lws_context *context) {
    my_perl_context_t* my_perl_context = lws_context_user(context);

    _destroy_my_perl_context( aTHX_ my_perl_context);

    lws_context_destroy(context);
}
