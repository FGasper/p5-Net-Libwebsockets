#ifndef NLWS_CONTEXT_H
#define NLWS_CONTEXT_H

#include <libwebsockets.h>

#include "nlws_courier.h"

typedef enum {
    NET_LWS_MESSAGE_TYPE_TEXT,
    NET_LWS_MESSAGE_TYPE_BINARY,
} message_type_t;

typedef struct {
    tTHX aTHX;
    pid_t pid;

    SV* connect_d;

    SV* headers_ar;

    net_lws_abstract_loop_t* abstract_loop;

    courier_t* courier;
    SV* courier_sv;

    lws_retry_bo_t lws_retry;

    char* message_content;
    STRLEN content_length;
    message_type_t message_type;
} my_perl_context_t;

#endif
