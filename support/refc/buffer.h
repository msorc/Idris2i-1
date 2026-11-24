#pragma once

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct {
  int size;
  char data[];
} Buffer;

void *newBuffer(int64_t bytes);

int getBufferSize(void *buffer);

// Stops the program: the `len` bytes from `offset` are not all within the
// buffer.  Out of line and cold, so that the checks of the inline accessors
// below are a compare and a branch that is not taken.
#if defined(__GNUC__) || defined(__clang__)
__attribute__((cold, noreturn))
#endif
void idris2i_1_bufferRangeError(const Buffer *buf, int64_t offset, int64_t len);

// Checks that the `len` bytes from `offset` are within the buffer (`len` is
// not negative, and a constant at the call sites below), and stops the program
// if they are not.  `buf->size - len` cannot overflow: both are ints.
static inline void idris2i_1_checkBufferRange(const Buffer *buf, int64_t offset,
                                           int64_t len) {
  if (__builtin_expect(offset < 0 || offset > (int64_t)buf->size - len, 0))
    idris2i_1_bufferRangeError(buf, offset, len);
}

// The fixed-width reads and writes of `Data.Buffer`, little-endian.  They are
// inline so that a read in a loop of the generated code is a bounds check and
// a load, not a call.  `getBufferUIntLE` and `setBufferUIntLE` are the general
// ones, for any length from 0 to 8.
uint64_t getBufferUIntLE(void *buffer, int64_t loc, size_t len);
void setBufferUIntLE(void *buffer, int64_t loc, uint64_t val, size_t len);

#if defined(__BYTE_ORDER__) && __BYTE_ORDER__ == __ORDER_LITTLE_ENDIAN__
#define IDRIS2I_1_BUFFER_LOAD(T, n)                                               \
  T v;                                                                         \
  memcpy(&v, buf->data + loc, n);                                              \
  return v
#define IDRIS2I_1_BUFFER_STORE(T, n)                                              \
  T v = (T)val;                                                                \
  memcpy(buf->data + loc, &v, n)
#else
#define IDRIS2I_1_BUFFER_LOAD(T, n)                                               \
  T v = 0;                                                                     \
  for (int i = n - 1; i >= 0; i--)                                             \
    v = (T)((v << 8) | (uint8_t)buf->data[loc + i]);                           \
  return v
#define IDRIS2I_1_BUFFER_STORE(T, n)                                              \
  uint64_t v = (uint64_t)val;                                                  \
  for (int i = 0; i < n; i++) {                                                \
    buf->data[loc + i] = (char)(uint8_t)v;                                     \
    v >>= 8;                                                                   \
  }
#endif

static inline uint8_t getBufferUInt8(void *b, int64_t loc) {
  Buffer *buf = (Buffer *)b;
  idris2i_1_checkBufferRange(buf, loc, 1);
  return (uint8_t)buf->data[loc];
}
static inline uint16_t getBufferUInt16LE(void *b, int64_t loc) {
  Buffer *buf = (Buffer *)b;
  idris2i_1_checkBufferRange(buf, loc, 2);
  IDRIS2I_1_BUFFER_LOAD(uint16_t, 2);
}
static inline uint32_t getBufferUInt32LE(void *b, int64_t loc) {
  Buffer *buf = (Buffer *)b;
  idris2i_1_checkBufferRange(buf, loc, 4);
  IDRIS2I_1_BUFFER_LOAD(uint32_t, 4);
}
static inline uint64_t getBufferUInt64LE(void *b, int64_t loc) {
  Buffer *buf = (Buffer *)b;
  idris2i_1_checkBufferRange(buf, loc, 8);
  IDRIS2I_1_BUFFER_LOAD(uint64_t, 8);
}

// (the signed reads give the unsigned value, which the caller converts)
#define getBufferByte(b, l) ((int64_t)getBufferUInt8(b, l))
#define getBufferInt16LE(b, l) ((int64_t)getBufferUInt16LE(b, l))
#define getBufferInt32LE(b, l) ((int64_t)getBufferUInt32LE(b, l))
#define getBufferInt64LE(b, l) ((int64_t)getBufferUInt64LE(b, l))

static inline void setBufferUInt8(void *b, int64_t loc, uint64_t val) {
  Buffer *buf = (Buffer *)b;
  idris2i_1_checkBufferRange(buf, loc, 1);
  buf->data[loc] = (char)(uint8_t)val;
}
static inline void setBufferUInt16LE(void *b, int64_t loc, uint64_t val) {
  Buffer *buf = (Buffer *)b;
  idris2i_1_checkBufferRange(buf, loc, 2);
  IDRIS2I_1_BUFFER_STORE(uint16_t, 2);
}
static inline void setBufferUInt32LE(void *b, int64_t loc, uint64_t val) {
  Buffer *buf = (Buffer *)b;
  idris2i_1_checkBufferRange(buf, loc, 4);
  IDRIS2I_1_BUFFER_STORE(uint32_t, 4);
}
static inline void setBufferUInt64LE(void *b, int64_t loc, uint64_t val) {
  Buffer *buf = (Buffer *)b;
  idris2i_1_checkBufferRange(buf, loc, 8);
  IDRIS2I_1_BUFFER_STORE(uint64_t, 8);
}

#undef IDRIS2I_1_BUFFER_LOAD
#undef IDRIS2I_1_BUFFER_STORE

#define setBufferByte(b, l, v) setBufferUInt8(b, l, (uint64_t)(v))
#define setBufferInt16LE(b, l, v) setBufferUInt16LE(b, l, (uint64_t)(v))
#define setBufferInt32LE(b, l, v) setBufferUInt32LE(b, l, (uint64_t)(v))
#define setBufferInt64LE(b, l, v) setBufferUInt64LE(b, l, (uint64_t)(v))

void setBufferDouble(void *buffer, int64_t loc, double val);
// The strings are Idris values (Idris2i_1_String), which are declared later.
void setBufferString(void *buffer, int64_t loc, void *str);

void copyBuffer(void *from, int64_t start, int64_t len, void *to,
                int64_t loc);

// Operations on ranges of bytes, for the loops of `Data.ByteString`.  Each
// checks its ranges as `copyBuffer` does (a negative length is an error).
//
// The order of the `n` bytes from `aoff` in `a` and the `n` bytes from `boff`
// in `b`, as unsigned bytes: -1, 0 or 1 (memcmp).
int64_t idris2i_1_bufferCompare(void *a, int64_t aoff, void *b, int64_t boff,
                             int64_t n);
// The index (from `off`) of the first byte `w` in the `n` bytes from `off`, or
// -1 (memchr).
int64_t idris2i_1_bufferFindByte(void *b, int64_t off, int64_t n, uint8_t w);
// FNV-1a on 31 bits over the `n` bytes from `off`, from the state `h`: for
// each byte, `h = ((h xor byte) * 16777619) mod 2^31` (in 64-bit two's
// complement arithmetic, as Idris computes it with `Int`).
int64_t idris2i_1_bufferHashFNV31(int64_t h, void *b, int64_t off, int64_t n);

double getBufferDouble(void *buffer, int64_t loc);
void *getBufferString(void *buffer, int64_t loc, int64_t len);
