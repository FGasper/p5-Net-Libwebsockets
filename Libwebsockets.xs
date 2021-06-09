#define PERL_NO_GET_CONTEXT
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#include "ppport.h"

#include <libwebsockets.h>

#define WEBSOCKET_CLASS "Net::Libwebsockets::WebSocket"

#define NET_LWS_LOCAL_PROTOCOL_NAME "lws-net-libwebsockets"

/*
#define FRAME_FLAG_TEXT         1
#define FRAME_FLAG_CONTINUATION 2
#define FRAME_FLAG_NONFINAL     4

#define FRAME_IS_TEXT(f)    (f.flags & FRAME_FLAG_TEXT)
#define FRAME_IS_BINARY(f)  (!FRAME_IS_TEXT(f))

#define FRAME_IS_CONTINUATION(f)    (f.flags & FRAME_FLAG_CONTINUATION)
#define FRAME_IS_FIRST(f)           (!FRAME_IS_CONTINUATION(f))

#define FRAME_IS_NONFINAL(f)    (f.flags & FRAME_FLAG_NONFINAL)
#define FRAME_IS_FIRST(f)       (!FRAME_IS_NONFINAL(f))

typedef struct {
    void *payload; //
    size_t len;
    char flags;
} frame_t;
*/

typedef struct {
    SV* perlobj;
} net_lws_abstract_loop_t;

typedef struct {
    tTHX aTHX;
} my_perl_context_t;

static const struct lws_extension default_extensions[] = {
        {
                "permessage-deflate",
                lws_extension_callback_pm_deflate,
                "permessage-deflate",
        },
        { NULL, NULL, NULL } // terminator
};

typedef struct {
    //SV*                 deferred;
    struct lws_context  *context;
} connect_state_t;

static int
net_lws_callback(
    struct lws *wsi,
    enum lws_callback_reasons reason,
    void *user,
    void *in,
    size_t len
) {
    my_perl_context_t* my_perl_context = user;

    pTHX = my_perl_context->aTHX;

    switch (reason) {

    case LWS_CALLBACK_PROTOCOL_INIT:
        // ?
        break;

    case LWS_CALLBACK_PROTOCOL_DESTROY:
        // ?
        break;

    case LWS_CALLBACK_CLIENT_ESTABLISHED:
        // resolve promise
        break;

    case LWS_CALLBACK_CLIENT_RECEIVE: {
        SV* msg_sv;

        if (lws_is_first_fragment(wsi)) {
            msg_sv = newSVpvn_flags(in, len, lws_frame_is_binary(wsi) ? 0 : SVf_UTF8);
        }
        else {
            //msg_sv = EXISTING_SV;   // TODO
            sv_catpvn(msg_sv, in, len);
        }

        } break;

    default:
        break;
    }

    return 0;
}

#define LWS_PLUGIN_PROTOCOL_NET_LWS \
        { \
                NET_LWS_LOCAL_PROTOCOL_NAME, \
                net_lws_callback, \
                sizeof(struct per_session_data__minimal_client_echo), \
                1024, \
                0, NULL, 0 \
        }

SV* _ptr_to_svrv(pTHX_ void* ptr, HV* stash) {
    SV* referent = newSVuv( PTR2UV(ptr) );
    SV* retval = newRV_noinc(referent);
    sv_bless(retval, stash);

    return retval;
}

static int
init_pt_custom (struct lws_context *cx, void *_loop, int tsi) {
    net_lws_abstract_loop_t* myloop_p = (net_lws_abstract_loop_t*) lws_evlib_tsi_to_evlib_pt(cx, tsi);

    myloop_p->perlobj = (SV *) _loop;

    return 0;
}

static int
custom_io_accept (struct lws *wsi) {
    net_lws_abstract_loop_t* myloop_p = (net_lws_abstract_loop_t*) lws_evlib_wsi_to_evlib_pt(wsi);

    int fd = lws_get_socket_fd(wsi);

    SV* myloop_sv = myloop_p->perlobj;

    // TODO: Call $myloop_sv->add_fd(fd); return 1 on error.
    // That should set to read.
}

static void
custom_io (struct lws *wsi, unsigned int flags) {
    net_lws_abstract_loop_t* myloop_p = (net_lws_abstract_loop_t*) lws_evlib_wsi_to_evlib_pt(wsi);

    int fd = lws_get_socket_fd(wsi);

    SV* myloop_sv = myloop_p->perlobj;

    int edits = 0;

    if (flags & LWS_EV_WRITE) edits |= POLLOUT;
    if (flags & LWS_EV_READ) edits |= POLLIN;

    if (flags & LWS_EV_START) {
        // TODO: Call $myloop_sv->add_to_fd(fd, edits);
    }
    else {
        // TODO: Call $myloop_sv->remove_from_fd(fd, edits);
    }
}

