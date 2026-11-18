// Foreign functions that die of a signal.  They are not inlined, so that
// their frames are on the stack whatever the optimisation level.
#pragma once

#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/mman.h>
#include <unistd.h>

__attribute__((noinline)) static int64_t bt_segv(int64_t x) {
  int *volatile p = NULL;
  *p = (int)x;
  return x;
}

__attribute__((noinline)) static int64_t bt_fpe(int64_t x) {
#if defined(__x86_64__) || defined(__i386__)
  volatile int64_t zero = 0;
  return x / zero;
#else
  // (no trap for a division by zero on other processors)
  raise(SIGFPE);
  return x;
#endif
}

__attribute__((noinline)) static int64_t bt_abort(int64_t x) {
  abort();
  return x;
}

// A mapping of an empty file: a read of it is a bus error.
__attribute__((noinline)) static int64_t bt_bus(int64_t x) {
  FILE *f = tmpfile();
  if (!f) {
    return x;
  }
  volatile char *p = (volatile char *)mmap(NULL, 4096, PROT_READ, MAP_PRIVATE,
                                           fileno(f), 0);
  if (p == MAP_FAILED) {
    return x;
  }
  return x + p[0];
}
