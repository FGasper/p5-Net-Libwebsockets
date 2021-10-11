#ifndef NLWS_LOGGER_H
#define NLWS_LOGGER_H

#define PERL_NO_GET_CONTEXT
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#include "xshelper/xshelper.h"

#include <libwebsockets.h>

#define LOGGER_CLASS "Net::Libwebsockets::Logger"

typedef struct {
    pTHX;

    pid_t pid;

    SV* callback;
} nlws_logger_opaque_t;

//lws_log_emit_cx_t nlws_logger_emit;
void nlws_logger_emit(struct lws_log_cx *cx, int level, const char *line, size_t len);

int nlws_get_global_lwsl_level();

#endif
