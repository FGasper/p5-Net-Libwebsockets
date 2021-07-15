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
#include "nlws_context.h"

#if DEBUG
#define LOG_FUNC fprintf(stderr, "%s\n", __func__)
#else
#define LOG_FUNC
#endif

#if defined(LWS_WITHOUT_EXTENSIONS)
#   define NLWS_LWS_HAS_EXTENSIONS false
#else
#   define NLWS_LWS_HAS_EXTENSIONS true
#endif

#ifdef NLWS_LWS_HAS_PMD
#define _LWS_HAS_PMD 1
#else
#define _LWS_HAS_PMD 0
#endif

#define WS_CLOSE_IS_FAILURE(code) (code == LWS_CLOSE_STATUS_NOSTATUS || code == LWS_CLOSE_STATUS_NORMAL)

typedef struct {
    SV* courier_sv;
} pause_t;

static inline void _finish_deferred_sv (pTHX_ SV** deferred_svp, const char* methname, SV* payload) {
    if (DEBUG) warn("finishing deferred (payload=%p)\n", payload);

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

void _on_ws_close (pTHX_ my_perl_context_t* my_perl_context, uint16_t code, size_t reasonlen, const U8* reason) {
    LOG_FUNC;

    SV* args[] = {
        newSVuv(code),
        newSVpvn((const char *) reason, reasonlen),
    };

    unsigned numargs = sizeof(args) / sizeof(*args);

    AV* code_reason = av_make( numargs, args );

    SV* arg = newRV_noinc((SV*) code_reason);

    _finish_deferred_sv( aTHX_ &my_perl_context->courier->done_d, "resolve", arg );
}

void _on_ws_error (pTHX_ my_perl_context_t* my_perl_context, size_t reasonlen, const char* reason) {
    LOG_FUNC;

    SV** deferred_svp;

    if (my_perl_context->courier) {
        deferred_svp = &my_perl_context->courier->done_d;
    }
    else {
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
net_lws_wsclient_callback(
    struct lws *wsi,
    enum lws_callback_reasons reason,
    void *user,
    void *in,
    size_t len
) {
    my_perl_context_t* my_perl_context = user;

    if (DEBUG) fprintf(stderr, "LWS callback: %d\n", reason);

    // Not all callbacks pass user??
    pTHX = my_perl_context ? my_perl_context->aTHX : NULL;

    switch (reason) {

    case LWS_CALLBACK_WSI_DESTROY:
        if (my_perl_context->courier_sv) {
            SvREFCNT_dec(my_perl_context->courier_sv);
        }

        net_lws_abstract_loop_t* myloop_p = (net_lws_abstract_loop_t*) lws_evlib_wsi_to_evlib_pt(wsi);

        if (myloop_p && myloop_p->perlobj) {
            SvREFCNT_dec(myloop_p->perlobj);
        }

        lws_context_destroy(myloop_p->lws_context);

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
                (const U8*) xsh_sv_to_str(aTHX_ *key),
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
        courier_t* courier = nlws_create_courier(aTHX, wsi);

        my_perl_context->courier = courier;

        SV* courier_sv = xsh_ptr_to_svrv(aTHX_ courier, gv_stashpv(COURIER_CLASS, FALSE));
        my_perl_context->courier_sv = courier_sv;

        _finish_deferred_sv( aTHX_ &my_perl_context->connect_d, "resolve", newSVsv(courier_sv) );

        } break;

    case LWS_CALLBACK_WS_PEER_INITIATED_CLOSE:
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
            _on_ws_close(aTHX_
                my_perl_context,
                courier->close_status,
                courier->close_reason_length,
                courier->close_reason
            );
        }
        else {
            warn("LWS_CALLBACK_CLIENT_CLOSED but we didn’t close … is this OK?");
        }

        } break;

    default:
        break;
    }

    return 0;
}


void _courier_send( pTHX_ courier_t* courier, U8* buf, STRLEN len, enum lws_write_protocol protocol ) {

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
    uintptr_t lws_context_int = lws_context_uv;

    struct lws_context *context = (void *) lws_context_int;

    struct lws_pollfd pollfd = {
        .fd = fd,
        .events = event,
        .revents = event,
    };

    lws_service_fd(context, &pollfd);
}

const struct lws_protocols wsclient_protocols[] = {
    {
        .name = NET_LWS_LOCAL_PROTOCOL_NAME,
        .callback = net_lws_wsclient_callback,
        .per_session_data_size = sizeof(void*),
        .rx_buffer_size = 0,
    },
    { NULL }
};

