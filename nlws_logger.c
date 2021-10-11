#include "nlws_logger.h"

void nlws_logger_emit(struct lws_log_cx *cx, int level, const char *line, size_t len) {
    nlws_logger_opaque_t* opaque = cx->opaque;

    pTHX = opaque->aTHX;

    SV* args[] = {
        newSVpvn_flags(line, len, SVs_TEMP),
        NULL,
    };

    xsh_call_sv_trap_void(opaque->callback, args, LOGGER_CLASS " callback error: ");
}
