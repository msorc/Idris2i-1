#include "buffer.h"
#include "crash.h"
#include "memoryManagement.h"
#include "prim.h"
#include "refc_util.h"
#include <inttypes.h>
#include <limits.h>
#include <string.h>
#include <sys/stat.h>

// The size of a buffer is an int (as for the length of an array, see
// arrayLength in prim.c): a larger one, which was cut to an int, is an error,
// and so is a negative one (Data.Buffer.newBuffer gives Nothing for that).
void *newBuffer(int64_t bytes) {
  if (bytes < 0 || bytes > INT_MAX) {
    char msg[64];
    snprintf(msg, sizeof(msg), "ERROR: Invalid buffer size: %" PRId64, bytes);
    idris2i_1_crashCheck(msg);
  }
  Buffer *buf = malloc(sizeof(Buffer) + (size_t)bytes);
  IDRIS2I_1_REFC_VERIFY(buf, "malloc failed");

  buf->size = (int)bytes;
  memset(buf->data, 0, (size_t)bytes);

  return (void *)buf;
}

static void assert_valid_range(const Buffer *buf, int64_t offset, int64_t len) {
  IDRIS2I_1_REFC_VERIFY(offset >= 0, "offset (%lld) < 0", (long long)offset);
  IDRIS2I_1_REFC_VERIFY(len >= 0, "len (%lld) < 0", (long long)len);
  IDRIS2I_1_REFC_VERIFY(offset <= (int64_t)buf->size - len,
                     "offset (%lld) + len (%lld) > buf.size (%lld)",
                     (long long)offset, (long long)len, (long long)buf->size);
}

// An access out of the buffer ends the innermost crash boundary of the
// thread (see crash.c), or stops the program as a failed assertion.
void idris2i_1_bufferRangeError(const Buffer *buf, int64_t offset, int64_t len) {
  if (idris2i_1_crashCatchable()) {
    char msg[160];
    int n;
    if (offset < 0)
      n = snprintf(msg, sizeof(msg),
                   "Buffer access out of range: offset (%lld) < 0",
                   (long long)offset);
    else if (len < 0)
      n = snprintf(msg, sizeof(msg),
                   "Buffer access out of range: len (%lld) < 0",
                   (long long)len);
    else
      n = snprintf(msg, sizeof(msg),
                   "Buffer access out of range: offset (%lld) + len (%lld) > "
                   "buf.size (%lld)",
                   (long long)offset, (long long)len, (long long)buf->size);
    idris2i_1_crashThrow(IDRIS2I_1_CRASH_FAILED_CHECK, msg,
                      n < 0 ? 0 : (size_t)n < sizeof(msg) ? (size_t)n
                                                          : sizeof(msg) - 1);
  }
  assert_valid_range((Buffer *)buf, offset, len);
  // (not reached: the range is not valid)
  abort();
}

// The checks of the functions below.
static inline void check_range(const Buffer *buf, int64_t offset,
                               int64_t len) {
  if (offset < 0 || len < 0 || offset > (int64_t)buf->size - len)
    idris2i_1_bufferRangeError(buf, offset, len);
}

void copyBuffer(void *from, int64_t from_offset, int64_t len, void *to, int64_t to_offset) {
  Buffer *bfrom = from;
  Buffer *bto = to;

  check_range(bfrom, from_offset, len);
  check_range(bto, to_offset, len);

  // (the ranges overlap when the data is copied within one buffer)
  memmove(bto->data + to_offset, bfrom->data + from_offset, len);
}

int64_t idris2i_1_bufferCompare(void *a, int64_t aoff, void *b, int64_t boff,
                             int64_t n) {
  check_range((Buffer *)a, aoff, n);
  check_range((Buffer *)b, boff, n);
  int r = memcmp(((Buffer *)a)->data + aoff, ((Buffer *)b)->data + boff,
                 (size_t)n);
  return r < 0 ? -1 : r > 0 ? 1 : 0;
}

int64_t idris2i_1_bufferFindByte(void *b, int64_t off, int64_t n, uint8_t w) {
  check_range((Buffer *)b, off, n);
  const char *start = ((Buffer *)b)->data + off;
  const char *p = memchr(start, w, (size_t)n);
  return p ? (int64_t)(p - start) : -1;
}

int64_t idris2i_1_bufferHashFNV31(int64_t h, void *b, int64_t off, int64_t n) {
  check_range((Buffer *)b, off, n);
  const uint8_t *p = (const uint8_t *)((Buffer *)b)->data + off;
  // (unsigned, so that the product wraps as `Int` arithmetic does; only its
  // low 31 bits are kept)
  uint64_t u = (uint64_t)h;
  for (int64_t i = 0; i < n; i++)
    u = ((u ^ p[i]) * UINT64_C(16777619)) & UINT64_C(0x7fffffff);
  return (int64_t)u;
}

int getBufferSize(void *buffer) { return ((Buffer *)buffer)->size; }

void setBufferUIntLE(void *b, int64_t loc, uint64_t val, size_t len) {
  check_range((Buffer *)b, loc, len);
  while (len--) {
    ((Buffer *)b)->data[loc++] = (uint8_t)val;
    val >>= 8;
  }
}

uint64_t getBufferUIntLE(void *b, int64_t loc, size_t len) {
  check_range((Buffer *)b, loc, len);
  uint64_t r = 0;
  loc += len;
  while (len--) {
    r <<= 8;
    r += (uint8_t)(((Buffer *)b)->data[--loc]);
  }
  return r;
}

void setBufferDouble(void *buffer, int64_t loc, double val) {
  union {
    double d;
    uint64_t i;
  } tmp;
  tmp.d = val;
  setBufferUIntLE(buffer, loc, tmp.i, 8);
}

// (strings are Idris values, see buffer.h)
void setBufferString(void *buffer, int64_t loc, void *str) {
  Buffer *b = buffer;
  Idris2i_1_String *s = str;
  check_range(b, loc, s->len);
  memcpy((b->data) + loc, s->str, s->len);
}

double getBufferDouble(void *buffer, int64_t loc) {
  union {
    double d;
    uint64_t i;
  } tmp;
  tmp.i = getBufferUIntLE(buffer, loc, 8);
  return tmp.d;
}

void *getBufferString(void *buffer, int64_t loc, int64_t len) {
  Buffer *b = buffer;
  check_range(b, loc, len);
  return idris2i_1_mkStringN((char const *)(b->data + loc), len);
}