void _populate_extensions (pTHX_ struct lws_extension* extensions, AV* compressions_av) {
#if _LWS_HAS_PMD
    SSize_t compressions_len = 1 + av_top_index(compressions_av);

    for (SSize_t c=0; c<compressions_len; c++) {
        SV** cur_p = av_fetch(compressions_av, c, FALSE);

        assert(cur_p);
        assert(*cur_p);
        assert(SvROK(*cur_p));
        assert(SVt_PVAV == SvTYPE(SvRV(*cur_p)));

        AV* cur_av = (AV*) SvRV(*cur_p);

        SV** extn_name_p = av_fetch(cur_av, 0, FALSE);
        assert(extn_name_p);
        assert(*extn_name_p);
        assert(SvOK(*extn_name_p));

        if (!strEQ("deflate", SvPVbyte_nolen(*extn_name_p)) ) {
            croak("Bad extension name: %" SVf, *extn_name_p);
        }

        SV** client_offer_p = av_fetch(cur_av, 1, FALSE);
        assert(client_offer_p);
        assert(*client_offer_p);
        assert(SvOK(*client_offer_p));

        extensions[c] = (struct lws_extension) {
            .name = "permessage-deflate",
            .callback = lws_extension_callback_pm_deflate,
            .client_offer = SvPVbyte_nolen(*client_offer_p),
        };
    }
#endif
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
    newCONSTSUB(gv_stashpv("Net::Libwebsockets", FALSE), "NLWS_LWS_HAS_PMD", _LWS_HAS_PMD ? &PL_sv_yes : &PL_sv_no);

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
        uintptr_t lws_context_int = lws_context_uv;

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

void
_new (SV* hostname, int port, SV* path, SV* compression_sv, SV* subprotocols_sv, SV* headers_ar, int tls_opts, unsigned ping_interval, unsigned ping_timeout, SV* loop_obj, SV* connected_d)
    CODE:
        //lws_set_log_level( LLL_USER | LLL_ERR | LLL_WARN | LLL_NOTICE | LLL_DEBUG | LLL_PARSER | LLL_HEADER | LLL_INFO, NULL );
        lws_set_log_level( LLL_USER | LLL_ERR | LLL_WARN | LLL_NOTICE | LLL_PARSER | LLL_HEADER | LLL_INFO, NULL );

        assert(SvROK(compression_sv));
        assert(SVt_PVAV == SvTYPE(SvRV(compression_sv)));

        AV* compressions_av = (AV*) SvRV(compression_sv);
        SSize_t compressions_len = 1 + av_top_index(compressions_av);

        struct lws_extension* extensions_p;

        if (NLWS_LWS_HAS_EXTENSIONS) {
            Newxz(extensions_p, 1 + compressions_len, struct lws_extension);

            _populate_extensions(aTHX_ extensions_p, compressions_av);
        }
        else {
            extensions_p = NULL;
        }

        net_lws_abstract_loop_t abstract_loop = {
            .aTHX = aTHX,
            .perlobj = loop_obj,
        };

        struct lws_context_creation_info info = {
            .options = LWS_SERVER_OPTION_DO_SSL_GLOBAL_INIT
                        | LWS_SERVER_OPTION_VALIDATE_UTF8,

            //.extensions = extensions_p,

            .event_lib_custom = &evlib_custom,

            .foreign_loops = (void *[]) {
                &abstract_loop,
            },

            .port = CONTEXT_PORT_NO_LISTEN, /* we do not run any server */

            .protocols = wsclient_protocols,
        };

        struct lws_context *context = lws_create_context(&info);
        if (!context) {
            if (extensions_p) Safefree(extensions_p);
            croak("lws init failed");
        }

        my_perl_context_t* my_perl_context;
        Newxz(my_perl_context, 1, my_perl_context_t); // TODO clean up

        *my_perl_context = (my_perl_context_t) {
            .aTHX = aTHX,
            .pid = getpid(),

            .extensions = extensions_p,

            .courier = NULL,
            .courier_sv = NULL,

            // We bump the refcounts of these below:
            .connect_d = connected_d,
            .headers_ar = headers_ar,

            .lws_retry = (lws_retry_bo_t) {
                .retry_ms_table_count = 0,
                .conceal_count = 0,
                .secs_since_valid_ping = ping_interval,
                .secs_since_valid_hangup = ping_timeout,
            },
        };

        const char* hostname_str = xsh_sv_to_str(aTHX_ hostname);

        struct lws_client_connect_info client = {
            .context = context,
            .port = port,

            .address = hostname_str,
            .path = xsh_sv_to_str(aTHX_ path),
            .host = hostname_str,
            .origin = hostname_str,
            .ssl_connection = tls_opts,
//            .retry_and_idle_policy = &my_perl_context->lws_retry,

            // The callback’s `user`:
            .userdata = my_perl_context,

            .protocol = SvOK(subprotocols_sv) ? xsh_sv_to_str(aTHX_ subprotocols_sv) : NULL,
        };

        if (!lws_client_connect_via_info(&client)) {
            Safefree(extensions_p);
            lws_context_destroy(context);
            croak("lws connect failed");
        }

        SvREFCNT_inc(connected_d);
        SvREFCNT_inc(headers_ar);

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

        _courier_send(aTHX_ courier, buf, len, LWS_WRITE_TEXT);

void
send_binary (SV* self_sv, SV* payload_sv)
    CODE:
        courier_t* courier = xsh_svrv_to_ptr(aTHX_ self_sv);

        STRLEN len;
        U8* buf = (U8*) SvPVbyte(payload_sv, len);

        _courier_send(aTHX_ courier, buf, len, LWS_WRITE_BINARY);

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
        else {
            courier->close_reason_length = 0;
        }

        courier->close_yn = true;
        courier->close_status = code;

        // Force a writable callback, which will trigger our close.
        lws_callback_on_writable(courier->wsi);

void
DESTROY (SV* self_sv)
    CODE:
        warn("xxxxxx destroying %" SVf "\n", self_sv);
        courier_t* courier = xsh_svrv_to_ptr(aTHX_ self_sv);

        if (IS_GLOBAL_DESTRUCTION && (getpid() == courier->pid)) {
            warn("Destroying %" SVf " at global destruction!\n", self_sv);
        }

        nlws_destroy_courier(aTHX_ courier);