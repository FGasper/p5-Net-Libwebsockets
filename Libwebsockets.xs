#define PERL_NO_GET_CONTEXT
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#include "ppport.h"

#include <libwebsockets.h>

#include <poll.h>

#include <arpa/inet.h>

#define WEBSOCKET_CLASS "Net::Libwebsockets::WebSocket::Client"
#define COURIER_CLASS "Net::Libwebsockets::WebSocket::Courier"
#define PAUSE_CLASS "Net::Libwebsockets::WebSocket::Pause"

#define NET_LWS_LOCAL_PROTOCOL_NAME "lws-net-libwebsockets"

#define DEBUG 1

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
*/

#define RING_DEPTH 1024

typedef struct {
    U8 *pre_plus_payload;
    size_t len;
    enum lws_write_protocol flags;
} frame_t;

typedef struct {
    SV* courier_sv;
} pause_t;

typedef enum {
    NET_LWS_MESSAGE_TYPE_TEXT,
    NET_LWS_MESSAGE_TYPE_BINARY,
} message_type_t;

typedef struct {
    tTHX aTHX;

    SV* perlobj;

    struct lws_context* lws_context;
} net_lws_abstract_loop_t;

typedef struct {
    struct lws *wsi;
    struct lws_context* lws_context;

    unsigned on_text_count;
    SV** on_text;

    unsigned on_binary_count;
    SV** on_binary;

    SV* done_d;

    struct lws_ring *ring;
    unsigned consume_pending_count;

    unsigned pauses;

    bool            close_yn;
    uint16_t        close_status;
    unsigned char   close_reason[123];
    STRLEN          close_reason_length;
} courier_t;

#define MAX_CLOSE_REASON_LENGTH (sizeof(courier->close_status))

typedef struct {
    tTHX aTHX;
    SV* connect_d;

    struct lws_context* lws_context;

    courier_t* courier;

    char* message_content;
    STRLEN content_length;
    message_type_t message_type;
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
    my_perl_context_t* perl_context;
    net_lws_abstract_loop_t* abstract_loop;
    struct lws_context *lws_context;
} connect_state_t;

SV* _ptr_to_svrv(pTHX_ void* ptr, HV* stash) {
    SV* referent = newSVuv( PTR2UV(ptr) );
    SV* retval = newRV_noinc(referent);
    sv_bless(retval, stash);

    return retval;
}

void* svrv_to_ptr(pTHX_ SV* svrv) {
    return (void *) (intptr_t) SvUV( SvRV(svrv) );
}

static void _call_sv_trap(pTHX_ SV* cbref, SV** mortal_args, unsigned argslen) {
    dSP;

    ENTER;
    SAVETMPS;

    PUSHMARK(SP);
    EXTEND(SP, argslen);

    for (unsigned i=0; i<argslen; i++) {
        PUSHs(mortal_args[i]);
    }

    PUTBACK;

    call_sv(cbref, G_VOID|G_DISCARD|G_EVAL);

    SV* err = ERRSV;

    if (err && SvTRUE(err)) {
        warn("Callback error: %" SVf, err);
    }

    FREETMPS;
    LEAVE;
}

void _call_object_method (pTHX_ SV* object, const char* methname, unsigned argscount, SV** mortal_args) {
    dSP;

    ENTER;
    SAVETMPS;

    PUSHMARK(SP);

    EXTEND(SP, 1 + argscount);

    mPUSHs( newSVsv(object) );

    unsigned i=0;
    for (; i<argscount; i++) PUSHs( newSVsv(mortal_args[i]) );

    PUTBACK;

    call_method( methname, G_DISCARD | G_VOID );

    FREETMPS;
    LEAVE;
}

