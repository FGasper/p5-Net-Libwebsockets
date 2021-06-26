#include "nlws_perl_loop.h"

static int
init_pt_custom (struct lws_context *cx, void *_loop, int tsi) {
    net_lws_abstract_loop_t* myloop_p = lws_evlib_tsi_to_evlib_pt(cx, tsi);

    net_lws_abstract_loop_t *sourceloop_p = _loop;

    memcpy(myloop_p, sourceloop_p, sizeof(net_lws_abstract_loop_t));

    return 0;
}

static int
custom_io_accept (struct lws *wsi) {
    net_lws_abstract_loop_t* myloop_p = lws_evlib_wsi_to_evlib_pt(wsi);

    pTHX = myloop_p->aTHX;

    int fd = lws_get_socket_fd(wsi);

    SV* myloop_sv = myloop_p->perlobj;

    SV* args[] = { newSViv(fd), NULL };

    xsh_call_object_method_void(aTHX_ myloop_sv, "add_fd", args);

    return 0;
}

static void
custom_io (struct lws *wsi, unsigned int flags) {
    net_lws_abstract_loop_t* myloop_p = lws_evlib_wsi_to_evlib_pt(wsi);

    int fd = lws_get_socket_fd(wsi);

    if (-1 != fd) {
        pTHX = myloop_p->aTHX;

        SV* myloop_sv = myloop_p->perlobj;

        char *method_name;

        if (flags & LWS_EV_START) {
            method_name = "add_to_fd";
        }
        else {
            method_name = "remove_from_fd";
        }

        SV* args[] = {
            newSViv(fd),
            newSVuv(flags),
            NULL,
        };

        xsh_call_object_method_void(aTHX_ myloop_sv, method_name, args );
    }
}

static int
custom_io_close (struct lws *wsi) {
    net_lws_abstract_loop_t* myloop_p = lws_evlib_wsi_to_evlib_pt(wsi);

    int fd = lws_get_socket_fd(wsi);

    if (-1 != fd) {
        pTHX = myloop_p->aTHX;

        SV* myloop_sv = myloop_p->perlobj;

        SV* args[] = { newSViv(fd), NULL };

        xsh_call_object_method_void(aTHX_ myloop_sv, "remove_fd", args);
    }

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