#include "nlws.h"
#include "nlws_courier.h"
#include "nlws_frame.h"

#define DEBUG 0

#if DEBUG
#define LOG_FUNC fprintf(stderr, "%s\n", __func__)
#else
#define LOG_FUNC
#endif

courier_t* nlws_create_courier (pTHX_ struct lws *wsi) {
    LOG_FUNC;

    struct lws_ring *ring = lws_ring_create(
        sizeof(frame_t),
        RING_DEPTH,
        nlws_destroy_frame
    );

    if (!ring) {
        croak("lws_ring_create() failed!");
    }

    courier_t* courier;
    Newx(courier, 1, courier_t);

    *courier = (courier_t) {
        .wsi = wsi,
        .pid = getpid(),
        .ring = ring,

        // Everything else is initialized to 0/NULL.
    };

    return courier;
}

void nlws_destroy_courier (pTHX_ courier_t* courier) {
    LOG_FUNC;

    if (courier->on_text) {
        for (unsigned i=0; i<courier->on_text_count; i++) {
            NLWS_SvREFCNT_dec(courier->on_text[i]);
        }

        Safefree(courier->on_text);
    }

    if (courier->on_binary) {
        for (unsigned i=0; i<courier->on_binary_count; i++) {
            NLWS_SvREFCNT_dec(courier->on_binary[i]);
        }

        Safefree(courier->on_binary);
    }

    lws_ring_destroy(courier->ring);

    Safefree(courier);
    //warn("end courier destroy\n");
}
