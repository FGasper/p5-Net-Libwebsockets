#include "xshelper.h"

void xsh_call_object_method_void (pTHX_ SV* object, const char* methname, SV** args) {
fprintf(stderr, "calling method: %s\n", methname);
    unsigned argscount = 0;
    while (args[argscount] != NULL) argscount++;

    dSP;

    ENTER;
    SAVETMPS;

    PUSHMARK(SP);

    EXTEND(SP, 1 + argscount);

    PUSHs( sv_mortalcopy(object) );

    while (argscount--) mPUSHs( args[argscount] );

    PUTBACK;

    call_method( methname, G_DISCARD | G_VOID );

    FREETMPS;
    LEAVE;
}
