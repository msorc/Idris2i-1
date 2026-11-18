#include "random.h"
#include "threads.h"
#include "worker.h"

#include <time.h>

// See random.h.  `lock` guards the state.
static Idris2_SpinLock lock = 0;
static uint64_t state[4];
static int seeded = 0;

static inline uint64_t rotl(uint64_t x, int k) {
  return (x << k) | (x >> (64 - k));
}

// The state of xoshiro256** must not be all zeros: it is filled with the
// output of splitmix64, as its authors recommend, which is never all zeros.
static void seed_locked(uint64_t seed) {
  for (int i = 0; i < 4; i++) {
    uint64_t z = (seed += UINT64_C(0x9E3779B97F4A7C15));
    z = (z ^ (z >> 30)) * UINT64_C(0xBF58476D1CE4E5B9);
    z = (z ^ (z >> 27)) * UINT64_C(0x94D049BB133111EB);
    state[i] = z ^ (z >> 31);
  }
  seeded = 1;
}

static uint64_t next(void) {
  idris2_spinLock(&lock);
  if (!seeded) {
    // The time of the day and the monotonic clock, in nanoseconds, and the
    // address of a variable (which changes from run to run where the address
    // space is randomised).
    uint64_t seed = (uint64_t)time(NULL) * UINT64_C(1000000007);
    seed ^= (uint64_t)idris2_monotonicNanoseconds();
    seed ^= (uint64_t)(uintptr_t)&seed << 20;
    seed_locked(seed);
  }
  uint64_t *s = state;
  uint64_t result = rotl(s[1] * 5, 7) * 9;
  uint64_t t = s[1] << 17;
  s[2] ^= s[0];
  s[3] ^= s[1];
  s[1] ^= s[2];
  s[0] ^= s[3];
  s[2] ^= t;
  s[3] = rotl(s[3], 45);
  idris2_spinUnlock(&lock);
  return result;
}

void refc_randomSeed(uint64_t seed) {
  idris2_spinLock(&lock);
  seed_locked(seed);
  idris2_spinUnlock(&lock);
}

uint32_t refc_randomBits32(uint32_t bound) {
  // (the upper bits of xoshiro256** are its best ones)
  uint32_t x = (uint32_t)(next() >> 32);
  if (bound == 0) {
    return x;
  }
  // Lemire's method: the upper half of x * bound is in [0, bound).  It is
  // uniformly distributed once the values of x whose lower half falls in
  // the first (2^32 mod bound) numbers are rejected.
  uint64_t m = (uint64_t)x * bound;
  uint32_t low = (uint32_t)m;
  if (low < bound) {
    uint32_t threshold = (uint32_t)(-bound) % bound;
    while (low < threshold) {
      x = (uint32_t)(next() >> 32);
      m = (uint64_t)x * bound;
      low = (uint32_t)m;
    }
  }
  return (uint32_t)(m >> 32);
}

double refc_randomDouble(void) {
  // The 53 upper bits, which is what the mantissa of a double holds.
  return (double)(next() >> 11) * 0x1.0p-53;
}
