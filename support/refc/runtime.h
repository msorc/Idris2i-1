#pragma once

#include "cBackend.h"

void idris2_missing_ffi();

#define idris2_isUnique(x) ((x)->header.refCounter == 1)
void idris2_removeReuseConstructor(Idris2_Constructor *constr);

Idris2_Value *idris2_apply_closure(Idris2_Value *, Idris2_Value *arg);
Idris2_Value *idris2_tailcall_apply_closure(Idris2_Value *_clos,
                                            Idris2_Value *arg);
Idris2_Value *idris2_apply_closure2(Idris2_Value *, Idris2_Value *arg1,
                                    Idris2_Value *arg2);
Idris2_Value *idris2_tailcall_apply_closure2(Idris2_Value *_clos,
                                             Idris2_Value *arg1,
                                             Idris2_Value *arg2);

// A call in tail position does not allocate a closure: the function stores
// the call in idris2_pendingTailCall and returns IDRIS2_TAILCALL, which the
// trampoline of its caller makes.  Nothing can run in between but the release
// of values; the finaliser of a GC pointer saves and restores the pending
// call (see idris2_releaseValue).
#define IDRIS2_MAX_TAILCALL_ARGS 16
typedef struct {
  void *f;
  uint8_t arity;
  Idris2_Value *args[IDRIS2_MAX_TAILCALL_ARGS];
} Idris2_PendingTailCall;
extern Idris2_PendingTailCall idris2_pendingTailCall;
extern Idris2_Value const idris2_tailCallMarker;
#define IDRIS2_TAILCALL ((Idris2_Value *)&idris2_tailCallMarker)

// Make the pending calls that `it` stands for: a pending tail call, or a
// closure that has all its arguments.  Most calls return a plain value, so
// that case is inlined.
Idris2_Value *idris2_trampolineSlow(Idris2_Value *it);
static inline Idris2_Value *idris2_trampoline(Idris2_Value *it) {
  if (it != IDRIS2_TAILCALL &&
      (!it || idris2_vp_is_unboxed(it) || it->header.tag != CLOSURE_TAG))
    return it;
  return idris2_trampolineSlow(it);
}

// Run a `PrimIO` action to completion and return its result.  This consumes
// the reference to the action.
Idris2_Value *idris2_run_primio(Idris2_Closure *action);

int idris2_extractInt(Idris2_Value *);
