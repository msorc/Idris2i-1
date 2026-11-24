#include "clock.h"

#define NSEC_PER_SEC 1000000000

// A clock is boxed as the number of nanoseconds it holds, in a Bits64.

static Idris2i_1_Value *clockOf(struct timespec t) {
  uint64_t ns = (uint64_t)t.tv_sec * NSEC_PER_SEC + (uint64_t)t.tv_nsec;
  return (Idris2i_1_Value *)idris2i_1_mkBits64(ns);
}

static Idris2i_1_Value *clockRead(clockid_t id) {
  struct timespec t;
  if (clock_gettime(id, &t) != 0)
    return NULL;
  return clockOf(t);
}

Idris2i_1_Value *clockTimeMonotonic() { return clockRead(CLOCK_MONOTONIC); }

Idris2i_1_Value *clockTimeUtc() { return clockRead(CLOCK_REALTIME); }

Idris2i_1_Value *clockTimeProcess() {
#ifdef CLOCK_PROCESS_CPUTIME_ID
  Idris2i_1_Value *cpu = clockRead(CLOCK_PROCESS_CPUTIME_ID);
  if (cpu != NULL)
    return cpu;
#endif
  uint64_t ns = (uint64_t)clock() * (NSEC_PER_SEC / CLOCKS_PER_SEC);
  return (Idris2i_1_Value *)idris2i_1_mkBits64(ns);
}

// Green threads move between the workers (see threads.h), so the CPU time of
// the current OS thread is not the time of the current Idris thread; the
// time of the process is the closest measure that is right with a single
// worker.
Idris2i_1_Value *clockTimeThread() { return clockTimeProcess(); }

Idris2i_1_Value *clockTimeGcCpu() { return NULL; }

Idris2i_1_Value *clockTimeGcReal() { return NULL; }

int clockValid(Idris2i_1_Value *clock) { return clock != NULL; }

uint64_t clockSecond(Idris2i_1_Value *clock) {
  return idris2i_1_vp_to_Bits64(clock) / NSEC_PER_SEC;
}

uint64_t clockNanosecond(Idris2i_1_Value *clock) {
  return idris2i_1_vp_to_Bits64(clock) % NSEC_PER_SEC;
}
