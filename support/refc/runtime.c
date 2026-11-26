#include "runtime.h"
#include "_datatypes.h"
#include "refc_util.h"

void idris2i_1_missing_ffi() {
  fprintf(stderr, "Foreign function declared, but not defined.\n"
                  "Cannot call missing FFI - aborting.\n");
  idris2i_1_backtracePrint();
  exit(1);
}

typedef Idris2i_1_Value *(*const FUN0)();
typedef Idris2i_1_Value *(*const FUN1)(Idris2i_1_Value *);
typedef Idris2i_1_Value *(*const FUN2)(Idris2i_1_Value *, Idris2i_1_Value *);
typedef Idris2i_1_Value *(*const FUN3)(Idris2i_1_Value *, Idris2i_1_Value *,
                                    Idris2i_1_Value *);
typedef Idris2i_1_Value *(*const FUN4)(Idris2i_1_Value *, Idris2i_1_Value *,
                                    Idris2i_1_Value *, Idris2i_1_Value *);
typedef Idris2i_1_Value *(*const FUN5)(Idris2i_1_Value *, Idris2i_1_Value *,
                                    Idris2i_1_Value *, Idris2i_1_Value *,
                                    Idris2i_1_Value *);
typedef Idris2i_1_Value *(*const FUN6)(Idris2i_1_Value *, Idris2i_1_Value *,
                                    Idris2i_1_Value *, Idris2i_1_Value *,
                                    Idris2i_1_Value *, Idris2i_1_Value *);
typedef Idris2i_1_Value *(*const FUN7)(Idris2i_1_Value *, Idris2i_1_Value *,
                                    Idris2i_1_Value *, Idris2i_1_Value *,
                                    Idris2i_1_Value *, Idris2i_1_Value *,
                                    Idris2i_1_Value *);
typedef Idris2i_1_Value *(*const FUN8)(Idris2i_1_Value *, Idris2i_1_Value *,
                                    Idris2i_1_Value *, Idris2i_1_Value *,
                                    Idris2i_1_Value *, Idris2i_1_Value *,
                                    Idris2i_1_Value *, Idris2i_1_Value *);
typedef Idris2i_1_Value *(*const FUN9)(Idris2i_1_Value *, Idris2i_1_Value *,
                                    Idris2i_1_Value *, Idris2i_1_Value *,
                                    Idris2i_1_Value *, Idris2i_1_Value *,
                                    Idris2i_1_Value *, Idris2i_1_Value *,
                                    Idris2i_1_Value *);
typedef Idris2i_1_Value *(*const FUN10)(Idris2i_1_Value *, Idris2i_1_Value *,
                                     Idris2i_1_Value *, Idris2i_1_Value *,
                                     Idris2i_1_Value *, Idris2i_1_Value *,
                                     Idris2i_1_Value *, Idris2i_1_Value *,
                                     Idris2i_1_Value *, Idris2i_1_Value *);
typedef Idris2i_1_Value *(*const FUN11)(Idris2i_1_Value *, Idris2i_1_Value *,
                                     Idris2i_1_Value *, Idris2i_1_Value *,
                                     Idris2i_1_Value *, Idris2i_1_Value *,
                                     Idris2i_1_Value *, Idris2i_1_Value *,
                                     Idris2i_1_Value *, Idris2i_1_Value *,
                                     Idris2i_1_Value *);
typedef Idris2i_1_Value *(*const FUN12)(Idris2i_1_Value *, Idris2i_1_Value *,
                                     Idris2i_1_Value *, Idris2i_1_Value *,
                                     Idris2i_1_Value *, Idris2i_1_Value *,
                                     Idris2i_1_Value *, Idris2i_1_Value *,
                                     Idris2i_1_Value *, Idris2i_1_Value *,
                                     Idris2i_1_Value *, Idris2i_1_Value *);
