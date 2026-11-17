#include "buffer.h"
#include "memoryManagement.h"
#include "refc_util.h"
#include <string.h>
#include <sys/stat.h>

void *newBuffer(int bytes) {
  size_t size = sizeof(Buffer) + bytes * sizeof(uint8_t);

  Buffer *buf = malloc(size);
  IDRIS2_REFC_VERIFY(buf, "malloc failed");

  buf->size = bytes;
  memset(buf->data, 0, bytes);

  return (void *)buf;
}

static void assert_valid_range(Buffer *buf, int64_t offset, int64_t len) {
  IDRIS2_REFC_VERIFY(offset >= 0, "offset (%lld) < 0", (long long)offset);
  IDRIS2_REFC_VERIFY(len >= 0, "len (%lld) < 0", (long long)len);
  IDRIS2_REFC_VERIFY(offset + len <= buf->size,
                     "offset (%lld) + len (%lld) > buf.size (%lld)",
                     (long long)offset, (long long)len, (long long)buf->size);
}

void copyBuffer(void *from, int from_offset, int len, void *to, int to_offset) {
  Buffer *bfrom = from;
  Buffer *bto = to;

  assert_valid_range(bfrom, from_offset, len);
  assert_valid_range(bto, to_offset, len);

  // (the ranges overlap when the data is copied within one buffer)
  memmove(bto->data + to_offset, bfrom->data + from_offset, len);
}

int getBufferSize(void *buffer) { return ((Buffer *)buffer)->size; }

void setBufferUIntLE(void *b, int loc, uint64_t val, size_t len) {
  assert_valid_range((Buffer *)b, loc, len);
  while (len--) {
    ((Buffer *)b)->data[loc++] = (uint8_t)val;
    val >>= 8;
  }
}

uint64_t getBufferUIntLE(void *b, int loc, size_t len) {
  assert_valid_range((Buffer *)b, loc, len);
  uint64_t r = 0;
  loc += len;
  while (len--) {
    r <<= 8;
    r += (uint8_t)(((Buffer *)b)->data[--loc]);
  }
  return r;
}

void setBufferDouble(void *buffer, int loc, double val) {
  union {
    double d;
    uint64_t i;
  } tmp;
  tmp.d = val;
  setBufferUIntLE(buffer, loc, tmp.i, 8);
}

// (strings are Idris values, see buffer.h)
void setBufferString(void *buffer, int loc, void *str) {
  Buffer *b = buffer;
  Idris2_String *s = str;
  assert_valid_range(b, loc, s->len);
  memcpy((b->data) + loc, s->str, s->len);
}

double getBufferDouble(void *buffer, int loc) {
  union {
    double d;
    uint64_t i;
  } tmp;
  tmp.i = getBufferUIntLE(buffer, loc, 8);
  return tmp.d;
}

void *getBufferString(void *buffer, int loc, int len) {
  Buffer *b = buffer;
  assert_valid_range(b, loc, len);
  return idris2_mkStringN((char const *)(b->data + loc), len);
}
