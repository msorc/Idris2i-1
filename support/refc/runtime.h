#pragma once

#include "cBackend.h"

void idris2_missing_ffi();

#define idris2_isUnique(x) ((x)->header.refCounter == 1)
void idris2_removeReuseConstructor(Idris2_Constructor *constr);

Idris2_Value *idris2_apply_closure(Idris2_Value *, Idris2_Value *arg);
Idris2_Value *idris2_tailcall_apply_closure(Idris2_Value *_clos,
                                            Idris2_Value *arg);
Idris2_Value *idris2_trampoline(Idris2_Value *closure);

// Run a `PrimIO` action to completion and return its result.  This consumes
// the reference to the action.
Idris2_Value *idris2_run_primio(Idris2_Closure *action);

int idris2_extractInt(Idris2_Value *);
