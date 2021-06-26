#include "xshelper.h"

void* xsh_svrv_to_ptr (pTHX_ SV* svrv) {
    return (void *) (intptr_t) SvUV( SvRV(svrv) );
}

SV* xsh_ptr_to_svrv (pTHX_ void* ptr, HV* stash) {
    SV* referent = newSVuv( PTR2UV(ptr) );
    SV* retval = newRV_noinc(referent);
    sv_bless(retval, stash);

    return retval;
}

/* ---------------------------------------------------------------------- */

#define _SET_ARGS(object, args) {               \
    unsigned argscount = 0;                     \
                                                \
    if (args) {                                 \
        while (args[argscount] != NULL) {       \
            argscount++;                        \
        }                                       \
    }                                           \
                                                \
    ENTER;                                      \
    SAVETMPS;                                   \
                                                \
    PUSHMARK(SP);                               \
                                                \
    EXTEND(SP, 1 + argscount);                  \
                                                \
    if (object) PUSHs( sv_mortalcopy(object) ); \
                                                \
    unsigned a=0;                               \
    while (a < argscount) mPUSHs( args[a++] );  \
                                                \
    PUTBACK;                                    \
}

void xsh_call_object_method_void (pTHX_ SV* object, const char* methname, SV** args) {
    dSP;

    _SET_ARGS(object, args);

    call_method( methname, G_DISCARD | G_VOID );

    FREETMPS;
    LEAVE;
}

SV* xsh_call_object_method_scalar (pTHX_ SV* object, const char* methname, SV** args) {
    dSP;

    _SET_ARGS(object, args);

    int got = call_method( methname, G_SCALAR );

    assert(got < 2);

    SV* ret = got ? SvREFCNT_inc(POPs) : NULL;

    FREETMPS;
    LEAVE;

    return ret;
}

void xsh_call_sv_trap_void (pTHX_ SV* cbref, SV** args, const char *warnprefix) {
    dSP;

    _SET_ARGS(NULL, args);

    call_sv(cbref, G_VOID|G_DISCARD|G_EVAL);

    SV* err = ERRSV;

    if (err && SvTRUE(err)) {
        warn("%s%" SVf, warnprefix, err);
    }

    FREETMPS;
    LEAVE;
}
