#ifndef NLWS_PERL_LOOP_H
#define NLWS_PERL_LOOP_H

#define PERL_NO_GET_CONTEXT
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#include "ppport.h"

#include "xshelper/xshelper.h"

#include <libwebsockets.h>

typedef struct {
    tTHX aTHX;

    SV* perlobj;

    struct lws_context* lws_context;
} net_lws_abstract_loop_t;

extern const struct lws_event_loop_ops event_loop_ops_custom;

extern const lws_plugin_evlib_t evlib_custom;

#endif
