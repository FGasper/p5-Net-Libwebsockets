#define PERL_NO_GET_CONTEXT
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#include "ppport.h"

#include <libwebsockets.h>

#include <poll.h>
#include <unistd.h>

#include <arpa/inet.h>

#define DEBUG 1

#include "xshelper/xshelper.h"

#include "nlws.h"
#include "nlws_frame.h"
#include "nlws_courier.h"
#include "nlws_perl_loop.h"

typedef struct {
    SV* courier_sv;
} pause_t;

typedef enum {
    NET_LWS_MESSAGE_TYPE_TEXT,
    NET_LWS_MESSAGE_TYPE_BINARY,
} message_type_t;

typedef struct {
    tTHX aTHX;
    SV* connect_d;

    SV* headers_ar;

    struct lws_context* lws_context;

    net_lws_abstract_loop_t* abstract_loop;

    courier_t* courier;
    SV* courier_sv;

    lws_retry_bo_t lws_retry;

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
    struct lws_context *lws_context;
    pid_t pid;
} connect_state_t;

static inline void _finish_deferred_sv (pTHX_ SV** deferred_svp, const char* methname, SV* payload) {
warn("finishing deferred (payload=%p)\n", payload);

    if (!*deferred_svp) croak("Can’t %s(); already finished!", methname);

    SV* deferred_sv = *deferred_svp;

    // The deferred’s callbacks might execute synchronously and also
    // might depend on the referent pointer being NULL as an indicator
    // that the deferred was already finished.
    //
    *deferred_svp = NULL;

    if (payload) {
        SV* args[] = { payload, NULL };

        xsh_call_object_method_void( aTHX_ deferred_sv, methname, args );
    }
    else {
        xsh_call_object_method_void( aTHX_ deferred_sv, methname, NULL );
    }

    SvREFCNT_dec(deferred_sv);

}

void _on_ws_close (pTHX_ my_perl_context_t* my_perl_context, uint16_t code, size_t reasonlen, const char* reason) {
fprintf(stderr, "%s\n", __func__);

    AV* code_reason = av_make(
        2,
        ( (SV*[]) {
            newSVuv(code),
            newSVpvn(reason, reasonlen),
        } )
    );

    SV* arg = newRV_noinc((SV*) code_reason);

    _finish_deferred_sv( aTHX_ &my_perl_context->courier->done_d, "resolve", arg );
}

void _on_ws_error (pTHX_ my_perl_context_t* my_perl_context, size_t reasonlen, const char* reason) {

    SV** deferred_svp;

    if (my_perl_context->courier) {
warn("promise is done_d\n");
        deferred_svp = &my_perl_context->courier->done_d;
    }
    else {
warn("promise is connect_d\n");
        deferred_svp = &my_perl_context->connect_d;
    }

    _finish_deferred_sv( aTHX_ deferred_svp, "reject", newSVpvn(reason, reasonlen) );
}

void _on_ws_message(pTHX_ my_perl_context_t* my_perl_context, SV* msgsv) {
    courier_t* courier = my_perl_context->courier;

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

    SV* cbargs[] = { NULL, NULL };

    for (unsigned c=0; c<cbcount; c++) {
        cbargs[0] = (c == cbcount-1) ? msgsv : newSVsv(msgsv);
        xsh_call_sv_trap_void(aTHX_ cbs[c], cbargs, "Callback error: ");
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

    case LWS_CALLBACK_WSI_DESTROY:
fprintf(stderr, "wsi destroy\n");
        if (my_perl_context->courier_sv) {
            SvREFCNT_dec(my_perl_context->courier_sv);
        }

        net_lws_abstract_loop_t* myloop_p = (net_lws_abstract_loop_t*) lws_evlib_wsi_to_evlib_pt(wsi);

        if (myloop_p && myloop_p->perlobj) {
            SvREFCNT_dec(myloop_p->perlobj);
        }
fprintf(stderr, "wsi destroy2\n");

        break;

    case LWS_CALLBACK_CLIENT_APPEND_HANDSHAKE_HEADER: {
        unsigned char **p = (unsigned char **)in;
        unsigned char *end = (*p) + len;

        AV* headers_av = (AV*) SvRV(my_perl_context->headers_ar);

        int headers_len = 1 + av_top_index(headers_av);

        STRLEN valuelen;
        SV** key;
        SV** value;

        int failed = 0;

        for (int h=0; h<headers_len; h += 2) {
            key = av_fetch(headers_av, h, 0);
            assert(key);

            value = av_fetch(headers_av, 1 + h, 0);
            assert(value);

            const U8* valuestr = (const U8*) SvPVbyte( *value, valuelen );

            int failed = lws_add_http_header_by_name(
                wsi,
                (const U8*) SvPVbyte_nolen(*key),
                valuestr,
                valuelen,
                p, end
            );

            if (failed) break;
        }

        SvREFCNT_dec(my_perl_context->headers_ar);

        if (failed) return -1;

        } break;

    case LWS_CALLBACK_CLIENT_ESTABLISHED: {
        courier_t* courier = nlws_create_courier(aTHX, wsi, my_perl_context->lws_context);

        my_perl_context->courier = courier;

        SV* courier_sv = xsh_ptr_to_svrv(aTHX_ courier, gv_stashpv(COURIER_CLASS, FALSE));
        my_perl_context->courier_sv = courier_sv;

        _finish_deferred_sv( aTHX_ &my_perl_context->connect_d, "resolve", newSVsv(courier_sv) );

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
warn("writable: we started close\n");
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
warn("client closed cuz us (courier=%p)\n", courier->done_d);
            _finish_deferred_sv( aTHX_ &courier->done_d, "resolve", NULL );
        }
        else {
            warn("LWS_CALLBACK_CLIENT_CLOSED but we didn’t close … is this OK?");
        }

        } break;

    default:
warn("other callback (%d)\n", reason);
        break;
    }

    return 0;
}





