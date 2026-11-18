#pragma once

#include <stdint.h>

// ---------------------------------------------------------------------------
// Random numbers (System.Random of contrib).
//
// The generator is xoshiro256** (Blackman and Vigna), seeded through
// splitmix64.  It has one state for the whole process, guarded by a spin
// lock, as the green threads of a program run on several OS threads (see
// worker.h): the functions of the C library (rand, srand) keep a state that
// is not safe to use from several threads everywhere.
//
// Like in the Chez backend, the generator is seeded from the clock the first
// time that it is used, unless the program seeded it with `srand`.  After
// `srand`, a program that draws its numbers from a single thread gets the
// same ones every time it runs.
// ---------------------------------------------------------------------------

// A number from [0, bound), uniformly distributed.  A bound of 0 stands for
// 2^32, i.e. any 32 bit number (this is what the `randomRIO` of `Int32`
// asks for when the range is the whole type, as the size of the range is
// truncated to 32 bits).
uint32_t refc_randomBits32(uint32_t bound);

// A number from [0, 1), uniformly distributed (a multiple of 2^-53).
double refc_randomDouble(void);

// Seed the generator.
void refc_randomSeed(uint64_t seed);
