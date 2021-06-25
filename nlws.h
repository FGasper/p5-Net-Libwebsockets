#ifndef NLWS_H
#define NLWS_H

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

#define UNUSED(x) (void)(x)

#define RING_DEPTH 1024

#endif
