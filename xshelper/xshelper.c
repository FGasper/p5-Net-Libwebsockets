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

void xsh_call_object_method_void (pTHX_ SV* object, const char* methname, SV** args) {
    unsigned argscount = 0;

    while (args[argscount] != NULL) {
        argscount++;
    }

    dSP;

    ENTER;
    SAVETMPS;

    PUSHMARK(SP);

    EXTEND(SP, 1 + argscount);

    PUSHs( sv_mortalcopy(object) );

    unsigned a=0;
    while (a < argscount) mPUSHs( args[a++] );

    PUTBACK;

    call_method( methname, G_DISCARD | G_VOID );

    FREETMPS;
    LEAVE;
}
