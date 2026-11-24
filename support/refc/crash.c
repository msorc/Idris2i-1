// ---------------------------------------------------------------------------
// Crash boundaries.
//
// A boundary (idris2i_1_crashCatch, behind System.Crash.catchCrash) records a
// recovery point with sigsetjmp, on the stack of the green thread that runs
// it, in a frame that it links into the thread (Idris2i_1_CrashState, see
// threads.c): nested boundaries make a stack.  A crash of that thread
// (idris2i_1_crash, idris2i_1_crashMsg, idris2i_1_crashCheck, a range check of a
// Buffer) asks idris2i_1_crashCatchable whether it may end at the innermost
// boundary; if so, idris2i_1_crashThrow records what happened and jumps back to
// the recovery point with siglongjmp, abandoning every C frame in between,
// and the boundary keeps the record in the thread, where System.Crash reads
// it.  Otherwise the crash does what it always did: print its message and
// exit.
//
// Why this is sound, and what it costs:
//
// * A crash is synchronous: it is a call made by the code of the thread
//   itself, so the thread runs (it is not parked, nor in a run queue, nor
//   waiting for a descriptor or a deadline), and the thread goes on after
//   the boundary, so all of its state in the scheduler stays consistent.
//   The frame is on the stack of the thread, and the thread runs on that
//   stack wherever it runs: it may have moved to another worker since the
//   boundary started (siglongjmp only restores the stack pointer and the
//   callee saved registers, and the code after the recovery point finds its
//   worker again with idris2i_1_worker(), see worker.h).
// * The crashes that may end at a boundary are raised by the generated code
//   and by support functions that it calls, never under a spin lock of the
//   runtime nor inside the allocator.  Idris code only runs under the
//   runtime when it is a finaliser (see releaseOne in memoryManagement.c),
//   which may be called by any release, those of the runtime included: a
//   crash in a finaliser is fatal, unless the finaliser has a boundary of
//   its own (`finalisers` counts the finalisers that the thread runs; a
//   frame only catches when none started after it).  The other piece of
//   runtime state that the abandoned frames may be in the middle of is the
//   evaluation of a constant (see idris2i_1_makeConstant): the constants that
//   the thread claimed since the boundary started are given back, so that
//   another thread may evaluate them (or crash in turn).
// * The values that the abandoned frames own are never released: a crash
//   leaks them (the request of a handler, say).  Nothing reclaims them
//   later.  idris2i_1_crashesCaught counts the crashes, for an operator who
//   restarts a long-running program that leaks too much.
// * A value updated in place (a cell taken over for a new constructor, a
//   closure applied in place) has a single reference, that of the frame
//   that updates it, so nothing outside the boundary sees it half done.
//   What the code wrote to mutable objects (IORef, IOArray, Buffer, files)
//   before the crash stays written, and a Mutex that it held stays held, by
//   the same thread.
// * The pending tail call of the worker (see runtime.h) is only read right
//   after the function that set it returns IDRIS2I_1_TAILCALL, so whatever an
//   abandoned frame left there is never read.
// ---------------------------------------------------------------------------

#include "crash.h"
#include "backtrace.h"
#include "memoryManagement.h"
#include "runtime.h"

#include <setjmp.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

struct Idris2i_1_CrashFrame {
  sigjmp_buf buf;
  Idris2i_1_CrashFrame *prev;
  // The finalisers that the thread ran and the constants that it evaluated
  // when the boundary started.
  int finalisers;
  Idris2i_1_ConstantClaim *constants;
  // Written by idris2i_1_crashThrow before it jumps back (so `volatile`, as
  // the C standard asks of what changes between setjmp and longjmp).
  Idris2i_1_CrashInfo *volatile info;
};

static int64_t crashes_caught = 0;

int idris2i_1_crashCatchable(void) {
  Idris2i_1_CrashState *cs = idris2i_1_crashState();
  if (!cs || !cs->frame) {
    return 0;
  }
  return cs->frame->finalisers == cs->finalisers;
}

