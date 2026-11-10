#include "runtime.h"
#include "_datatypes.h"
#include "refc_util.h"

void idris2_missing_ffi() {
  fprintf(stderr, "Foreign function declared, but not defined.\n"
                  "Cannot call missing FFI - aborting.\n");
  exit(1);
}

typedef Idris2_Value *(*const FUN0)();
typedef Idris2_Value *(*const FUN1)(Idris2_Value *);
typedef Idris2_Value *(*const FUN2)(Idris2_Value *, Idris2_Value *);
typedef Idris2_Value *(*const FUN3)(Idris2_Value *, Idris2_Value *,
                                    Idris2_Value *);
typedef Idris2_Value *(*const FUN4)(Idris2_Value *, Idris2_Value *,
                                    Idris2_Value *, Idris2_Value *);
typedef Idris2_Value *(*const FUN5)(Idris2_Value *, Idris2_Value *,
                                    Idris2_Value *, Idris2_Value *,
                                    Idris2_Value *);
typedef Idris2_Value *(*const FUN6)(Idris2_Value *, Idris2_Value *,
                                    Idris2_Value *, Idris2_Value *,
                                    Idris2_Value *, Idris2_Value *);
typedef Idris2_Value *(*const FUN7)(Idris2_Value *, Idris2_Value *,
                                    Idris2_Value *, Idris2_Value *,
                                    Idris2_Value *, Idris2_Value *,
                                    Idris2_Value *);
typedef Idris2_Value *(*const FUN8)(Idris2_Value *, Idris2_Value *,
                                    Idris2_Value *, Idris2_Value *,
                                    Idris2_Value *, Idris2_Value *,
                                    Idris2_Value *, Idris2_Value *);
typedef Idris2_Value *(*const FUN9)(Idris2_Value *, Idris2_Value *,
                                    Idris2_Value *, Idris2_Value *,
                                    Idris2_Value *, Idris2_Value *,
                                    Idris2_Value *, Idris2_Value *,
                                    Idris2_Value *);
typedef Idris2_Value *(*const FUN10)(Idris2_Value *, Idris2_Value *,
                                     Idris2_Value *, Idris2_Value *,
                                     Idris2_Value *, Idris2_Value *,
                                     Idris2_Value *, Idris2_Value *,
                                     Idris2_Value *, Idris2_Value *);
typedef Idris2_Value *(*const FUN11)(Idris2_Value *, Idris2_Value *,
                                     Idris2_Value *, Idris2_Value *,
                                     Idris2_Value *, Idris2_Value *,
                                     Idris2_Value *, Idris2_Value *,
                                     Idris2_Value *, Idris2_Value *,
                                     Idris2_Value *);
typedef Idris2_Value *(*const FUN12)(Idris2_Value *, Idris2_Value *,
                                     Idris2_Value *, Idris2_Value *,
                                     Idris2_Value *, Idris2_Value *,
                                     Idris2_Value *, Idris2_Value *,
                                     Idris2_Value *, Idris2_Value *,
                                     Idris2_Value *, Idris2_Value *);
typedef Idris2_Value *(*const FUN13)(Idris2_Value *, Idris2_Value *,
                                     Idris2_Value *, Idris2_Value *,
                                     Idris2_Value *, Idris2_Value *,
                                     Idris2_Value *, Idris2_Value *,
                                     Idris2_Value *, Idris2_Value *,
                                     Idris2_Value *, Idris2_Value *,
                                     Idris2_Value *);
typedef Idris2_Value *(*const FUN14)(Idris2_Value *, Idris2_Value *,
                                     Idris2_Value *, Idris2_Value *,
                                     Idris2_Value *, Idris2_Value *,
                                     Idris2_Value *, Idris2_Value *,
                                     Idris2_Value *, Idris2_Value *,
                                     Idris2_Value *, Idris2_Value *,
                                     Idris2_Value *, Idris2_Value *);
typedef Idris2_Value *(*const FUN15)(
    Idris2_Value *, Idris2_Value *, Idris2_Value *, Idris2_Value *,
    Idris2_Value *, Idris2_Value *, Idris2_Value *, Idris2_Value *,
    Idris2_Value *, Idris2_Value *, Idris2_Value *, Idris2_Value *,
    Idris2_Value *, Idris2_Value *, Idris2_Value *);