typedef Idris2i_1_Value *(*const FUN13)(Idris2i_1_Value *, Idris2i_1_Value *,
                                     Idris2i_1_Value *, Idris2i_1_Value *,
                                     Idris2i_1_Value *, Idris2i_1_Value *,
                                     Idris2i_1_Value *, Idris2i_1_Value *,
                                     Idris2i_1_Value *, Idris2i_1_Value *,
                                     Idris2i_1_Value *, Idris2i_1_Value *,
                                     Idris2i_1_Value *);
typedef Idris2i_1_Value *(*const FUN14)(Idris2i_1_Value *, Idris2i_1_Value *,
                                     Idris2i_1_Value *, Idris2i_1_Value *,
                                     Idris2i_1_Value *, Idris2i_1_Value *,
                                     Idris2i_1_Value *, Idris2i_1_Value *,
                                     Idris2i_1_Value *, Idris2i_1_Value *,
                                     Idris2i_1_Value *, Idris2i_1_Value *,
                                     Idris2i_1_Value *, Idris2i_1_Value *);
typedef Idris2i_1_Value *(*const FUN15)(
    Idris2i_1_Value *, Idris2i_1_Value *, Idris2i_1_Value *, Idris2i_1_Value *,
    Idris2i_1_Value *, Idris2i_1_Value *, Idris2i_1_Value *, Idris2i_1_Value *,
    Idris2i_1_Value *, Idris2i_1_Value *, Idris2i_1_Value *, Idris2i_1_Value *,
    Idris2i_1_Value *, Idris2i_1_Value *, Idris2i_1_Value *);
typedef Idris2i_1_Value *(*const FUN16)(
    Idris2i_1_Value *, Idris2i_1_Value *, Idris2i_1_Value *, Idris2i_1_Value *,
    Idris2i_1_Value *, Idris2i_1_Value *, Idris2i_1_Value *, Idris2i_1_Value *,
    Idris2i_1_Value *, Idris2i_1_Value *, Idris2i_1_Value *, Idris2i_1_Value *,
    Idris2i_1_Value *, Idris2i_1_Value *, Idris2i_1_Value *, Idris2i_1_Value *);
typedef Idris2i_1_Value *(*const FUNStar)(Idris2i_1_Value **);