void _courier_sv_send( pTHX_ courier_t* courier, U8* buf, STRLEN len, enum lws_write_protocol protocol ) {

    frame_t frame = {
        .len = len,
        .flags = lws_write_ws_flags(protocol, 1, 1),
    };

    Newx(frame.pre_plus_payload, len + LWS_PRE, U8);

    Copy(buf, LWS_PRE + frame.pre_plus_payload, len, U8);

    if (!lws_ring_insert( courier->ring, &frame, 1 )) {
        nlws_destroy_frame(&frame);

        size_t count = lws_ring_get_count_free_elements(courier->ring);

        croak("Failed to add message to ring buffer! (%zu ring nodes free)", count);
    }

    lws_callback_on_writable(courier->wsi);
}

static inline void _lws_service_fd (pTHX_ UV lws_context_uv, int fd, short event) {
    intptr_t lws_context_int = lws_context_uv;

    struct lws_context *context = (void *) lws_context_int;

    struct lws_pollfd pollfd = {
        .fd = fd,
        .events = event,
        .revents = event,
    };

    lws_service_fd(context, &pollfd);

    my_perl_context_t* my_perl_context = lws_context_user(context);

    if (my_perl_context && my_perl_context->abstract_loop) {
        SV* loop_sv = my_perl_context->abstract_loop->perlobj;
        xsh_call_object_method_void(aTHX_ loop_sv, "set_timer", NULL);
    }
}

/* ---------------------------------------------------------------------- */

MODULE = Net::Libwebsockets     PACKAGE = Net::Libwebsockets

PROTOTYPES: DISABLE

BOOT:
    newCONSTSUB(gv_stashpv("Net::Libwebsockets", FALSE), "LCCSCF_USE_SSL", newSVuv(LCCSCF_USE_SSL));
    newCONSTSUB(gv_stashpv("Net::Libwebsockets", FALSE), "LCCSCF_ALLOW_SELFSIGNED", newSVuv(LCCSCF_ALLOW_SELFSIGNED));
    newCONSTSUB(gv_stashpv("Net::Libwebsockets", FALSE), "LCCSCF_SKIP_SERVER_CERT_HOSTNAME_CHECK", newSVuv(LCCSCF_SKIP_SERVER_CERT_HOSTNAME_CHECK));
    newCONSTSUB(gv_stashpv("Net::Libwebsockets", FALSE), "LCCSCF_ALLOW_EXPIRED", newSVuv(LCCSCF_ALLOW_EXPIRED));
    newCONSTSUB(gv_stashpv("Net::Libwebsockets", FALSE), "LCCSCF_ALLOW_INSECURE", newSVuv(LCCSCF_ALLOW_INSECURE));
    newCONSTSUB(gv_stashpv("Net::Libwebsockets", FALSE), "LWS_EV_READ", newSVuv(LWS_EV_READ));
    newCONSTSUB(gv_stashpv("Net::Libwebsockets", FALSE), "LWS_EV_WRITE", newSVuv(LWS_EV_WRITE));

void
lws_service_fd_read( UV lws_context_uv, int fd )
    CODE:
        _lws_service_fd(aTHX_ lws_context_uv, fd, POLLIN);

void
lws_service_fd_write( UV lws_context_uv, int fd )
    CODE:
        _lws_service_fd(aTHX_ lws_context_uv, fd, POLLOUT);

int
get_timeout( UV lws_context_uv )
    CODE:
        intptr_t lws_context_int = lws_context_uv;
        struct lws_context *context = (void *) lws_context_int;

        RETVAL = lws_service_adjust_timeout(
            context,
            DEFAULT_POLL_TIMEOUT,
            0
        );

    OUTPUT:
        RETVAL

