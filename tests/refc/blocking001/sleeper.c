// A call that blocks its OS thread, run through idris2_blockingCall so that
// it does not block the worker of the green thread that makes it.
#include <stdint.h>
#include <time.h>

int idris2_blockingCall(void (*fn)(void *), void *arg);

static void sleep_ms(void *arg) {
  int64_t ms = *(int64_t *)arg;
  struct timespec t = {(time_t)(ms / 1000), (long)(ms % 1000) * 1000000};
  while (nanosleep(&t, &t) != 0) {
  }
}

int64_t test_sleepBlocking(int64_t ms) {
  return idris2_blockingCall(sleep_ms, &ms);
}
