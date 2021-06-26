#ifndef XSHELPER_H
#define XSHELPER_H

#define PERL_NO_GET_CONTEXT
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

void xsh_call_object_method_void (pTHX_ SV* object, const char* methname, SV** args);

void* xsh_svrv_to_ptr (pTHX_ SV* svrv);

SV* xsh_ptr_to_svrv (pTHX_ void* ptr, HV* stash);

#endif