typedef Idris2_Value *(*const FUN16)(
    Idris2_Value *, Idris2_Value *, Idris2_Value *, Idris2_Value *,
    Idris2_Value *, Idris2_Value *, Idris2_Value *, Idris2_Value *,
    Idris2_Value *, Idris2_Value *, Idris2_Value *, Idris2_Value *,
    Idris2_Value *, Idris2_Value *, Idris2_Value *, Idris2_Value *);
typedef Idris2_Value *(*const FUNStar)(Idris2_Value **);

// Call the function `f` of the given arity with the arguments in xs.
static inline Idris2_Value *idris2_dispatch(void *f, uint8_t arity,
                                            Idris2_Value **const xs) {
  switch (arity) {
  default:
    return (*(FUNStar)f)(xs);

  case 0:
    return (*(FUN0)f)();
  case 1:
    return (*(FUN1)f)(xs[0]);
  case 2:
    return (*(FUN2)f)(xs[0], xs[1]);
  case 3:
    return (*(FUN3)f)(xs[0], xs[1], xs[2]);
  case 4:
    return (*(FUN4)f)(xs[0], xs[1], xs[2], xs[3]);
  case 5:
    return (*(FUN5)f)(xs[0], xs[1], xs[2], xs[3], xs[4]);
  case 6:
    return (*(FUN6)f)(xs[0], xs[1], xs[2], xs[3], xs[4], xs[5]);
  case 7:
    return (*(FUN7)f)(xs[0], xs[1], xs[2], xs[3], xs[4], xs[5], xs[6]);
  case 8:
    return (*(FUN8)f)(xs[0], xs[1], xs[2], xs[3], xs[4], xs[5], xs[6],
                           xs[7]);
  case 9:
    return (*(FUN9)f)(xs[0], xs[1], xs[2], xs[3], xs[4], xs[5], xs[6],
                           xs[7], xs[8]);
  case 10:
    return (*(FUN10)f)(xs[0], xs[1], xs[2], xs[3], xs[4], xs[5], xs[6],
                            xs[7], xs[8], xs[9]);
  case 11:
    return (*(FUN11)f)(xs[0], xs[1], xs[2], xs[3], xs[4], xs[5], xs[6],
                            xs[7], xs[8], xs[9], xs[10]);
  case 12:
    return (*(FUN12)f)(xs[0], xs[1], xs[2], xs[3], xs[4], xs[5], xs[6],
                            xs[7], xs[8], xs[9], xs[10], xs[11]);
  case 13:
    return (*(FUN13)f)(xs[0], xs[1], xs[2], xs[3], xs[4], xs[5], xs[6],
                            xs[7], xs[8], xs[9], xs[10], xs[11], xs[12]);
  case 14:
    return (*(FUN14)f)(xs[0], xs[1], xs[2], xs[3], xs[4], xs[5], xs[6],
                            xs[7], xs[8], xs[9], xs[10], xs[11], xs[12],
                            xs[13]);
  case 15:
    return (*(FUN15)f)(xs[0], xs[1], xs[2], xs[3], xs[4], xs[5], xs[6],
                            xs[7], xs[8], xs[9], xs[10], xs[11], xs[12], xs[13],
                            xs[14]);
  case 16:
    return (*(FUN16)f)(xs[0], xs[1], xs[2], xs[3], xs[4], xs[5], xs[6],
                            xs[7], xs[8], xs[9], xs[10], xs[11], xs[12], xs[13],
                            xs[14], xs[15]);
  }
}

Idris2_PendingTailCall idris2_pendingTailCall;
Idris2_Value const idris2_tailCallMarker = {IDRIS2_STOCKVAL(NO_TAG)};

Idris2_Value *idris2_trampolineSlow(Idris2_Value *it) {
  for (;;) {
    if (it == IDRIS2_TAILCALL) {
      // The arguments are read before the call, which may store another
      // tail call.
      it = idris2_dispatch(idris2_pendingTailCall.f,
                           idris2_pendingTailCall.arity,
                           idris2_pendingTailCall.args);
      continue;
    }
    if (!it || idris2_vp_is_unboxed(it) || it->header.tag != CLOSURE_TAG)
      break;
    Idris2_Closure *clos = (Idris2_Closure *)it;
    if (clos->filled < clos->arity)
      break;

    it = idris2_dispatch(clos->f, clos->arity, clos->args);
    if (idris2_isUnique(clos))
      idris2_freeValue((Idris2_Value *)clos);
    else
      idris2_dropSharedReference((Idris2_Value *)clos);
  }
  return it;
}

