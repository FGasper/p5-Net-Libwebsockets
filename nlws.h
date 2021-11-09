#ifndef NLWS_H
#define NLWS_H

#include "EXTERN.h"
#include "perl.h"

#define NLWS_DEBUG 0

// ----------------------------------------------------------------------
// These simplify the hunt for reference-counting errors:

#define NLWS_SvREFCNT_inc(sv) \
    if (NLWS_DEBUG) fprintf(stderr, "%s: SvREFCNT_inc(%p, from %d refs)\n", __func__, sv, SvREFCNT(sv)); \
    SvREFCNT_inc(sv);

#define NLWS_SvREFCNT_dec(sv) STMT_START { \
    if (NLWS_DEBUG) fprintf(stderr, "%s: SvREFCNT_dec(%p, from %d refs)\n", __func__, sv, SvREFCNT(sv)); \
    SvREFCNT_dec(sv); \
    if (NLWS_DEBUG) fprintf(stderr, "after %s SvREFCNT_dec(%p)\n", __func__, sv); \
} STMT_END

// ----------------------------------------------------------------------

#if NLWS_DEBUG
#define NLWS_LOG_FUNC fprintf(stderr, "%s\n", __func__)
#else
#define NLWS_LOG_FUNC
#endif

#define MAX_CLOSE_REASON_LENGTH 123

#define DEFAULT_POLL_TIMEOUT (5 * 60 * 1000)

#define WEBSOCKET_CLASS "Net::Libwebsockets::WebSocket::Client"
#define COURIER_CLASS "Net::Libwebsockets::WebSocket::Courier"
#define PAUSE_CLASS "Net::Libwebsockets::WebSocket::Pause"

#define NET_LWS_LOCAL_PROTOCOL_NAME "perl-net-libwebsockets"

#ifdef PL_phase
#   define IS_GLOBAL_DESTRUCTION (PL_phase == PERL_PHASE_DESTRUCT)
#else
#   define IS_GLOBAL_DESTRUCTION PL_dirty
#endif

#ifdef MULTIPLICITY
#   define PERL_CONTEXT_IN_STRUCT .aTHX = aTHX,
#   define PERL_CONTEXT_FROM_STRUCT(name) pTHX = name->aTHX
#else
#   define PERL_CONTEXT_IN_STRUCT
#   define PERL_CONTEXT_FROM_STRUCT(name) (void)(name)
#endif

#define UNUSED(x) (void)(x)

#define RING_DEPTH 1024

#endif