static char *copy_bytes(const char *s, size_t len) {
  char *r = (char *)malloc(len + 1);
  if (r) {
    memcpy(r, s, len);
    r[len] = '\0';
  }
  return r;
}

void idris2i_1_crashThrow(int kind, const char *msg, size_t len) {
  Idris2i_1_CrashState *cs = idris2i_1_crashState();
  Idris2i_1_CrashFrame *frame = cs->frame;
  Idris2i_1_CrashInfo *info = (Idris2i_1_CrashInfo *)malloc(sizeof(*info));
  char *message = copy_bytes(msg, len);
  if (!info || !message) {
    fputs("RefC: out of memory while catching a crash\n", stderr);
    exit(1);
  }
  info->kind = kind;
  info->message = message;
  info->messageLen = len;
  info->backtrace = idris2i_1_backtraceCapture();
  // The constants that the thread was evaluating since the boundary
  // started: the other threads that wait for them may evaluate them now.
  for (Idris2i_1_ConstantClaim *c = cs->constants; c != frame->constants;
       c = c->prev) {
    __atomic_store_n(c->maker, 0, __ATOMIC_RELEASE);
  }
  cs->constants = frame->constants;
  __atomic_fetch_add(&crashes_caught, 1, __ATOMIC_RELAXED);
  frame->info = info;
  siglongjmp(frame->buf, 1);
}

static void free_info(Idris2i_1_CrashInfo *i) {
  if (i) {
    free(i->message);
    free(i->backtrace);
    free(i);
  }
}

#if defined(__GNUC__) || defined(__clang__)
__attribute__((noinline))
#endif
Idris2i_1_Value *idris2i_1_crashCatch(Idris2i_1_Value *erased, Idris2i_1_Closure *action) {
  (void)erased;
  // (`cs` and the fields of `frame` other than `info` do not change after
  // sigsetjmp, so they keep their values when it returns again)
  Idris2i_1_CrashState *cs = idris2i_1_crashState();
  Idris2i_1_CrashFrame frame;
  frame.prev = cs->frame;
  frame.finalisers = cs->finalisers;
  frame.constants = cs->constants;
  frame.info = NULL;
  cs->frame = &frame;
  // (0: the signal mask is not saved, which would cost a system call; a
  // crash is not raised in a signal handler, so the mask is the same)
  if (sigsetjmp(frame.buf, 0) == 0) {
    Idris2i_1_Value *result = idris2i_1_run_primio(
        (Idris2i_1_Closure *)idris2i_1_newReference((Idris2i_1_Value *)action));
    cs->frame = frame.prev;
    return result;
  }
  cs->frame = frame.prev;
  free_info(cs->caught);
  cs->caught = frame.info;
  return NULL;
}

int64_t idris2i_1_crashCaught(void) { return idris2i_1_crashState()->caught != NULL; }

int64_t idris2i_1_crashKind(void) { return idris2i_1_crashState()->caught->kind; }

Idris2i_1_Value *idris2i_1_crashMessage(void) {
  Idris2i_1_CrashInfo *i = idris2i_1_crashState()->caught;
  return (Idris2i_1_Value *)idris2i_1_mkStringN(i->message, i->messageLen);
}

Idris2i_1_Value *idris2i_1_crashBacktrace(void) {
  const char *bt = idris2i_1_crashState()->caught->backtrace;
  return (Idris2i_1_Value *)idris2i_1_mkString(bt ? bt : "");
}

int64_t idris2i_1_crashHasBacktrace(void) {
  return idris2i_1_crashState()->caught->backtrace != NULL;
}

void idris2i_1_crashClear(void) {
  Idris2i_1_CrashState *cs = idris2i_1_crashState();
  free_info(cs->caught);
  cs->caught = NULL;
}

int64_t idris2i_1_crashesCaught(void) {
  return __atomic_load_n(&crashes_caught, __ATOMIC_RELAXED);
}

int64_t idris2i_1_crashBoundaries(void) { return 1; }
