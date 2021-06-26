#ifndef XSHELPER_H
#define XSHELPER_H

#define PERL_NO_GET_CONTEXT
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

void xsh_call_object_method_void (pTHX_ SV* object, const char* methname, SV** args);

#endif
