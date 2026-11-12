#include "clock.h"

#define NSEC_PER_SEC 1000000000

// A clock is boxed as the number of nanoseconds it holds, in a Bits64.

static Idris2_Value *clockOf(struct timespec t) {
  uint64_t ns = (uint64_t)t.tv_sec * NSEC_PER_SEC + (uint64_t)t.tv_nsec;
  return (Idris2_Value *)idris2_mkBits64(ns);
}

static Idris2_Value *clockRead(clockid_t id) {
  struct timespec t;
  if (clock_gettime(id, &t) != 0)
    return NULL;
  return clockOf(t);
}

Idris2_Value *clockTimeMonotonic() { return clockRead(CLOCK_MONOTONIC); }

Idris2_Value *clockTimeUtc() { return clockRead(CLOCK_REALTIME); }

Idris2_Value *clockTimeProcess() {
#ifdef CLOCK_PROCESS_CPUTIME_ID
  Idris2_Value *cpu = clockRead(CLOCK_PROCESS_CPUTIME_ID);
  if (cpu != NULL)
    return cpu;
#endif
  uint64_t ns = (uint64_t)clock() * (NSEC_PER_SEC / CLOCKS_PER_SEC);
  return (Idris2_Value *)idris2_mkBits64(ns);
}

// Green threads move between the workers (see threads.h), so the CPU time of
// the current OS thread is not the time of the current Idris thread; the
// time of the process is the closest measure that is right with a single
// worker.
Idris2_Value *clockTimeThread() { return clockTimeProcess(); }

Idris2_Value *clockTimeGcCpu() { return NULL; }

Idris2_Value *clockTimeGcReal() { return NULL; }

int clockValid(Idris2_Value *clock) { return clock != NULL; }

uint64_t clockSecond(Idris2_Value *clock) {
  return idris2_vp_to_Bits64(clock) / NSEC_PER_SEC;
}

uint64_t clockNanosecond(Idris2_Value *clock) {
  return idris2_vp_to_Bits64(clock) % NSEC_PER_SEC;
}