// Call the function `f` of the given arity with the arguments in xs.
// (Inlined into its callers, which saves a call per closure application.)
IDRIS2I_1_INLINE Idris2i_1_Value *idris2i_1_dispatch(void *f, int arity,
                                            Idris2i_1_Value **const xs) {
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

Idris2i_1_Value const idris2i_1_tailCallMarker = {IDRIS2I_1_STOCKVAL(NO_TAG)};

// Call a shared closure that `n` more arguments complete.  Other threads may
// use the closure at the same time, so the arguments go in an array of our
// own rather than in the room of the closure.  Consumes the reference to the
// closure.  The result is not trampolined.
static Idris2i_1_Value *idris2i_1_call_shared_closure(Idris2i_1_Closure *clos, int n,
                                                Idris2i_1_Value *arg1,
                                                Idris2i_1_Value *arg2) {
  IDRIS2I_1_STAT(apply[IDRIS2I_1_APPLY_SHARED]);
  Idris2i_1_Value *small[IDRIS2I_1_MAX_TAILCALL_ARGS];
  Idris2i_1_Value **xs = small;
  if (clos->arity > IDRIS2I_1_MAX_TAILCALL_ARGS) {
    xs = malloc(sizeof(Idris2i_1_Value *) * clos->arity);
    IDRIS2I_1_REFC_VERIFY(xs, "malloc failed");
  }
  int filled = clos->filled;
  for (int i = 0; i < filled; ++i)
    xs[i] = idris2i_1_newReference(clos->args[i]);
  if (n >= 1)
    xs[filled] = arg1;
  if (n == 2)
    xs[filled + 1] = arg2;
  void *f = clos->f;
  int arity = clos->arity;
  idris2i_1_removeReference((Idris2i_1_Value *)clos);
  Idris2i_1_Value *r = idris2i_1_dispatch(f, arity, xs);
  if (xs != small)
    free(xs);
  return r;
}

Idris2i_1_Value *idris2i_1_trampolineSlow(Idris2i_1_Value *it) {
  for (;;) {
    if (it == IDRIS2I_1_TAILCALL) {
      // The arguments are read before the call, which may store another
      // tail call.
      Idris2i_1_PendingTailCall *pending = &idris2i_1_pendingTailCall;
      it = idris2i_1_dispatch(pending->f, pending->arity, pending->args);
      continue;
    }
    if (!it || idris2i_1_vp_is_unboxed(it) || it->header.tag != CLOSURE_TAG)
      break;
    Idris2i_1_Closure *clos = (Idris2i_1_Closure *)it;
    if (clos->filled < clos->arity)
      break;
    // (the call is in the closure, not in the worker: we may switch here)
    IDRIS2I_1_SAFEPOINT();

    if (idris2i_1_isShared(clos) && !idris2i_1_tryUnshare((Idris2i_1_Value *)clos)) {
      it = idris2i_1_call_shared_closure(clos, 0, NULL, NULL);
      continue;
    }
    // The call consumes the arguments: when another reference to the closure
    // remains, it keeps its own (as in idris2i_1_call_closure).
    int unique = idris2i_1_isUnique(clos);
    if (unique)
      IDRIS2I_1_STAT(apply[IDRIS2I_1_APPLY_SATURATED]);
    else
      IDRIS2I_1_STAT(apply[IDRIS2I_1_APPLY_COPIED]);
    if (!unique)
      for (int i = 0; i < clos->filled; ++i)
        idris2i_1_newReference(clos->args[i]);
    it = idris2i_1_dispatch(clos->f, clos->arity, clos->args);
    if (unique)
      idris2i_1_freeValue((Idris2i_1_Value *)clos);
    else
      idris2i_1_removeReference((Idris2i_1_Value *)clos);
  }
  return it;
}

// A `PrimIO` action is a closure waiting for its %World argument.  The world
// is not represented at runtime, so it is passed as NULL.  Applying it
// consumes the reference to the action (see idris2i_1_tailcall_apply_closure).
Idris2i_1_Value *idris2i_1_run_primio(Idris2i_1_Closure *action) {
  if (!action) {
    return NULL;
  }
  return idris2i_1_trampoline(
      idris2i_1_tailcall_apply_closure((Idris2i_1_Value *)action, NULL));
}

// A closure that `n` more arguments (arg1, then arg2) complete, in tail
// position, when calls in tail position can be jumps (IDRIS2I_1_MUSTTAIL, see
// runtime.h): the function is called directly, its frame replacing this one,
// rather than through the trampoline of the caller.  Only for functions that
// take their arguments in registers (IDRIS2I_1_MUSTTAIL_REG_ARGS: 6 on x86-64,
// 4 on Windows, 8 on AArch64; up to 6 here), or that take no more arguments
// than idris2i_1_tailcall_apply_closure (2): a jump to a function that takes
// more arguments than its caller on the stack is not possible, and GCC
// refuses to compile one.  The generated code calls
// idris2i_1_tailcall_apply_closure in tail position with a jump too, so a loop
// through closures runs in constant stack.
//
// The arguments are read and the reference to the closure dropped first:
// the closure is gone once the call starts.
#if defined(IDRIS2I_1_MUSTTAIL)
#if IDRIS2I_1_MUSTTAIL_REG_ARGS >= 6
#define IDRIS2I_1_JUMP_MAX_ARGS 6
#elif IDRIS2I_1_MUSTTAIL_REG_ARGS > 2
#define IDRIS2I_1_JUMP_MAX_ARGS IDRIS2I_1_MUSTTAIL_REG_ARGS
#else
#define IDRIS2I_1_JUMP_MAX_ARGS 2
#endif
// The jumps to the functions with 3 to 6 arguments, where they are possible.
#if IDRIS2I_1_JUMP_MAX_ARGS >= 3
#define IDRIS2I_1_JUMP_3                                                          \
  case 3:                                                                      \
    IDRIS2I_1_MUSTTAIL return (*(FUN3)f_)(x0_, x1_, x2_);
#else
#define IDRIS2I_1_JUMP_3
#endif
#if IDRIS2I_1_JUMP_MAX_ARGS >= 4
#define IDRIS2I_1_JUMP_4                                                          \
  case 4:                                                                      \
    IDRIS2I_1_MUSTTAIL return (*(FUN4)f_)(x0_, x1_, x2_, x3_);
#else
#define IDRIS2I_1_JUMP_4
#endif
#if IDRIS2I_1_JUMP_MAX_ARGS >= 5
#define IDRIS2I_1_JUMP_5                                                          \
  case 5:                                                                      \
    IDRIS2I_1_MUSTTAIL return (*(FUN5)f_)(x0_, x1_, x2_, x3_, x4_);
#else
#define IDRIS2I_1_JUMP_5
#endif
#if IDRIS2I_1_JUMP_MAX_ARGS >= 6
#define IDRIS2I_1_JUMP_6                                                          \
  case 6:                                                                      \
    IDRIS2I_1_MUSTTAIL return (*(FUN6)f_)(x0_, x1_, x2_, x3_, x4_, x5_);
#else
#define IDRIS2I_1_JUMP_6
#endif
#define IDRIS2I_1_JUMP_TO_CLOSURE(clos, n, arg1, arg2)                           \
  do {                                                                         \
    int arity_ = (clos)->arity;                                                \
    if (arity_ <= IDRIS2I_1_JUMP_MAX_ARGS && !idris2i_1_isShared(clos)) {            \
      IDRIS2I_1_SAFEPOINT();                                                      \
      int filled_ = (clos)->filled;                                            \
      Idris2i_1_Value *a_[6 + 2];                                                 \
      int unique_ = (clos)->header.refCounter == 1;                            \
      IDRIS2I_1_STAT_UNIQUE(clos, unique_);                                       \
      for (int i_ = 0; i_ < filled_; ++i_)                                     \
        a_[i_] = unique_ ? (clos)->args[i_]                                    \
                         : idris2i_1_newReference((clos)->args[i_]);              \
      a_[filled_] = (arg1);                                                    \
      a_[filled_ + 1] = (arg2);                                                \
      void *f_ = (clos)->f;                                                    \
      if (unique_) {                                                           \
        IDRIS2I_1_STAT(apply[IDRIS2I_1_APPLY_SATURATED]);                            \
        idris2i_1_freeValue((Idris2i_1_Value *)(clos));                              \
      } else {                                                                 \
        IDRIS2I_1_STAT(apply[IDRIS2I_1_APPLY_COPIED]);                               \
        idris2i_1_dropSharedReference((Idris2i_1_Value *)(clos));                    \
      }                                                                        \
      Idris2i_1_Value *x0_ = a_[0], *x1_ = a_[1], *x2_ = a_[2], *x3_ = a_[3],     \
                   *x4_ = a_[4], *x5_ = a_[5];                                 \
      (void)x2_, (void)x3_, (void)x4_, (void)x5_;                              \
      switch (arity_) {                                                        \
      case 1:                                                                  \
        IDRIS2I_1_MUSTTAIL return (*(FUN1)f_)(x0_);                               \
      case 2:                                                                  \
        IDRIS2I_1_MUSTTAIL return (*(FUN2)f_)(x0_, x1_);                          \
        IDRIS2I_1_JUMP_3                                                          \
        IDRIS2I_1_JUMP_4                                                          \
        IDRIS2I_1_JUMP_5                                                          \
        IDRIS2I_1_JUMP_6                                                          \
      default: /* (a closure takes at least one argument) */                   \
        __builtin_unreachable();                                               \
      }                                                                        \
    }                                                                          \
  } while (0)
#endif

Idris2i_1_Value *idris2i_1_tailcall_apply_closure(Idris2i_1_Value *_clos,
                                            Idris2i_1_Value *arg) {
  Idris2i_1_Closure *clos = (Idris2i_1_Closure *)_clos;
  int filled = clos->filled;
  if (filled + 1 == clos->arity) {
#if defined(IDRIS2I_1_MUSTTAIL)
    IDRIS2I_1_JUMP_TO_CLOSURE(clos, 1, arg, NULL);
#endif
  } else if (filled < clos->arity && idris2i_1_isUnique(clos)) {
    // A closure has room for all its arguments (see idris2i_1_mkClosure): when
    // nobody else refers to it, the argument goes in place.
    clos->args[clos->filled++] = arg;
    IDRIS2I_1_STAT(apply[IDRIS2I_1_APPLY_IN_PLACE]);
    return (Idris2i_1_Value *)clos;
  }
  if (filled + 1 == clos->arity && idris2i_1_isUnique(clos)) {
    // Complete it in place: the trampoline of the caller makes the call.
    clos->args[clos->filled++] = arg;
    return (Idris2i_1_Value *)clos;
  }

  // The argument completes a closure that is shared: make the call a pending
  // tail call (see runtime.h) rather than a copy of the closure that would be
  // called and freed right away.  The result goes through a trampoline, as
  // for any call in tail position.
  if (filled + 1 == clos->arity && clos->arity <= IDRIS2I_1_MAX_TAILCALL_ARGS) {
    Idris2i_1_PendingTailCall *pending = &idris2i_1_pendingTailCall;
    pending->f = clos->f;
    pending->arity = clos->arity;
    for (int i = 0; i < filled; ++i)
      pending->args[i] = idris2i_1_newReference(clos->args[i]);
    pending->args[filled] = arg;
    idris2i_1_dropSharedReference((Idris2i_1_Value *)clos);
    IDRIS2I_1_STAT(apply[IDRIS2I_1_APPLY_COPIED]);
    return IDRIS2I_1_TAILCALL;
  }

  // Otherwise create a new closure and copy args.
  Idris2i_1_Closure *newclos = idris2i_1_mkClosure(
      clos->f, clos->arity, filled + 1 /* expanding a payload */);

  // (a unique closure was completed in place above, so this one is shared)
  for (int i = 0; i < filled; ++i)
    newclos->args[i] = idris2i_1_newReference(clos->args[i]);
  newclos->args[filled] = arg; // add argument to new arglist
  idris2i_1_dropSharedReference((Idris2i_1_Value *)clos);
  IDRIS2I_1_STAT(apply[IDRIS2I_1_APPLY_UNDER_COPY]);

  return (Idris2i_1_Value *)newclos;
}

// Call a closure that `n` more arguments complete (not in tail position):
// directly, rather than through a pending tail call and the trampoline.  The
// arguments go in the room of the closure (see idris2i_1_mkClosure), which the
// call reads at once; no copy is made, so that this frame, which stays on the
// stack during the call, is small.  (Inlined: with the dispatch, this saves
// two calls per application.)
IDRIS2I_1_INLINE Idris2i_1_Value *idris2i_1_call_closure(Idris2i_1_Closure *clos,
                                                Idris2i_1_Value *arg1,
                                                Idris2i_1_Value *arg2, int n) {
  int filled = clos->filled;
  if (filled == 0) {
    // Nothing to take from the closure (which has no room for arguments when
    // it is static, see IDRIS2I_1_STATIC_CLOSURE): the arguments are passed as
    // they are.
    void *f = clos->f;
    IDRIS2I_1_STAT(apply[IDRIS2I_1_APPLY_SATURATED]);
    IDRIS2I_1_STAT_UNIQUE(clos, !idris2i_1_isShared(clos) &&
                                 clos->header.refCounter == 1);
    if (!idris2i_1_isShared(clos) && clos->header.refCounter == 1)
      idris2i_1_freeValue((Idris2i_1_Value *)clos);
    else
      idris2i_1_removeReference((Idris2i_1_Value *)clos);
    return idris2i_1_trampoline(n == 1 ? (*(FUN1)f)(arg1)
                                    : (*(FUN2)f)(arg1, arg2));
  }
  int unique;
  if (__builtin_expect(idris2i_1_isShared(clos), 0)) {
    if (!idris2i_1_tryUnshare((Idris2i_1_Value *)clos))
      return idris2i_1_trampoline(idris2i_1_call_shared_closure(clos, n, arg1, arg2));
    unique = 1;
  } else {
    unique = clos->header.refCounter == 1;
  }
  IDRIS2I_1_STAT_UNIQUE(clos, unique);
  if (unique) {
    IDRIS2I_1_STAT(apply[IDRIS2I_1_APPLY_SATURATED]);
  } else {
    IDRIS2I_1_STAT(apply[IDRIS2I_1_APPLY_COPIED]);
    for (int i = 0; i < filled; ++i)
      idris2i_1_newReference(clos->args[i]);
  }
  clos->args[filled] = arg1;
  if (n == 2)
    clos->args[filled + 1] = arg2;
  Idris2i_1_Value *r = idris2i_1_dispatch(clos->f, clos->arity, clos->args);
  // The arguments were given to the call: only the closure is released.
  if (unique)
    idris2i_1_freeValue((Idris2i_1_Value *)clos);
  else
    idris2i_1_removeReference((Idris2i_1_Value *)clos);
  return idris2i_1_trampoline(r);
}

Idris2i_1_Value *idris2i_1_apply_closure(Idris2i_1_Value *_clos, Idris2i_1_Value *arg) {
  Idris2i_1_Closure *clos = (Idris2i_1_Closure *)_clos;
  if (__builtin_expect(clos->filled + 1 == clos->arity, 1) &&
      clos->arity <= IDRIS2I_1_MAX_TAILCALL_ARGS)
    return idris2i_1_call_closure(clos, arg, NULL, 1);
  return idris2i_1_trampoline(idris2i_1_tailcall_apply_closure(_clos, arg));
}

// Apply a closure to two arguments, like idris2i_1_tailcall_apply_closure
// twice, but without the partial application in between when both
// arguments go to the closure.
Idris2i_1_Value *idris2i_1_tailcall_apply_closure2(Idris2i_1_Value *_clos,
                                             Idris2i_1_Value *arg1,
                                             Idris2i_1_Value *arg2) {
  Idris2i_1_Closure *clos = (Idris2i_1_Closure *)_clos;
  if (clos->filled + 2 > clos->arity) {
    // The closure takes one more argument: apply its result to the other.
    return idris2i_1_tailcall_apply_closure(idris2i_1_apply_closure(_clos, arg1),
                                         arg2);
  }
#if defined(IDRIS2I_1_MUSTTAIL)
  if (clos->filled + 2 == clos->arity)
    IDRIS2I_1_JUMP_TO_CLOSURE(clos, 2, arg1, arg2);
#endif
  if (idris2i_1_isUnique(clos)) {
    clos->args[clos->filled++] = arg1;
    clos->args[clos->filled++] = arg2;
#ifdef IDRIS2I_1_REFC_STATS
    if (clos->filled < clos->arity)
      IDRIS2I_1_STAT(apply[IDRIS2I_1_APPLY_IN_PLACE]);
#endif
    return (Idris2i_1_Value *)clos;
  }
  if (clos->filled + 2 == clos->arity &&
      clos->arity <= IDRIS2I_1_MAX_TAILCALL_ARGS) {
    Idris2i_1_PendingTailCall *pending = &idris2i_1_pendingTailCall;
    pending->f = clos->f;
    pending->arity = clos->arity;
    for (int i = 0; i < clos->filled; ++i)
      pending->args[i] = idris2i_1_newReference(clos->args[i]);
    pending->args[clos->filled] = arg1;
    pending->args[clos->filled + 1] = arg2;
    idris2i_1_dropSharedReference((Idris2i_1_Value *)clos);
    IDRIS2I_1_STAT(apply[IDRIS2I_1_APPLY_COPIED]);
    return IDRIS2I_1_TAILCALL;
  }
  Idris2i_1_Closure *newclos =
      idris2i_1_mkClosure(clos->f, clos->arity, clos->filled + 2);
  for (int i = 0; i < clos->filled; ++i)
    newclos->args[i] = idris2i_1_newReference(clos->args[i]);
  newclos->args[clos->filled] = arg1;
  newclos->args[clos->filled + 1] = arg2;
  idris2i_1_dropSharedReference((Idris2i_1_Value *)clos);
  IDRIS2I_1_STAT(apply[IDRIS2I_1_APPLY_UNDER_COPY]);
  return (Idris2i_1_Value *)newclos;
}

Idris2i_1_Value *idris2i_1_apply_closure2(Idris2i_1_Value *_clos, Idris2i_1_Value *arg1,
                                    Idris2i_1_Value *arg2) {
  Idris2i_1_Closure *clos = (Idris2i_1_Closure *)_clos;
  if (__builtin_expect(clos->filled + 2 == clos->arity, 1) &&
      clos->arity <= IDRIS2I_1_MAX_TAILCALL_ARGS)
    return idris2i_1_call_closure(clos, arg1, arg2, 2);
  return idris2i_1_trampoline(idris2i_1_tailcall_apply_closure2(_clos, arg1, arg2));
}

void idris2i_1_removeReuseConstructor(Idris2i_1_Constructor *constr) {
  if (!constr) {
    return;
  }
  IDRIS2I_1_REFC_VERIFY(constr->header.refCounter > 0, "refCounter %lld",
                     (long long)constr->header.refCounter);
  IDRIS2I_1_STAT_REAL(drops, constr);
  constr->header.refCounter--;
  if (constr->header.refCounter == 0) {
    IDRIS2I_1_STAT_KIND(released, IDRIS2I_1_KIND_CONSTRUCTOR);
    idris2i_1_freeValue((Idris2i_1_Value *)constr);
  }
}

int64_t idris2i_1_extractInt64Boxed(Idris2i_1_Value *v) {
  switch (v->header.tag) {
  case BITS32_TAG:
    return idris2i_1_vp_to_Bits32(v);
  case BITS64_TAG:
    return (int64_t)idris2i_1_vp_to_Bits64(v);
  case INT32_TAG:
    return idris2i_1_vp_to_Int32(v);
  case INT64_TAG:
    return idris2i_1_vp_to_Int64(v);
  case INTEGER_TAG: {
#if LONG_MAX >= INT64_MAX
    return mpz_get_si(((Idris2i_1_Integer *)v)->i);
#else
    // (a `long` has 32 bits)
    mpz_srcptr z = ((Idris2i_1_Integer *)v)->i;
    uint64_t n = idris2i_1_mpzLow64(z);
    return (int64_t)(mpz_sgn(z) < 0 ? -n : n);
#endif
  }
  case DOUBLE_TAG:
    return (int64_t)idris2i_1_vp_to_Double(v);
  default:
    return -1;
  }
}

// ---------------------------------------------------------------------------
// Constants of the program (see runtime.h)
// ---------------------------------------------------------------------------

// The constants evaluated while there is a single worker, to be made shared
// when the others start.  (Only the main worker touches this list.)
static Idris2i_1_Value **unshared_constants = NULL;
static size_t n_unshared_constants = 0, unshared_capacity = 0;

// idris2i_1_markShared, set by idris2i_1_shareConstants: a program that never
// starts a second worker does not link it.
static void (*mark_shared)(Idris2i_1_Value *) = NULL;

static void publish_constant(Idris2i_1_Value *v) {
  if (!v || idris2i_1_vp_is_unboxed(v))
    return;
  if (__atomic_load_n(&idris2i_1_multicoreStarted, __ATOMIC_ACQUIRE)) {
    mark_shared(v);
    return;
  }
  if (n_unshared_constants == unshared_capacity) {
    size_t capacity = unshared_capacity ? 2 * unshared_capacity : 256;
    Idris2i_1_Value **bigger = (Idris2i_1_Value **)realloc(
        unshared_constants, capacity * sizeof(Idris2i_1_Value *));
    IDRIS2I_1_REFC_VERIFY(bigger, "malloc failed");
    unshared_constants = bigger;
    unshared_capacity = capacity;
  }
  unshared_constants[n_unshared_constants++] = v;
}

void idris2i_1_shareConstants(void) {
  mark_shared = idris2i_1_markShared;
  for (size_t i = 0; i < n_unshared_constants; i++)
    idris2i_1_markShared(unshared_constants[i]);
  free(unshared_constants);
  unshared_constants = NULL;
  n_unshared_constants = unshared_capacity = 0;
}

Idris2i_1_Value *idris2i_1_makeConstant(Idris2i_1_Constant *c,
                                  Idris2i_1_Value *(*make)(void)) {
  // A thread claims the constant by writing its identifier (plus one) into
  // `maker`, in one atomic step, so that a thread that finds the constant
  // claimed knows by whom.  (Were the claim and the identifier written one
  // after the other, the main thread, whose identifier is 0, could see the
  // claim of another thread before its identifier, take itself for the
  // maker, and evaluate a copy of its own: another IORef, say, than the one
  // that the other threads get.)
  int64_t me = idris2i_1_threadId(idris2i_1_currentThread()) + 1;
  for (;;) {
    int64_t maker = 0;
    if (__atomic_compare_exchange_n(&c->maker, &maker, me, 0,
                                    __ATOMIC_ACQ_REL, __ATOMIC_ACQUIRE)) {
      // The claim is given back if the evaluation crashes into a crash
      // boundary (see crash.c).
      Idris2i_1_CrashState *cs = idris2i_1_crashState();
      Idris2i_1_ConstantClaim claim = {NULL, &c->maker};
      if (cs) {
        claim.prev = cs->constants;
        cs->constants = &claim;
      }
      Idris2i_1_Value *v = idris2i_1_makeImmortal(idris2i_1_trampoline(make()));
      if (cs)
        cs->constants = claim.prev;
      publish_constant(v);
      c->value = v;
      __atomic_store_n(&c->state, 2, __ATOMIC_RELEASE);
      return v;
    }
    if (__atomic_load_n(&c->state, __ATOMIC_ACQUIRE) == 2)
      return c->value;
    if (maker == me) {
      // The constant needs itself: evaluate it again, as when constants
      // were not kept.  This value is an ordinary one, owned by the caller
      // (as any result), which releases it once it is done with it: only
      // the value of the outer evaluation is kept.
      return idris2i_1_trampoline(make());
    }
    // Another thread evaluates it (until it is done, or until its
    // evaluation crashed and it gave it back).
    while (__atomic_load_n(&c->state, __ATOMIC_ACQUIRE) != 2 &&
           __atomic_load_n(&c->maker, __ATOMIC_ACQUIRE) != 0) {
      idris2i_1_threadYield();
      idris2i_1_cpuRelax();
    }
    if (__atomic_load_n(&c->state, __ATOMIC_ACQUIRE) == 2)
      return c->value;
  }
}
