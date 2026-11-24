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
#define IDRIS2I_1_CRASH_CALL 0         // idris_crash
#define IDRIS2I_1_CRASH_MISSING_CASE 1 // compiled code with no clause, a hole
#define IDRIS2I_1_CRASH_FAILED_CHECK 2 // a check of the runtime failed

// What a boundary keeps of a crash: allocated with malloc, in the thread
// until the next boundary of the thread ends with a crash, or until the
// code of System.Crash has read it (idris2i_1_crashClear).
typedef struct {
  int kind;
  char *message; // (NUL-terminated too)
  size_t messageLen;
  char *backtrace; // NULL when backtraces are off
} Idris2i_1_CrashInfo;

typedef struct Idris2i_1_CrashFrame Idris2i_1_CrashFrame;

// A constant that a thread evaluates (see idris2i_1_makeConstant): a crash
// gives it back to the other threads.
typedef struct Idris2i_1_ConstantClaim {
  struct Idris2i_1_ConstantClaim *prev;
  int64_t *maker;
} Idris2i_1_ConstantClaim;

// The state of a green thread that the boundaries need (in the thread, see
// threads.c; all zero for a new thread).
typedef struct {
  // The innermost boundary of the thread, NULL if there is none.
  Idris2i_1_CrashFrame *frame;
  // The number of finalisers that the thread runs now (a crash in a
  // finaliser is fatal, see crash.c).
  int finalisers;
  // The constants that the thread evaluates now, the innermost first.
  Idris2i_1_ConstantClaim *constants;
  // The crash that the last boundary caught, until it is read.
  Idris2i_1_CrashInfo *caught;
} Idris2i_1_CrashState;

// The crash state of the thread that runs, NULL in the scheduler.
Idris2i_1_CrashState *idris2i_1_crashState(void);

// Is there a boundary that a crash of the running code may end at?
int idris2i_1_crashCatchable(void);

// End the innermost boundary of the thread with this crash (`len` bytes of
// `msg`).  Only when idris2i_1_crashCatchable() says so.
#if defined(__GNUC__) || defined(__clang__)
__attribute__((__noreturn__, __cold__))
#endif
void idris2i_1_crashThrow(int kind, const char *msg, size_t len);

// FFI of System.Crash: run the `PrimIO a` (borrowed; `erased` is its type)
// in a boundary, and
// give its result, or NULL if it crashed (then idris2i_1_crashCaught gives 1
// and the functions below tell what happened, until idris2i_1_crashClear).
// (Hand written and small, as a function that calls setjmp has to be: see
// crash.c.)
Idris2i_1_Value *idris2i_1_crashCatch(Idris2i_1_Value *erased, Idris2i_1_Closure *action);
int64_t idris2i_1_crashCaught(void);
int64_t idris2i_1_crashKind(void);
// (strings of the RefC calling convention: new Idris values)
Idris2i_1_Value *idris2i_1_crashMessage(void);
Idris2i_1_Value *idris2i_1_crashBacktrace(void); // "" when there is none
int64_t idris2i_1_crashHasBacktrace(void);
void idris2i_1_crashClear(void);
// The number of crashes that boundaries caught since the program started.
int64_t idris2i_1_crashesCaught(void);
// 1 on this backend: boundaries catch crashes.
int64_t idris2i_1_crashBoundaries(void);
