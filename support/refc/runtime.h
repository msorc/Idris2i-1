#pragma once

#include "cBackend.h"

void idris2i_1_missing_ffi();

// The branch that is taken almost always (for the C compiler's layout).
#if defined(__GNUC__)
#define IDRIS2I_1_LIKELY(c) __builtin_expect(!!(c), 1)
#else
#define IDRIS2I_1_LIKELY(c) (c)
#endif

// May the value be updated in place?  Only when this is its only reference.
// A shared value (see memoryManagement.h) that has a single reference left
// is ours alone: it stops being shared first.
#define idris2i_1_isUnique(x) (idris2i_1_isUniqueValue((Idris2i_1_Value *)(x)))
static inline int idris2i_1_isUniqueValue(Idris2i_1_Value *v) {
#ifdef IDRIS2I_1_REFC_STATS
  int unique = idris2i_1_isShared(v) ? idris2i_1_tryUnshare(v)
                                  : v->header.refCounter == 1;
  IDRIS2I_1_STAT_UNIQUE(v, unique);
  return unique;
#else
  if (__builtin_expect(idris2i_1_isShared(v), 0))
    return idris2i_1_tryUnshare(v);
  return v->header.refCounter == 1;
#endif
}
void idris2i_1_removeReuseConstructor(Idris2i_1_Constructor *constr);

Idris2i_1_Value *idris2i_1_apply_closure(Idris2i_1_Value *, Idris2i_1_Value *arg);
Idris2i_1_Value *idris2i_1_tailcall_apply_closure(Idris2i_1_Value *_clos,
                                            Idris2i_1_Value *arg);
Idris2i_1_Value *idris2i_1_apply_closure2(Idris2i_1_Value *, Idris2i_1_Value *arg1,
                                    Idris2i_1_Value *arg2);
Idris2i_1_Value *idris2i_1_tailcall_apply_closure2(Idris2i_1_Value *_clos,
                                             Idris2i_1_Value *arg1,
                                             Idris2i_1_Value *arg2);

// A call in tail position does not allocate a closure: the function stores
// the call in idris2i_1_pendingTailCall and returns IDRIS2I_1_TAILCALL, which the
// trampoline of its caller makes.  Nothing can run in between but the release
// of values; the finaliser of a GC pointer saves and restores the pending
// call (see idris2i_1_releaseValue).
//
// The pending call is in the current worker (see worker.h).
#define idris2i_1_pendingTailCall (idris2i_1_worker()->tailcall)
extern Idris2i_1_Value const idris2i_1_tailCallMarker;
#define IDRIS2I_1_TAILCALL ((Idris2i_1_Value *)&idris2i_1_tailCallMarker)

// A call in tail position that is a jump (see makeTailCall in RefC.idr):
// GCC 15 can make one even when the caller and the callee have different
// parameters (Clang requires them to be the same).
//
// Not on 32 bit x86 and ARM: the jump needs the arguments of the callee to
// fit where the caller got its own.  x86 passes every argument on the stack
// and ARM all but four, so a function cannot jump to one that takes more
// arguments than it does, which the runtime does for closures (see
// IDRIS2I_1_JUMP_TO_CLOSURE in runtime.c) and the generated code when it applies
// one (IDRIS2I_1_TAIL_APPLY): GCC refuses to compile such a call ("cannot
// tail-call: target is not able to optimize the call into a sibling call").
// The calls in tail position go through the trampoline there.
//
// Nor on other platforms with 32 bit pointers: the workers of the functions
// take 64 bit integers (see `Worker` in RefC.idr), which take two registers
// there, where the caller got one for a value.
#if defined(__GNUC__) && !defined(__clang__) && __GNUC__ >= 15 &&             \
    !defined(__wasm__) && !defined(__i386__) && !defined(__arm__) &&           \
    defined(__SIZEOF_POINTER__) && __SIZEOF_POINTER__ == 8 &&                 \
    !defined(IDRIS2I_1_NO_MUSTTAIL)
#define IDRIS2I_1_MUSTTAIL __attribute__((musttail))
#endif

// The `return` of a value in a function that has calls that are jumps too
// (see `plainReturn` in RefC.idr): a statement that GCC takes to touch
// memory, and that is no code, stops its check of the jumps from walking
// back through the whole function from this `return`.
#if defined(IDRIS2I_1_MUSTTAIL)
#define IDRIS2I_1_PLAIN_RETURN __asm__ volatile("" ::: "memory");
#else
#define IDRIS2I_1_PLAIN_RETURN
#endif

