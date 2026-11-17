#pragma once

#include "cBackend.h"

void idris2_missing_ffi();

// May the value be updated in place?  Only when this is its only reference.
// A shared value (see memoryManagement.h) that has a single reference left
// is ours alone: it stops being shared first.
#define idris2_isUnique(x) (idris2_isUniqueValue((Idris2_Value *)(x)))
static inline int idris2_isUniqueValue(Idris2_Value *v) {
#ifdef IDRIS2_REFC_STATS
  int unique = idris2_isShared(v) ? idris2_tryUnshare(v)
                                  : v->header.refCounter == 1;
  if (unique)
    IDRIS2_STAT(uniqueHit);
  else
    IDRIS2_STAT(uniqueMiss);
  return unique;
#else
  if (__builtin_expect(idris2_isShared(v), 0))
    return idris2_tryUnshare(v);
  return v->header.refCounter == 1;
#endif
}
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
//
// The pending call is in the current worker (see worker.h).
#define idris2_pendingTailCall (idris2_worker()->tailcall)
extern Idris2_Value const idris2_tailCallMarker;
#define IDRIS2_TAILCALL ((Idris2_Value *)&idris2_tailCallMarker)

// A call in tail position that is a jump (see makeTailCall in RefC.idr):
// GCC 15 can make one even when the caller and the callee have different
// parameters (Clang requires them to be the same).
#if defined(__GNUC__) && !defined(__clang__) && __GNUC__ >= 15 &&             \
    !defined(__wasm__) && !defined(IDRIS2_NO_MUSTTAIL)
#define IDRIS2_MUSTTAIL __attribute__((musttail))
#endif

// The `return` of a value in a function that has calls that are jumps too
// (see `plainReturn` in RefC.idr): a statement that GCC takes to touch
// memory, and that is no code, stops its check of the jumps from walking
// back through the whole function from this `return`.
#if defined(IDRIS2_MUSTTAIL)
#define IDRIS2_PLAIN_RETURN __asm__ volatile("" ::: "memory");
#else
#define IDRIS2_PLAIN_RETURN
#endif

// How many arguments a function takes in registers: a call in tail position
// of a function with no more arguments than that can be a jump whatever the
// arguments of its caller are, as nothing is passed on the stack.
// (-DIDRIS2_MUSTTAIL_REG_ARGS=0 turns these jumps off.)
#if defined(IDRIS2_MUSTTAIL) && !defined(IDRIS2_MUSTTAIL_REG_ARGS)
#if defined(__x86_64__) && !defined(_WIN32)
#define IDRIS2_MUSTTAIL_REG_ARGS 6
#elif defined(__aarch64__) || (defined(__riscv) && __riscv_xlen == 64)
#define IDRIS2_MUSTTAIL_REG_ARGS 8
#else
#define IDRIS2_MUSTTAIL_REG_ARGS 0
#endif
#endif

// The application of a closure in tail position (see cStatementsFromANF in
// RefC.idr): a jump when the C compiler can make one, so that
// idris2_tailcall_apply_closure can itself jump to the function of the
// closure (see runtime.c) without the stack growing.
#if defined(IDRIS2_MUSTTAIL)
#define IDRIS2_TAIL_APPLY IDRIS2_MUSTTAIL
#else
#define IDRIS2_TAIL_APPLY
#endif

// Make the pending calls that `it` stands for: a pending tail call, or a
// closure that has all its arguments.  Most calls return a plain value or a
// partial application, so these cases are inlined.
Idris2_Value *idris2_trampolineSlow(Idris2_Value *it);
static inline Idris2_Value *idris2_trampoline(Idris2_Value *it) {
  if (it != IDRIS2_TAILCALL &&
      (!it || idris2_vp_is_unboxed(it) || it->header.tag != CLOSURE_TAG ||
       ((Idris2_Closure *)it)->filled < ((Idris2_Closure *)it)->arity))
    return it;
  return idris2_trampolineSlow(it);
}

// Run a `PrimIO` action to completion and return its result.  This consumes
// the reference to the action.
Idris2_Value *idris2_run_primio(Idris2_Closure *action);

// The integer in a value, for a `case` on integer constants.  An unboxed
// value is a signed (idris2_extractInt64) or an unsigned
// (idris2_extractUInt64) integer of up to 32 bits; the boxed ones are
// converted according to their type.
int64_t idris2_extractInt64Boxed(Idris2_Value *);
static inline int64_t idris2_extractInt64(Idris2_Value *v) {
  if (idris2_vp_is_unboxed(v))
    return (int32_t)((uintptr_t)(v) >> idris2_vp_int_shift);
  return idris2_extractInt64Boxed(v);
}
static inline int64_t idris2_extractUInt64(Idris2_Value *v) {
  if (idris2_vp_is_unboxed(v))
    return (uint32_t)((uintptr_t)(v) >> idris2_vp_int_shift);
  return idris2_extractInt64Boxed(v);
}

// ---------------------------------------------------------------------------
// Constants of the program
//
// A definition without arguments is evaluated once, the first time that it
// is needed (see createCFunctions in RefC.idr), and its value is kept for
// good: it is immortal, and shared (see memoryManagement.h) once several
// workers run.  Threads that need it while another one evaluates it wait.
// A constant that needs itself while it is evaluated is evaluated again
// (and that value is not kept).
// ---------------------------------------------------------------------------

typedef struct {
  Idris2_Value *value;
  int state;     // 0: not evaluated, 1: being evaluated, 2: evaluated
  int64_t maker; // the thread that evaluates it
} Idris2_Constant;

Idris2_Value *idris2_makeConstant(Idris2_Constant *c,
                                  Idris2_Value *(*make)(void));
static inline Idris2_Value *idris2_constantValue(Idris2_Constant *c,
                                                 Idris2_Value *(*make)(void)) {
  if (__atomic_load_n(&c->state, __ATOMIC_ACQUIRE) == 2)
    return c->value;
  return idris2_makeConstant(c, make);
}

// Make the constants evaluated so far shared (when the second worker starts).
void idris2_shareConstants(void);
