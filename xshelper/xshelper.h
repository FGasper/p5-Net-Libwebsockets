#ifndef XSHELPER_H
#define XSHELPER_H

#define PERL_NO_GET_CONTEXT
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

/*
    Calls $object->$methname(@args) in void context. (args may be NULL.)

    IMPORTANT: Each @args will be MORTALIZED!
*/
void xsh_call_object_method_void (pTHX_ SV* object, const char* methname, SV** args);

SV* xsh_call_object_method_scalar (pTHX_ SV* object, const char* methname, SV** args);

void xsh_call_sv_trap_void (pTHX_ SV* cbref, SV** args, const char *warnprefix);

/*
    Creates a new SVRV that refers to ptr, blessed as a scalar reference.
*/
SV* xsh_ptr_to_svrv (pTHX_ void* ptr, HV* stash);

/*
    Extracts a pointer value from an SVRV, which we assume to be
    a scalar reference. The reverse of xsh_ptr_to_svrv().
*/
void* xsh_svrv_to_ptr (pTHX_ SV* svrv);


#endif