// How many arguments a function takes in registers: a call in tail position
// of a function with no more arguments than that can be a jump whatever the
// arguments of its caller are, as nothing is passed on the stack.
// (-DIDRIS2I_1_MUSTTAIL_REG_ARGS=0 turns these jumps off.)  The x86-64 ABI of
// Windows (also used by Cygwin) passes four arguments in registers, and the
// caller always reserves room for them on the stack.
#if defined(IDRIS2I_1_MUSTTAIL) && !defined(IDRIS2I_1_MUSTTAIL_REG_ARGS)
#if defined(__x86_64__) && (defined(_WIN32) || defined(__CYGWIN__))
#define IDRIS2I_1_MUSTTAIL_REG_ARGS 4
#elif defined(__x86_64__)
#define IDRIS2I_1_MUSTTAIL_REG_ARGS 6
#elif defined(__aarch64__) || (defined(__riscv) && __riscv_xlen == 64)
#define IDRIS2I_1_MUSTTAIL_REG_ARGS 8
#else
#define IDRIS2I_1_MUSTTAIL_REG_ARGS 0
#endif
#endif

// The application of a closure in tail position (see cStatementsFromANF in
// RefC.idr): a jump when the C compiler can make one, so that
// idris2i_1_tailcall_apply_closure can itself jump to the function of the
// closure (see runtime.c) without the stack growing.
#if defined(IDRIS2I_1_MUSTTAIL)
#define IDRIS2I_1_TAIL_APPLY IDRIS2I_1_MUSTTAIL
#else
#define IDRIS2I_1_TAIL_APPLY
#endif

// Make the pending calls that `it` stands for: a pending tail call, or a
// closure that has all its arguments.  Most calls return a plain value or a
// partial application, so these cases are inlined.
Idris2i_1_Value *idris2i_1_trampolineSlow(Idris2i_1_Value *it);
static inline Idris2i_1_Value *idris2i_1_trampoline(Idris2i_1_Value *it) {
  if (it != IDRIS2I_1_TAILCALL &&
      (!it || idris2i_1_vp_is_unboxed(it) || it->header.tag != CLOSURE_TAG ||
       ((Idris2i_1_Closure *)it)->filled < ((Idris2i_1_Closure *)it)->arity))
    return it;
  return idris2i_1_trampolineSlow(it);
}

// Run a `PrimIO` action to completion and return its result.  This consumes
// the reference to the action.
Idris2i_1_Value *idris2i_1_run_primio(Idris2i_1_Closure *action);

// The integer in a value, for a `case` on integer constants.  An unboxed
// value is a signed (idris2i_1_extractInt64) or an unsigned
// (idris2i_1_extractUInt64) integer of up to 32 bits; the boxed ones are
// converted according to their type.
int64_t idris2i_1_extractInt64Boxed(Idris2i_1_Value *);
static inline int64_t idris2i_1_extractInt64(Idris2i_1_Value *v) {
  if (idris2i_1_vp_is_unboxed(v))
    return (int32_t)((uintptr_t)(v) >> idris2i_1_vp_int_shift);
  return idris2i_1_extractInt64Boxed(v);
}
static inline int64_t idris2i_1_extractUInt64(Idris2i_1_Value *v) {
  if (idris2i_1_vp_is_unboxed(v))
    return (uint32_t)((uintptr_t)(v) >> idris2i_1_vp_int_shift);
  return idris2i_1_extractInt64Boxed(v);
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

// The generated code declares the constants as zero-initialised statics.
typedef struct {
  Idris2i_1_Value *value;
  int state;     // 2 once evaluated (0 before)
  int64_t maker; // the identifier plus one of the thread that evaluates it,
                 // 0 until a thread starts
} Idris2i_1_Constant;

Idris2i_1_Value *idris2i_1_makeConstant(Idris2i_1_Constant *c,
                                  Idris2i_1_Value *(*make)(void));
static inline Idris2i_1_Value *idris2i_1_constantValue(Idris2i_1_Constant *c,
                                                 Idris2i_1_Value *(*make)(void)) {
  if (__atomic_load_n(&c->state, __ATOMIC_ACQUIRE) == 2)
    return c->value;
  return idris2i_1_makeConstant(c, make);
}

// Make the constants evaluated so far shared, and those evaluated from now on
// (on the main worker, when the second worker is about to start).
void idris2i_1_shareConstants(void);