// A `PrimIO` action is a closure waiting for its %World argument.  The world
// is not represented at runtime, so it is passed as NULL.  Applying it
// consumes the reference to the action (see idris2_tailcall_apply_closure).
Idris2_Value *idris2_run_primio(Idris2_Closure *action) {
  if (!action) {
    return NULL;
  }
  return idris2_trampoline(
      idris2_tailcall_apply_closure((Idris2_Value *)action, NULL));
}

Idris2_Value *idris2_tailcall_apply_closure(Idris2_Value *_clos,
                                            Idris2_Value *arg) {
  Idris2_Closure *clos = (Idris2_Closure *)_clos;
  // A closure has room for all its arguments (see idris2_mkClosure): when
  // nobody else refers to it, the argument goes in place.
  if (idris2_isUnique(clos) && clos->filled < clos->arity) {
    clos->args[clos->filled++] = arg;
    return (Idris2_Value *)clos;
  }

  // The argument completes a closure that is shared: make the call a pending
  // tail call (see runtime.h) rather than a copy of the closure that would be
  // called and freed right away.  The result goes through a trampoline, as
  // for any call in tail position.
  if (clos->filled + 1 == clos->arity &&
      clos->arity <= IDRIS2_MAX_TAILCALL_ARGS) {
    idris2_pendingTailCall.f = clos->f;
    idris2_pendingTailCall.arity = clos->arity;
    for (int i = 0; i < clos->filled; ++i)
      idris2_pendingTailCall.args[i] = idris2_newReference(clos->args[i]);
    idris2_pendingTailCall.args[clos->filled] = arg;
    idris2_dropSharedReference((Idris2_Value *)clos);
    return IDRIS2_TAILCALL;
  }

  // Otherwise create a new closure and copy args.
  Idris2_Closure *newclos = idris2_mkClosure(
      clos->f, clos->arity, clos->filled + 1 /* expanding a payload */);

  // (a unique closure was completed in place above, so this one is shared)
  for (int i = 0; i < clos->filled; ++i)
    newclos->args[i] = idris2_newReference(clos->args[i]);
  newclos->args[clos->filled] = arg; // add argument to new arglist
  idris2_dropSharedReference((Idris2_Value *)clos);

  return (Idris2_Value *)newclos;
}

// Call a closure that `n` more arguments complete (not in tail position):
// directly, rather than through a pending tail call and the trampoline.  The
// arguments go in the room of the closure (see idris2_mkClosure), which the
// call reads at once; no copy is made, so that this frame, which stays on the
// stack during the call, is small.
static inline Idris2_Value *idris2_call_closure(Idris2_Closure *clos,
                                                Idris2_Value *arg1,
                                                Idris2_Value *arg2, int n) {
  uint8_t filled = clos->filled;
  int unique = idris2_isUnique(clos);
  if (!unique)
    for (int i = 0; i < filled; ++i)
      idris2_newReference(clos->args[i]);
  clos->args[filled] = arg1;
  if (n == 2)
    clos->args[filled + 1] = arg2;
  Idris2_Value *r = idris2_dispatch(clos->f, clos->arity, clos->args);
  // The arguments were given to the call: only the closure is released.
  if (unique)
    idris2_freeValue((Idris2_Value *)clos);
  else
    idris2_removeReference((Idris2_Value *)clos);
  return idris2_trampoline(r);
}

Idris2_Value *idris2_apply_closure(Idris2_Value *_clos, Idris2_Value *arg) {
  Idris2_Closure *clos = (Idris2_Closure *)_clos;
  if (clos->filled + 1 == clos->arity &&
      clos->arity <= IDRIS2_MAX_TAILCALL_ARGS)
    return idris2_call_closure(clos, arg, NULL, 1);
  return idris2_trampoline(idris2_tailcall_apply_closure(_clos, arg));
}