static int
custom_io_close (struct lws *wsi) {
    net_lws_abstract_loop_t* myloop_p = (net_lws_abstract_loop_t*) lws_evlib_wsi_to_evlib_pt(wsi);

    int fd = lws_get_socket_fd(wsi);

    SV* myloop_sv = myloop_p->perlobj;

    // TODO: Call $myloop_sv->remove_from_fd(fd); return 1 on error.
}


/* ---------------------------------------------------------------------- */

MODULE = Net::Libwebsockets     PACKAGE = Net::Libwebsockets

BOOT:
    newCONSTSUB(gv_stashpv("Net::Libwebsockets", FALSE), "LCCSCF_USE_SSL", newSVuv(LCCSCF_USE_SSL));
    newCONSTSUB(gv_stashpv("Net::Libwebsockets", FALSE), "LCCSCF_ALLOW_SELFSIGNED", newSVuv(LCCSCF_ALLOW_SELFSIGNED));
    newCONSTSUB(gv_stashpv("Net::Libwebsockets", FALSE), "LCCSCF_SKIP_SERVER_CERT_HOSTNAME_CHECK", newSVuv(LCCSCF_SKIP_SERVER_CERT_HOSTNAME_CHECK));
    newCONSTSUB(gv_stashpv("Net::Libwebsockets", FALSE), "LCCSCF_ALLOW_EXPIRED", newSVuv(LCCSCF_ALLOW_EXPIRED));
    newCONSTSUB(gv_stashpv("Net::Libwebsockets", FALSE), "LCCSCF_ALLOW_INSECURE", newSVuv(LCCSCF_ALLOW_INSECURE));

MODULE = Net::Libwebsockets     PACKAGE = Net::Libwebsockets::WebSocket::Client

PROTOTYPES: DISABLE

SV*
_new (const char* class, SV* hostname, int port, SV* path, int tls_opts)
    CODE:
        struct lws_context_creation_info info;
        struct lws_client_connect_info client;

        memset(&info, 0, sizeof info);

        info.options = (
            LWS_SERVER_OPTION_DO_SSL_GLOBAL_INIT
            | LWS_SERVER_OPTION_VALIDATE_UTF8
        );

        const struct lws_event_loop_ops event_loop_ops_custom = {
            .name                   = "net-lws-custom-loop",
            .init_pt                = init_pt_custom,
            .init_vhost_listen_wsi  = custom_io_accept,
            .sock_accept            = custom_io_accept,
            .io                     = custom_io,
            .wsi_logical_close      = custom_io_close,

            .evlib_size_pt          = sizeof(net_lws_abstract_loop_t),
        };

        my_perl_context_t* my_perl_context;
        Newx(my_perl_context, 1, my_perl_context_t); // TODO clean up
        my_perl_context->aTHX = aTHX;

        const lws_plugin_evlib_t evlib_custom = {
            .hdr = {
                "custom perl loop",
                "net_lws_plugin",
                LWS_BUILD_HASH,
                LWS_PLUGIN_API_MAGIC,
            },

            .ops = &event_loop_ops_custom,
        };

        info.event_lib_custom = &evlib_custom;

        info.port = CONTEXT_PORT_NO_LISTEN; /* we do not run any server */

        const struct lws_protocols protocols[] = {
            {
                .name = "net-libwebsockets",
                .callback = net_lws_callback,
                .per_session_data_size = 0,
                .rx_buffer_size = 0,
            },
            { NULL, NULL, 0, 0 }
        };

        info.protocols = protocols;

        struct lws_context *context = lws_create_context(&info);
        if (!context) {
            croak("lws init failed");
        }

        memset(&client, 0, sizeof client);

        const char* hostname_str = SvPVbyte_nolen(hostname);

        client.context = context;
        client.port = port;
        client.address = hostname_str;
        client.path = SvPVbyte_nolen(path);
        client.host = hostname_str;
        client.origin = hostname_str;
        client.ssl_connection = tls_opts;
        client.local_protocol_name = NET_LWS_LOCAL_PROTOCOL_NAME;

        RETVAL = &PL_sv_undef;
    OUTPUT:
        RETVAL

##    return _ptr_to_svrv(aTHX_ connstate_p, gv_stashpv(WEBSOCKET_CLASS, 
##
##
##    if (!lws_client_connect_via_info(&client)) {
##        lws_context_destroy(context);
##        croak("lws connect failed");
##    }
##
##}
