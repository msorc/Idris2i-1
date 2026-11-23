#pragma once

// ---------------------------------------------------------------------------
// Crash boundaries (see crash.c and System.Crash in base)
//
// `catchCrash act` runs `act` so that a crash of the code of the thread
// inside it (`idris_crash`, a missing case, a failed check of the runtime
// such as an access out of a Buffer) ends `act` instead of the program.
// ---------------------------------------------------------------------------

#include "_datatypes.h"

#include <stddef.h>
#include <stdint.h>

// The kinds of crash (the constructors of System.Crash.CrashKind).
#define IDRIS2_CRASH_CALL 0         // idris_crash
#define IDRIS2_CRASH_MISSING_CASE 1 // compiled code with no clause, a hole
#define IDRIS2_CRASH_FAILED_CHECK 2 // a check of the runtime failed

// What a boundary keeps of a crash: allocated with malloc, in the thread
// until the next boundary of the thread ends with a crash, or until the
// code of System.Crash has read it (idris2_crashClear).
typedef struct {
  int kind;
  char *message; // (NUL-terminated too)
  size_t messageLen;
  char *backtrace; // NULL when backtraces are off
} Idris2_CrashInfo;

typedef struct Idris2_CrashFrame Idris2_CrashFrame;

// A constant that a thread evaluates (see idris2_makeConstant): a crash
// gives it back to the other threads.
typedef struct Idris2_ConstantClaim {
  struct Idris2_ConstantClaim *prev;
  int64_t *maker;
} Idris2_ConstantClaim;

// The state of a green thread that the boundaries need (in the thread, see
// threads.c; all zero for a new thread).
typedef struct {
  // The innermost boundary of the thread, NULL if there is none.
  Idris2_CrashFrame *frame;
  // The number of finalisers that the thread runs now (a crash in a
  // finaliser is fatal, see crash.c).
  int finalisers;
  // The constants that the thread evaluates now, the innermost first.
  Idris2_ConstantClaim *constants;
  // The crash that the last boundary caught, until it is read.
  Idris2_CrashInfo *caught;
} Idris2_CrashState;

// The crash state of the thread that runs, NULL in the scheduler.
Idris2_CrashState *idris2_crashState(void);

// Is there a boundary that a crash of the running code may end at?
int idris2_crashCatchable(void);

// End the innermost boundary of the thread with this crash (`len` bytes of
// `msg`).  Only when idris2_crashCatchable() says so.
#if defined(__GNUC__) || defined(__clang__)
__attribute__((__noreturn__, __cold__))
#endif
void idris2_crashThrow(int kind, const char *msg, size_t len);

// FFI of System.Crash: run the `PrimIO a` (borrowed; `erased` is its type)
// in a boundary, and
// give its result, or NULL if it crashed (then idris2_crashCaught gives 1
// and the functions below tell what happened, until idris2_crashClear).
// (Hand written and small, as a function that calls setjmp has to be: see
// crash.c.)
Idris2_Value *idris2_crashCatch(Idris2_Value *erased, Idris2_Closure *action);
int64_t idris2_crashCaught(void);
int64_t idris2_crashKind(void);
// (strings of the RefC calling convention: new Idris values)
Idris2_Value *idris2_crashMessage(void);
Idris2_Value *idris2_crashBacktrace(void); // "" when there is none
int64_t idris2_crashHasBacktrace(void);
void idris2_crashClear(void);
// The number of crashes that boundaries caught since the program started.
int64_t idris2_crashesCaught(void);
// 1 on this backend: boundaries catch crashes.
int64_t idris2_crashBoundaries(void);
