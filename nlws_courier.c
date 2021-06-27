#include "nlws_courier.h"
#include "nlws_frame.h"

static inline SV* _new_deferred_sv(pTHX) {
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

courier_t* nlws_create_courier (pTHX_ struct lws *wsi) {
    courier_t* courier;
    Newx(courier, 1, courier_t);

    courier->wsi = wsi;

    courier->on_text_count = 0;
    courier->on_text = NULL;
    courier->on_binary_count = 0;
    courier->on_binary = NULL;
    courier->close_yn = false;

    courier->pid = getpid();

    courier->ring = lws_ring_create(sizeof(frame_t), RING_DEPTH, nlws_destroy_frame);
    courier->consume_pending_count = 0;

    courier->pauses = 0;

    if (!courier->ring) {
        Safefree(courier);
        croak("lws_ring_create() failed!");
    }

    courier->done_d = _new_deferred_sv(aTHX);

    return courier;
}

void nlws_destroy_courier (pTHX_ courier_t* courier) {
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

    if (courier->done_d) SvREFCNT_dec(courier->done_d);

    lws_ring_destroy(courier->ring);

    Safefree(courier);
    warn("end courier destroy\n");
}