SV* _call_object_method_scalar (pTHX_ SV* object, const char* methname, unsigned argscount, SV** mortal_args) {
    dSP;

    ENTER;
    SAVETMPS;

    PUSHMARK(SP);

    EXTEND(SP, 1 + argscount);

    mPUSHs( newSVsv(object) );

    unsigned i=0;
    for (; i<argscount; i++) PUSHs( newSVsv(mortal_args[i]) );

    PUTBACK;

    int count = call_method( methname, G_SCALAR );

    SV* ret;

    if (count > 0) {
        ret = POPs;
        SvREFCNT_inc(ret);
    }
    else {
        ret = &PL_sv_undef;
    }

    FREETMPS;
    LEAVE;

    return ret;
}

void _on_ws_close (pTHX_ my_perl_context_t* my_perl_context, uint16_t code, size_t reasonlen, const char* reason) {
    SV* done_d = my_perl_context->courier->done_d;

    SV* args[] = {
        sv_2mortal( newSVuv(code) ),
        sv_2mortal( newSVpvn(reason, reasonlen) ),
    };

    _call_object_method( aTHX_ done_d, "resolve", 2, args );
}

void _on_ws_error (pTHX_ my_perl_context_t* my_perl_context, size_t reasonlen, const char* reason) {

    SV* deferred_sv;

    if (my_perl_context->courier) {
        deferred_sv = my_perl_context->courier->done_d;
    }
    else {
        deferred_sv = my_perl_context->connect_d;
    }

    SV* args[] = {
        sv_2mortal( newSVpvn(reason, reasonlen) ),
    };

    _call_object_method( aTHX_ deferred_sv, "reject", 1, args );
}

SV* _new_deferred_sv(pTHX) {
    dSP;

    ENTER;
    SAVETMPS;

    PUSHMARK(SP);

    int count = call_pv("Promise::XS::deferred", G_SCALAR);

    if (count != 1) croak("deferred() returned %d things?!?", count);

    SPAGAIN;

    SV* deferred_sv = POPs;
    SvREFCNT_inc(deferred_sv);

    FREETMPS;
    LEAVE;

    assert(SvREFCNT(deferred_sv) == 1);

    return deferred_sv;
}

static void
_destroy_frame (void *_frame) {
    frame_t *frame_p = _frame;

    Safefree(frame_p->pre_plus_payload);
}

courier_t* _new_courier(pTHX_ struct lws *wsi, struct lws_context *context) {
    courier_t* courier;
    Newx(courier, 1, courier_t);

    courier->wsi = wsi;
    courier->lws_context = context;

    courier->on_text_count = 0;
    courier->on_text = NULL;
    courier->on_binary_count = 0;
    courier->on_binary = NULL;
    courier->close_yn = false;

    courier->ring = lws_ring_create(sizeof(frame_t), RING_DEPTH, _destroy_frame);
    courier->consume_pending_count = 0;

    courier->pauses = 0;

    if (!courier->ring) {
        Safefree(courier);
        croak("lws_ring_create() failed!");
    }

    courier->done_d = _new_deferred_sv(aTHX);

    return courier;
/*
    return sv_2mortal(
        _ptr_to_svrv(aTHX_ courier, gv_stashpv(COURIER_CLASS, FALSE))
    );
*/
}

void _on_ws_message(pTHX_ my_perl_context_t* my_perl_context, SV* msgsv) {
    courier_t* courier = my_perl_context->courier;

    sv_2mortal(msgsv);

    // Because of the assert() below this initialization isn’t needed,
    // but some compilers aren’t smart enough to realize that.
    unsigned cbcount = 0;

    SV** cbs;

    switch (my_perl_context->message_type) {
        case NET_LWS_MESSAGE_TYPE_TEXT:
            cbcount = courier->on_text_count;
            cbs = courier->on_text;
            break;

        case NET_LWS_MESSAGE_TYPE_BINARY:
            cbcount = courier->on_binary_count;
            cbs = courier->on_binary;
            break;

        default:
            assert(0);
    }

    SV* args[] = { NULL };

    for (unsigned c=0; c<cbcount; c++) {
        args[0] = (c == cbcount-1) ? msgsv : sv_mortalcopy(msgsv);
        _call_sv_trap(aTHX_ cbs[c], args, 1);
    }
}