// Apply a closure to two arguments, like idris2_tailcall_apply_closure
// twice, but without the partial application in between when both
// arguments go to the closure.
Idris2_Value *idris2_tailcall_apply_closure2(Idris2_Value *_clos,
                                             Idris2_Value *arg1,
                                             Idris2_Value *arg2) {
  Idris2_Closure *clos = (Idris2_Closure *)_clos;
  if (clos->filled + 2 > clos->arity) {
    // The closure takes one more argument: apply its result to the other.
    return idris2_tailcall_apply_closure(idris2_apply_closure(_clos, arg1),
                                         arg2);
  }
  if (idris2_isUnique(clos)) {
    clos->args[clos->filled++] = arg1;
    clos->args[clos->filled++] = arg2;
    return (Idris2_Value *)clos;
  }
  if (clos->filled + 2 == clos->arity &&
      clos->arity <= IDRIS2_MAX_TAILCALL_ARGS) {
    idris2_pendingTailCall.f = clos->f;
    idris2_pendingTailCall.arity = clos->arity;
    for (int i = 0; i < clos->filled; ++i)
      idris2_pendingTailCall.args[i] = idris2_newReference(clos->args[i]);
    idris2_pendingTailCall.args[clos->filled] = arg1;
    idris2_pendingTailCall.args[clos->filled + 1] = arg2;
    idris2_dropSharedReference((Idris2_Value *)clos);
    return IDRIS2_TAILCALL;
  }
  Idris2_Closure *newclos =
      idris2_mkClosure(clos->f, clos->arity, clos->filled + 2);
  for (int i = 0; i < clos->filled; ++i)
    newclos->args[i] = idris2_newReference(clos->args[i]);
  newclos->args[clos->filled] = arg1;
  newclos->args[clos->filled + 1] = arg2;
  idris2_dropSharedReference((Idris2_Value *)clos);
  return (Idris2_Value *)newclos;
}

Idris2_Value *idris2_apply_closure2(Idris2_Value *_clos, Idris2_Value *arg1,
                                    Idris2_Value *arg2) {
  Idris2_Closure *clos = (Idris2_Closure *)_clos;
  if (clos->filled + 2 == clos->arity &&
      clos->arity <= IDRIS2_MAX_TAILCALL_ARGS)
    return idris2_call_closure(clos, arg1, arg2, 2);
  return idris2_trampoline(idris2_tailcall_apply_closure2(_clos, arg1, arg2));
}

void idris2_removeReuseConstructor(Idris2_Constructor *constr) {
  if (!constr) {
    return;
  }
  IDRIS2_REFC_VERIFY(constr->header.refCounter > 0, "refCounter %lld",
                     (long long)constr->header.refCounter);
  constr->header.refCounter--;
  if (constr->header.refCounter == 0) {
    idris2_freeValue((Idris2_Value *)constr);
  }
}

int64_t idris2_extractInt64Boxed(Idris2_Value *v) {
  switch (v->header.tag) {
  case BITS32_TAG:
    return idris2_vp_to_Bits32(v);
  case BITS64_TAG:
    return (int64_t)idris2_vp_to_Bits64(v);
  case INT32_TAG:
    return idris2_vp_to_Int32(v);
  case INT64_TAG:
    return idris2_vp_to_Int64(v);
  case INTEGER_TAG:
    return mpz_get_si(((Idris2_Integer *)v)->i);
  case DOUBLE_TAG:
    return (int64_t)idris2_vp_to_Double(v);
  default:
    return -1;
  }
}

int idris2_extractInt(Idris2_Value *v) {
  if (idris2_vp_is_unboxed(v))
    return (int)((uintptr_t)(v) >> idris2_vp_int_shift);

  switch (v->header.tag) {
  case BITS32_TAG:
    return (int)idris2_vp_to_Bits32(v);
  case BITS64_TAG:
    return (int)idris2_vp_to_Bits64(v);
  case INT32_TAG:
    return (int)idris2_vp_to_Bits32(v);
  case INT64_TAG:
    return (int)idris2_vp_to_Int64(v);
  case INTEGER_TAG:
    return (int)mpz_get_si(((Idris2_Integer *)v)->i);
  case DOUBLE_TAG:
    return (int)idris2_vp_to_Double(v);
  default:
    return -1;
  }
}