MODULE = Net::Libwebsockets     PACKAGE = Net::Libwebsockets::WebSocket::Client

PROTOTYPES: DISABLE

SV*
_new (SV* hostname, int port, SV* path, SV* subprotocols_sv, SV* headers_ar, int tls_opts, unsigned ping_interval, unsigned ping_timeout, SV* loop_obj, SV* connected_d)
    CODE:
        //lws_set_log_level( LLL_USER | LLL_ERR | LLL_WARN | LLL_NOTICE | LLL_DEBUG | LLL_PARSER | LLL_HEADER | LLL_INFO, NULL );
        lws_set_log_level( LLL_USER | LLL_ERR | LLL_WARN | LLL_NOTICE | LLL_PARSER | LLL_HEADER | LLL_INFO, NULL );

        struct lws_context_creation_info info;
        Zero(&info, 1, struct lws_context_creation_info);

        struct lws_client_connect_info client;
        Zero(&client, 1, struct lws_client_connect_info);

        my_perl_context_t* my_perl_context;
        Newxz(my_perl_context, 1, my_perl_context_t); // TODO clean up
        my_perl_context->aTHX = aTHX;

        my_perl_context->connect_d = connected_d;
        SvREFCNT_inc(connected_d);

        my_perl_context->headers_ar = headers_ar;
        SvREFCNT_inc(headers_ar);

        my_perl_context->courier = NULL;
        my_perl_context->courier_sv = NULL;

        my_perl_context->lws_retry.retry_ms_table_count = 0;
        my_perl_context->lws_retry.conceal_count = 0;
        my_perl_context->lws_retry.secs_since_valid_ping = ping_interval;
        my_perl_context->lws_retry.secs_since_valid_hangup = ping_timeout;


        info.options = (
            LWS_SERVER_OPTION_DO_SSL_GLOBAL_INIT
            | LWS_SERVER_OPTION_VALIDATE_UTF8
        );

        // TODO: make this adjustable
        info.extensions = default_extensions;

        info.event_lib_custom = &evlib_custom;

        info.user = (void *) my_perl_context;

        Newx(my_perl_context->abstract_loop, 1, net_lws_abstract_loop_t);
        my_perl_context->abstract_loop->aTHX = aTHX;
        my_perl_context->abstract_loop->perlobj = loop_obj;
        SvREFCNT_inc(loop_obj);

        info.foreign_loops = (void *[]) {
            my_perl_context->abstract_loop,
        };

        info.port = CONTEXT_PORT_NO_LISTEN; /* we do not run any server */

        const struct lws_protocols protocols[] = {
            {
                .name = NET_LWS_LOCAL_PROTOCOL_NAME,
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

        const char* hostname_str = SvPVbyte_nolen(hostname);

        client.context = context;
        client.port = port;
        client.address = hostname_str;
        client.path = SvPVbyte_nolen(path);
        client.host = hostname_str;
        client.origin = hostname_str;
        client.ssl_connection = tls_opts;
        client.retry_and_idle_policy = &my_perl_context->lws_retry;
        client.local_protocol_name = protocols[0].name;

        // The callback’s `user`:
        client.userdata = my_perl_context;

        if (SvOK(subprotocols_sv)) {
            client.protocol = SvPVbyte_nolen(subprotocols_sv);
        }

        if (!lws_client_connect_via_info(&client)) {
            lws_context_destroy(context);
            croak("lws connect failed");
        }

        connect_state_t* connect_state;
        Newx(connect_state, 1, connect_state_t);

        fprintf(stderr, "my_perl_context: %p\n", my_perl_context);

        connect_state->perl_context = my_perl_context;
        connect_state->lws_context = context;
        connect_state->pid = getpid();

        RETVAL = xsh_ptr_to_svrv(aTHX_ connect_state, gv_stashpv(WEBSOCKET_CLASS, FALSE));

    OUTPUT:
        RETVAL

void
DESTROY (SV* self_sv)
    CODE:
        warn("start connect_state destroy\n");
        connect_state_t* connect_state = xsh_svrv_to_ptr(aTHX_ self_sv);

        if (IS_GLOBAL_DESTRUCTION && (getpid() == connect_state->pid)) {
            warn("Destroying %" SVf " at global destruction!\n", self_sv);
        }

        if (connect_state->perl_context->connect_d) {

            // If we got here, then we’re DESTROYed before the
            // connection was ever made.

            my_perl_context_t* my_perl_context = connect_state->perl_context;

            lws_context_destroy(connect_state->lws_context);

            SvREFCNT_dec(my_perl_context->connect_d);

            if (my_perl_context->message_content) {
                Safefree(my_perl_context->message_content);
            }

            SvREFCNT_dec(my_perl_context->abstract_loop->perlobj);
            Safefree(my_perl_context->abstract_loop);

            Safefree(my_perl_context);
        }

        Safefree(connect_state);
        warn("end connect_state destroy\n");

# ----------------------------------------------------------------------

MODULE = Net::Libwebsockets     PACKAGE = Net::Libwebsockets::WebSocket::Pause

PROTOTYPES: DISABLE

void
DESTROY (SV* self_sv)
    CODE:
        pause_t* my_pause = xsh_svrv_to_ptr(aTHX_ self_sv);

        courier_t* courier = xsh_svrv_to_ptr(aTHX_ my_pause->courier_sv);

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
        courier_t* courier = xsh_svrv_to_ptr(aTHX_ self_sv);

        SvREFCNT_inc(cbref);

        courier->on_text_count++;
        Renew(courier->on_text, courier->on_text_count, SV*);
        courier->on_text[courier->on_text_count - 1] = cbref;

void
on_binary (SV* self_sv, SV* cbref)
    CODE:
        courier_t* courier = xsh_svrv_to_ptr(aTHX_ self_sv);

        SvREFCNT_inc(cbref);

        courier->on_binary_count++;
        Renew(courier->on_binary, courier->on_binary_count, SV*);
        courier->on_binary[courier->on_binary_count - 1] = cbref;

SV*
done_p (SV* self_sv)
    CODE:
        courier_t* courier = xsh_svrv_to_ptr(aTHX_ self_sv);

        RETVAL = xsh_call_object_method_scalar(aTHX_ courier->done_d, "promise", NULL);

    OUTPUT:
        RETVAL

void
send_text (SV* self_sv, SV* payload_sv)
    CODE:
        courier_t* courier = xsh_svrv_to_ptr(aTHX_ self_sv);

        STRLEN len;
        U8* buf = (U8*) SvPVutf8(payload_sv, len);

        _courier_sv_send(aTHX_ courier, buf, len, LWS_WRITE_TEXT);

void
send_binary (SV* self_sv, SV* payload_sv)
    CODE:
        courier_t* courier = xsh_svrv_to_ptr(aTHX_ self_sv);

        STRLEN len;
        U8* buf = (U8*) SvPVbyte(payload_sv, len);

        _courier_sv_send(aTHX_ courier, buf, len, LWS_WRITE_BINARY);

SV*
pause (SV* self_sv)
    CODE:
        if (GIMME_V == G_VOID) croak("Don’t call pause() in void context!");

        courier_t* courier = xsh_svrv_to_ptr(aTHX_ self_sv);

        pause_t* my_pause;
        Newx(my_pause, 1, pause_t);

        my_pause->courier_sv = self_sv;
        SvREFCNT_inc(self_sv);

        if (!courier->pauses) {
            lws_rx_flow_control(courier->wsi, 0);
        }

        courier->pauses++;

        RETVAL = xsh_ptr_to_svrv(aTHX_ my_pause, gv_stashpv(PAUSE_CLASS, FALSE));

    OUTPUT:
        RETVAL

void
close (SV* self_sv, U16 code=LWS_CLOSE_STATUS_NOSTATUS, SV* reason_sv=NULL)
    CODE:
        courier_t* courier = xsh_svrv_to_ptr(aTHX_ self_sv);

        if (reason_sv && SvOK(reason_sv)) {
            U8* reason = (U8*) SvPVutf8(reason_sv, courier->close_reason_length);

            if (courier->close_reason_length > MAX_CLOSE_REASON_LENGTH) {
                warn("Truncating %zu-byte close reason (%.*s) to %d bytes …", courier->close_reason_length, (int) courier->close_reason_length, reason, MAX_CLOSE_REASON_LENGTH);
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
        courier_t* courier = xsh_svrv_to_ptr(aTHX_ self_sv);
        warn("xxxxxx destroying %" SVf "\n", self_sv);

        if (IS_GLOBAL_DESTRUCTION && (getpid() == courier->pid)) {
            warn("Destroying %" SVf " at global destruction!\n", self_sv);
        }

        nlws_destroy_courier(aTHX_ courier);

# ----------------------------------------------------------------------

MODULE = Net::Libwebsockets     PACKAGE = Net::Libwebsockets::Loop

PROTOTYPES: DISABLE

void
_xs_pre_destroy (SV* self_sv, SV* context_ptr_sv)
    CODE:
        UNUSED(self_sv);

        if (SvOK(context_ptr_sv)) {
            intptr_t lws_context_int = SvUV(context_ptr_sv);

            struct lws_context *context = (void *) lws_context_int;

            my_perl_context_t* my_perl_context = lws_context_user(context);

            if (my_perl_context) {
                Safefree(my_perl_context->abstract_loop);
                my_perl_context->abstract_loop = NULL;
            }
        }