static int
net_lws_callback(
    struct lws *wsi,
    enum lws_callback_reasons reason,
    void *user,
    void *in,
    size_t len
) {
    my_perl_context_t* my_perl_context = user;

    // Not all callbacks pass user??
    pTHX = my_perl_context ? my_perl_context->aTHX : NULL;

    switch (reason) {

    case LWS_CALLBACK_PROTOCOL_INIT:
fprintf(stderr, "protocol init\n");
        // ?
        break;

    case LWS_CALLBACK_PROTOCOL_DESTROY:
fprintf(stderr, "protocol destroy\n");
        // ?
        break;

    case LWS_CALLBACK_CLIENT_ESTABLISHED: {
        courier_t* courier = _new_courier(aTHX, wsi, my_perl_context->lws_context);

        my_perl_context->courier = courier;

        SV* courier_sv = sv_2mortal(
            _ptr_to_svrv(aTHX_ courier, gv_stashpv(COURIER_CLASS, FALSE))
        );

        SV* args[] = { courier_sv };

        _call_object_method( aTHX_ my_perl_context->connect_d, "resolve", 1, args );
        } break;

    case LWS_CALLBACK_WS_PEER_INITIATED_CLOSE:
fprintf(stderr, "peer started close\n");
        _on_ws_close(aTHX_
            my_perl_context,
            ntohs( *(uint16_t *) in ),
            len - sizeof(uint16_t),
            sizeof(uint16_t) + in
        );
        break;

    case LWS_CALLBACK_CLIENT_WRITEABLE: {
        courier_t* courier = my_perl_context->courier;

        // Idea taken from LWS’s lws-minimal-client-echo demo:
        // permessage-deflate requires that we forgo consuming the
        // item from the ring buffer until the next writeable.
        //
        if (courier->consume_pending_count) {
            courier->consume_pending_count -= lws_ring_consume(courier->ring, NULL, NULL, courier->consume_pending_count);
        }

        const frame_t *frame_p = lws_ring_get_element(courier->ring, NULL);

        if (frame_p) {
            int wrote = lws_write(
                wsi,
                LWS_PRE + frame_p->pre_plus_payload,
                frame_p->len,
                frame_p->flags
            );

            if (wrote < (int)frame_p->len) {
                warn("ERROR %d while writing to WebSocket!", wrote);
                return -1;
            }

            courier->consume_pending_count++;
            lws_callback_on_writable(wsi);
        }

        // Don’t close until we’ve flushed the buffer:
        else if (courier->close_yn) {
            if (courier->close_status != LWS_CLOSE_STATUS_NOSTATUS) {
                lws_close_reason(
                    wsi,
                    courier->close_status,
                    courier->close_reason,
                    courier->close_reason_length
                );
            }

            return -1;
        }

        } break;

    case LWS_CALLBACK_CLIENT_CONNECTION_ERROR:
        _on_ws_error(aTHX_ my_perl_context, len, in);
        break;

    case LWS_CALLBACK_CLIENT_RECEIVE: {

        if (lws_is_first_fragment(wsi)) {

            // In this (generally prevalent) case we can create our SV
            // directly from the incoming frame.
            if (lws_is_final_fragment(wsi)) {
                _on_ws_message(aTHX_ my_perl_context, newSVpvn_flags(in, len, lws_frame_is_binary(wsi) ? 0 : SVf_UTF8));
                break;
            }

            my_perl_context->message_type = lws_frame_is_binary(wsi) ? NET_LWS_MESSAGE_TYPE_BINARY : NET_LWS_MESSAGE_TYPE_TEXT;

            my_perl_context->content_length = len;
        }
        else {
            my_perl_context->content_length += len;
        }

        Renew(my_perl_context->message_content, my_perl_context->content_length, char);
        Copy(
            in,
            my_perl_context->message_content + my_perl_context->content_length - len,
            len,
            char
        );

        if (lws_is_final_fragment(wsi)) {
            SV* msgsv = newSVpvn_flags(
                my_perl_context->message_content,
                my_perl_context->content_length,
                my_perl_context->message_type == NET_LWS_MESSAGE_TYPE_TEXT ? SVf_UTF8 : 0
            );

            _on_ws_message(aTHX_ my_perl_context, msgsv );
        }

        } break;

    case LWS_CALLBACK_CLIENT_CLOSED: {

        courier_t* courier = my_perl_context->courier;

        if (courier->close_yn) {
            _call_object_method( aTHX_
                courier->done_d,
                "resolve",
                0,
                NULL
            );
        }
        else {
            warn("LWS_CALLBACK_CLIENT_CLOSED but we didn’t close … is this OK?");
        }

        } break;

    default:
fprintf(stderr, "other callback\n");
        break;
    }

    //return lws_callback_http_dummy(wsi, reason, user, in, len);
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

static int
init_pt_custom (struct lws_context *cx, void *_loop, int tsi) {
    net_lws_abstract_loop_t* myloop_p = lws_evlib_tsi_to_evlib_pt(cx, tsi);

    net_lws_abstract_loop_t *sourceloop_p = (net_lws_abstract_loop_t *) _loop;

    memcpy(myloop_p, sourceloop_p, sizeof(net_lws_abstract_loop_t));

    return 0;
}

static int
custom_io_accept (struct lws *wsi) {
    net_lws_abstract_loop_t* myloop_p = (net_lws_abstract_loop_t*) lws_evlib_wsi_to_evlib_pt(wsi);

    pTHX = myloop_p->aTHX;

    int fd = lws_get_socket_fd(wsi);

    SV* myloop_sv = myloop_p->perlobj;

    SV* args[] = { sv_2mortal(newSViv(fd)) };

    _call_object_method(aTHX_ myloop_sv, "add_fd", 1, args);

    return 0;
}

static void
custom_io (struct lws *wsi, unsigned int flags) {
    net_lws_abstract_loop_t* myloop_p = (net_lws_abstract_loop_t*) lws_evlib_wsi_to_evlib_pt(wsi);

    pTHX = myloop_p->aTHX;

    int fd = lws_get_socket_fd(wsi);

    SV* myloop_sv = myloop_p->perlobj;

    char *method_name;

    if (flags & LWS_EV_START) {
        method_name = "add_to_fd";
    }
    else {
        method_name = "remove_from_fd";
    }

    SV* args[] = {
        sv_2mortal(newSViv(fd)),
        sv_2mortal(newSVuv(flags)),
    };

    _call_object_method(aTHX_ myloop_sv, method_name, 2, args );
}

static int
custom_io_close (struct lws *wsi) {
fprintf(stderr, "custom_io_close\n");
    net_lws_abstract_loop_t* myloop_p = (net_lws_abstract_loop_t*) lws_evlib_wsi_to_evlib_pt(wsi);

    pTHX = myloop_p->aTHX;

    int fd = lws_get_socket_fd(wsi);
fprintf(stderr, "closing fd %d\n", fd);

    SV* myloop_sv = myloop_p->perlobj;

    SV* args[] = { sv_2mortal(newSViv(fd)) };

    _call_object_method(aTHX_ myloop_sv, "remove_fd", 1, args);

    return 0;
}

const struct lws_event_loop_ops event_loop_ops_custom = {
    .name                   = "net-lws-custom-loop",

    .init_pt                = init_pt_custom,
    .init_vhost_listen_wsi  = custom_io_accept,
    .sock_accept            = custom_io_accept,
    .io                     = custom_io,
    .wsi_logical_close      = custom_io_close,

    .evlib_size_pt          = sizeof(net_lws_abstract_loop_t),
};

const lws_plugin_evlib_t evlib_custom = {
    .hdr = {
        "custom perl loop",
        "net_lws_plugin",
        LWS_BUILD_HASH,
        LWS_PLUGIN_API_MAGIC,
    },

    .ops = &event_loop_ops_custom,
};

void _courier_sv_send( pTHX_ courier_t* courier, U8* buf, STRLEN len, enum lws_write_protocol protocol ) {

    frame_t frame = {
        .len = len,
        .flags = lws_write_ws_flags(protocol, 1, 1),
    };

    Newx(frame.pre_plus_payload, len + LWS_PRE, U8);

    Copy(buf, LWS_PRE + frame.pre_plus_payload, len, U8);

    if (!lws_ring_insert( courier->ring, &frame, 1 )) {
        _destroy_frame(&frame);

        size_t count = lws_ring_get_count_free_elements(courier->ring);

        croak("Failed to add message to ring buffer! (%zu ring nodes free)", count);
    }

    lws_callback_on_writable(courier->wsi);
}

/* ---------------------------------------------------------------------- */

MODULE = Net::Libwebsockets     PACKAGE = Net::Libwebsockets

BOOT:
    newCONSTSUB(gv_stashpv("Net::Libwebsockets", FALSE), "LCCSCF_USE_SSL", newSVuv(LCCSCF_USE_SSL));
    newCONSTSUB(gv_stashpv("Net::Libwebsockets", FALSE), "LCCSCF_ALLOW_SELFSIGNED", newSVuv(LCCSCF_ALLOW_SELFSIGNED));
    newCONSTSUB(gv_stashpv("Net::Libwebsockets", FALSE), "LCCSCF_SKIP_SERVER_CERT_HOSTNAME_CHECK", newSVuv(LCCSCF_SKIP_SERVER_CERT_HOSTNAME_CHECK));
    newCONSTSUB(gv_stashpv("Net::Libwebsockets", FALSE), "LCCSCF_ALLOW_EXPIRED", newSVuv(LCCSCF_ALLOW_EXPIRED));
    newCONSTSUB(gv_stashpv("Net::Libwebsockets", FALSE), "LCCSCF_ALLOW_INSECURE", newSVuv(LCCSCF_ALLOW_INSECURE));
    newCONSTSUB(gv_stashpv("Net::Libwebsockets", FALSE), "LWS_EV_READ", newSVuv(LWS_EV_READ));
    newCONSTSUB(gv_stashpv("Net::Libwebsockets", FALSE), "LWS_EV_WRITE", newSVuv(LWS_EV_WRITE));

MODULE = Net::Libwebsockets     PACKAGE = Net::Libwebsockets::WebSocket::Client

PROTOTYPES: DISABLE

void
lws_service_fd_read( SV* lws_context_sv, int fd )
    CODE:
        intptr_t lws_context_int = (intptr_t) SvUV(lws_context_sv);

        struct lws_context *context = (void *) lws_context_int;
        struct lws_pollfd pollfd = {
            .fd = fd,
            .events = POLLIN,
            .revents = POLLIN,
        };

        lws_service_fd(context, &pollfd);

void
lws_service_fd_write( SV* lws_context_sv, int fd )
    CODE:
        intptr_t lws_context_int = (intptr_t) SvUV(lws_context_sv);

        struct lws_context *context = (void *) lws_context_int;
        struct lws_pollfd pollfd = {
            .fd = fd,
            .events = POLLOUT,
            .revents = POLLOUT,
        };

        lws_service_fd(context, &pollfd);

SV*
_new (SV* hostname, int port, SV* path, int tls_opts, SV* loop_obj, SV* connected_d)
    CODE:
        lws_set_log_level( LLL_USER | LLL_ERR | LLL_WARN | LLL_NOTICE | LLL_DEBUG | LLL_PARSER | LLL_HEADER | LLL_INFO, NULL );

        struct lws_context_creation_info info;
        struct lws_client_connect_info client;

        Zero(&info, 1, struct lws_context_creation_info);

        info.options = (
            LWS_SERVER_OPTION_DO_SSL_GLOBAL_INIT
            | LWS_SERVER_OPTION_VALIDATE_UTF8
        );



        my_perl_context_t* my_perl_context;
        Newxz(my_perl_context, 1, my_perl_context_t); // TODO clean up
        my_perl_context->aTHX = aTHX;

        my_perl_context->connect_d = connected_d;
        my_perl_context->courier = NULL;
        SvREFCNT_inc(connected_d);



        info.event_lib_custom = &evlib_custom;

        net_lws_abstract_loop_t* abstract_loop;
        Newx(abstract_loop, 1, net_lws_abstract_loop_t);
        abstract_loop->aTHX = aTHX;
        abstract_loop->perlobj = loop_obj;
        SvREFCNT_inc(loop_obj);

        void *foreign_loops[] = { abstract_loop };
        fprintf(stderr, "abstract loop: %p\n", abstract_loop);
        info.foreign_loops = foreign_loops;

        info.port = CONTEXT_PORT_NO_LISTEN; /* we do not run any server */

        const struct lws_protocols protocols[] = {
            {
                .name = "net-libwebsockets",
                .callback = net_lws_callback,
                .per_session_data_size = sizeof(void*),
                .rx_buffer_size = 0,
            },
            { NULL, NULL, 0, 0 }
        };

        info.protocols = protocols;

        struct lws_context *context = lws_create_context(&info);
        if (!context) {
            croak("lws init failed");
        }

        fprintf(stderr, "lws context: %" UVf "\n", (UV) context);
        my_perl_context->lws_context = context;

        SV* set_ctx_args[] = { sv_2mortal( newSVuv((intptr_t) context) ) };
        _call_object_method(aTHX_ loop_obj, "set_lws_context", 1, set_ctx_args);

        memset(&client, 0, sizeof client);

        const char* hostname_str = SvPVbyte_nolen(hostname);

        client.context = context;
        client.port = port;
        client.address = hostname_str;
        client.path = SvPVbyte_nolen(path);
        client.host = hostname_str;
        client.origin = hostname_str;
        client.ssl_connection = tls_opts;
        //client.local_protocol_name = NET_LWS_LOCAL_PROTOCOL_NAME;
        client.local_protocol_name = protocols[0].name;

        // The callback’s `user`:
        client.userdata = my_perl_context;

        if (!lws_client_connect_via_info(&client)) {
            lws_context_destroy(context);
            croak("lws connect failed");
        }

        connect_state_t* connect_state;
        Newx(connect_state, 1, connect_state_t);

        fprintf(stderr, "my_perl_context: %p\n", my_perl_context);

        connect_state->perl_context = my_perl_context;
        connect_state->lws_context = context;
        connect_state->abstract_loop = abstract_loop;

        RETVAL = _ptr_to_svrv(aTHX_ connect_state, gv_stashpv(WEBSOCKET_CLASS, FALSE));

    OUTPUT:
        RETVAL

# ----------------------------------------------------------------------

MODULE = Net::Libwebsockets     PACKAGE = Net::Libwebsockets::WebSocket::Pause

PROTOTYPES: DISABLE

void
DESTROY (SV* self_sv)
    CODE:
        pause_t *my_pause = svrv_to_ptr(aTHX_ self_sv);

        courier_t *courier = svrv_to_ptr(aTHX_ my_pause->courier_sv);

        courier->pauses--;

        if (!courier->pauses) {
            lws_rx_flow_control(courier->wsi, 1);
        }

        SvREFCNT_dec(my_pause->courier_sv);

        Safefree(my_pause);

# ----------------------------------------------------------------------

MODULE = Net::Libwebsockets     PACKAGE = Net::Libwebsockets::WebSocket::Courier

PROTOTYPES: DISABLE

void
on_text (SV* self_sv, SV* cbref)
    CODE:
        courier_t* courier = svrv_to_ptr(aTHX_ self_sv);

        SvREFCNT_inc(cbref);

        courier->on_text_count++;
        Renew(courier->on_text, courier->on_text_count, SV*);
        courier->on_text[courier->on_text_count - 1] = cbref;

void
on_binary (SV* self_sv, SV* cbref)
    CODE:
        courier_t* courier = svrv_to_ptr(aTHX_ self_sv);

        SvREFCNT_inc(cbref);

        courier->on_binary_count++;
        Renew(courier->on_binary, courier->on_binary_count, SV*);
        courier->on_binary[courier->on_binary_count - 1] = cbref;

SV*
done_p (SV* self_sv)
    CODE:
        courier_t* courier = svrv_to_ptr(aTHX_ self_sv);

        RETVAL = _call_object_method_scalar(aTHX_ courier->done_d, "promise", 0, NULL);

    OUTPUT:
        RETVAL

void
send_text (SV* self_sv, SV* payload_sv)
    CODE:
        courier_t* courier = svrv_to_ptr(aTHX_ self_sv);

        STRLEN len;
        U8* buf = (U8*) SvPVutf8(payload_sv, len);

        _courier_sv_send(aTHX_ courier, buf, len, LWS_WRITE_TEXT);

void
send_binary (SV* self_sv, SV* payload_sv)
    CODE:
        courier_t* courier = svrv_to_ptr(aTHX_ self_sv);

        STRLEN len;
        U8* buf = (U8*) SvPVbyte(payload_sv, len);

        _courier_sv_send(aTHX_ courier, buf, len, LWS_WRITE_BINARY);

SV*
pause (SV* self_sv)
    CODE:
        if (GIMME_V == G_VOID) croak("Don’t call pause() in void context!");

        courier_t* courier = svrv_to_ptr(aTHX_ self_sv);

        pause_t* my_pause;
        Newx(my_pause, 1, pause_t);

        my_pause->courier_sv = self_sv;
        SvREFCNT_inc(self_sv);

        if (!courier->pauses) {
            lws_rx_flow_control(courier->wsi, 0);
        }

        courier->pauses++;

        RETVAL = _ptr_to_svrv(aTHX_ my_pause, gv_stashpv(PAUSE_CLASS, FALSE));

    OUTPUT:
        RETVAL

void
close (SV* self_sv, U16 code=LWS_CLOSE_STATUS_NOSTATUS, SV* reason_sv=NULL)
    CODE:
        courier_t* courier = svrv_to_ptr(aTHX_ self_sv);

        if (reason_sv && SvOK(reason_sv)) {
            U8* reason = (U8*) SvPVutf8(reason_sv, courier->close_reason_length);

            if (courier->close_reason_length > MAX_CLOSE_REASON_LENGTH) {
                warn("Truncating %zu-byte close reason (%.*s) to %zu bytes …", courier->close_reason_length, (int) courier->close_reason_length, reason, MAX_CLOSE_REASON_LENGTH);
                courier->close_reason_length = MAX_CLOSE_REASON_LENGTH;
            }

            memcpy(courier->close_reason, reason, courier->close_reason_length);
        }

        courier->close_yn = true;
        courier->close_status = code;

        // Force a writable callback, which will trigger our close.
        lws_callback_on_writable(courier->wsi);

void
DESTROY (SV* self_sv)
    CODE:
        fprintf(stderr, "===== DESTROY courier\n");

        courier_t* courier = svrv_to_ptr(aTHX_ self_sv);

        if (courier->on_text) {
            for (unsigned i=0; i<courier->on_text_count; i++) {
                SvREFCNT_dec(courier->on_text[i]);
            }

            Safefree(courier->on_text);
        }

        if (courier->on_binary) {
            for (unsigned i=0; i<courier->on_binary_count; i++) {
                SvREFCNT_dec(courier->on_binary[i]);
            }

            Safefree(courier->on_binary);
        }

        SvREFCNT_dec(courier->done_d);

        lws_ring_destroy(courier->ring);

        Safefree(courier);
