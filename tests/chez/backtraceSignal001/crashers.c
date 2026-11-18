// Foreign functions that die of a signal.
#include <signal.h>
#include <stdint.h>
#include <stdlib.h>

int64_t bt_segv(int64_t x) {
  int *volatile p = NULL;
  *p = (int)x;
  return x;
}

int64_t bt_fpe(int64_t x) {
#if defined(__x86_64__) || defined(__i386__)
  volatile int64_t zero = 0;
  return x / zero;
#else
  // (no trap for a division by zero on other processors)
  raise(SIGFPE);
  return x;
#endif
}

int64_t bt_abort(int64_t x) {
  abort();
  return x;
}
