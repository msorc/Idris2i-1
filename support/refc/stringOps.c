#include "stringOps.h"
#include "refc_util.h"

/*
 * Strings are stored as NUL-terminated UTF-8, but every operation works on
 * Unicode code points, like the other backends do.  Bytes that are not part
 * of a valid UTF-8 sequence are read as U+FFFD, one byte at a time.
 */

int idris2_utf8_encode(uint32_t c, char *out) {
  unsigned char *o = (unsigned char *)out;
  if (c < 0x80) {
    o[0] = c;
    return 1;
  } else if (c < 0x800) {
    o[0] = 0xC0 | (c >> 6);
    o[1] = 0x80 | (c & 0x3F);
    return 2;
  } else if (c < 0x10000) {
    o[0] = 0xE0 | (c >> 12);
    o[1] = 0x80 | ((c >> 6) & 0x3F);
    o[2] = 0x80 | (c & 0x3F);
    return 3;
  } else {
    o[0] = 0xF0 | (c >> 18);
    o[1] = 0x80 | ((c >> 12) & 0x3F);
    o[2] = 0x80 | ((c >> 6) & 0x3F);
    o[3] = 0x80 | (c & 0x3F);
    return 4;
  }
}

int idris2_utf8_encodedLength(uint32_t c) {
  return c < 0x80 ? 1 : c < 0x800 ? 2 : c < 0x10000 ? 3 : 4;
}

uint32_t idris2_utf8_decode(char const **p) {
  unsigned char const *s = (unsigned char const *)*p;
  uint32_t c = s[0];
  int n;
  uint32_t min;

  if (c < 0x80) {
    *p += 1;
    return c;
  } else if (c >= 0xC2 && c <= 0xDF) {
    n = 1;
    c &= 0x1F;
    min = 0x80;
  } else if (c >= 0xE0 && c <= 0xEF) {
    n = 2;
    c &= 0x0F;
    min = 0x800;
  } else if (c >= 0xF0 && c <= 0xF4) {
    n = 3;
    c &= 0x07;
    min = 0x10000;
  } else {
    *p += 1;
    return 0xFFFD;
  }

  for (int i = 1; i <= n; i++) {
    if ((s[i] & 0xC0) != 0x80) {
      *p += 1;
      return 0xFFFD;
    }
    c = (c << 6) | (s[i] & 0x3F);
  }
  if (c < min || c > 0x10FFFF || (c >= 0xD800 && c <= 0xDFFF)) {
    *p += 1;
    return 0xFFFD;
  }
  *p += n + 1;
  return c;
}

#define STR(v) ((Idris2_String *)(v))

/* Skip at most n code points of the bytes from s to end; *skipped is the
 * number of code points skipped. */
static char const *utf8_skip(char const *s, char const *end, int64_t n,
                             int64_t *skipped) {
  int64_t i = 0;
  while (i < n && s < end) {
    if ((unsigned char)*s < 0x80)
      s++;
    else
      idris2_utf8_decode(&s);
    i++;
  }
  *skipped = i;
  return s < end ? s : end;
}

#define IDRIS2_HIGH_BITS UINT64_C(0x8080808080808080)

int64_t idris2_utf8_length(char const *s, size_t len) {
  char const *end = s + len;
  int64_t n = 0;
  while (s < end) {
    // Eight ASCII characters at a time
    uint64_t w;
    if (end - s >= 8 && (memcpy(&w, s, 8), (w & IDRIS2_HIGH_BITS) == 0)) {
      s += 8;
      n += 8;
      continue;
    }
    if ((unsigned char)*s < 0x80)
      s++;
    else
      idris2_utf8_decode(&s);
    n++;
  }
  return n;
}

/*
 * The number of code points of a string is counted once, and kept in the
 * string (see Idris2_String): then the length of a string is known at once,
 * and the characters of an ASCII string (or any string whose characters are
 * all one byte) can be indexed directly, like the other backends do with
 * their strings.  The functions that make a string
 * from strings whose lengths are known set the length of the result, when it
 * is the number that counting would give: a substring has the code points
 * that were skipped over to find it (an invalid byte is one U+FFFD, wherever
 * the string ends), but the concatenation of two strings that are not valid
 * UTF-8 can have fewer code points than the two (the end of one and the
 * start of the other can make a code point), and so can the reverse of one.
 * That is when the second string starts with a continuation byte.
 *
 * The count is written into a string that other threads may see, but they
 * would all write the same number: it is a relaxed atomic store.  A static
 * string (a constant of a program) may be in read only memory: it is not
 * written to, the code generator gives the length of the ASCII ones.
 */
static inline int64_t knownCodePoints(Idris2_String *s) {
  return (int64_t)__atomic_load_n(&s->codePoints, __ATOMIC_RELAXED) - 1;
}

// Does a string start with a UTF-8 continuation byte?  (see above)
static inline int startsWithContinuation(Idris2_String *s) {
  return s->len > 0 && ((unsigned char)s->str[0] & 0xC0) == 0x80;
}

int64_t idris2_stringCodePoints(Idris2_Value *str) {
  Idris2_String *s = STR(str);
  int64_t n = knownCodePoints(s);
  if (n >= 0)
    return n;
  n = idris2_utf8_length(s->str, s->len);
  if (n < (int64_t)UINT32_MAX && !(s->header.reserved & IDRIS2_STATIC_FLAG))
    __atomic_store_n(&s->codePoints, (uint32_t)(n + 1), __ATOMIC_RELAXED);
  return n;
}

/* Is each character of the string one byte (an ASCII character, or an
 * invalid byte, which is U+FFFD)?  Then the byte offsets are the character
 * offsets.  When this is not known, and a string operation would only look
 * at the first `upTo` bytes, it is not worth counting the code points of the
 * whole string: false. */
#define IDRIS2_COUNT_FROM 32
static inline int isNarrow(Idris2_String *s, int64_t upTo) {
  int64_t n = knownCodePoints(s);
  if (n < 0) {
    if (upTo < IDRIS2_COUNT_FROM)
      return 0;
    n = idris2_stringCodePoints((Idris2_Value *)s);
  }
  return (size_t)n == s->len;
}

int idris2_compareStrings(Idris2_Value *a, Idris2_Value *b) {
  size_t la = STR(a)->len, lb = STR(b)->len;
  int c = memcmp(STR(a)->str, STR(b)->str, la < lb ? la : lb);
  if (c != 0)
    return c;
  return (la > lb) - (la < lb);
}

Idris2_Value *stringLength(Idris2_Value *str) {
  return idris2_mkInt64(idris2_stringCodePoints(str));
}

Idris2_Value *head(Idris2_Value *str) {
  return idris2_cast_string_to_Char(str);
}

Idris2_Value *tail(Idris2_Value *input) {
  char const *s = STR(input)->str, *end = s + STR(input)->len;
  int64_t skipped, n = knownCodePoints(STR(input));
  char const *rest = utf8_skip(s, end, 1, &skipped);
  Idris2_String *retVal = idris2_mkStringN(rest, end - rest);
  if (n >= 0)
    idris2_setCodePoints(retVal, n - skipped);
  return (Idris2_Value *)retVal;
}

Idris2_Value *reverse(Idris2_Value *str) {
  char const *input = STR(str)->str;
  size_t l = STR(str)->len;
  Idris2_String *retVal = idris2_mkEmptyString(l + 1);
  if (l == 0)
    return (Idris2_Value *)retVal;

  /* Copy the encoding of each code point to the mirrored position.  (Bytes
   * that are not UTF-8 can make a code point once reversed: the number of
   * code points is only known for ASCII.) */
  char *out = retVal->str + l;
  char const *p = input, *end = input + l;
  int ascii = 1;
  while (p < end) {
    char const *start = p;
    if ((unsigned char)*p < 0x80)
      p++;
    else {
      idris2_utf8_decode(&p);
      ascii = 0;
    }
    if (p > end)
      p = end;
    out -= p - start;
    memcpy(out, start, p - start);
  }
  if (ascii)
    idris2_setAscii(retVal);
  return (Idris2_Value *)retVal;
}

Idris2_Value *strIndex(Idris2_Value *str, Idris2_Value *i) {
  int64_t idx = idris2_vp_to_Int64(i), skipped;
  char const *s = STR(str)->str, *end = s + STR(str)->len;
  // (a string has no more code points than bytes)
  if (idx < 0 || (uint64_t)idx >= STR(str)->len)
    return idris2_mkChar(0);
  if (isNarrow(STR(str), idx)) {
    unsigned char c = s[idx];
    return idris2_mkChar(c < 0x80 ? c : 0xFFFD);
  }
  s = utf8_skip(s, end, idx, &skipped);
  return idris2_mkChar(s >= end ? 0 : idris2_utf8_decode(&s));
}

Idris2_Value *strCons(Idris2_Value *c, Idris2_Value *str) {
  uint32_t ch = idris2_vp_to_Char(c);
  size_t l = STR(str)->len;
  int cl = idris2_utf8_encodedLength(ch);
  int64_t n = knownCodePoints(STR(str));
  Idris2_String *retVal = idris2_mkEmptyString(cl + l + 1);
  idris2_utf8_encode(ch, retVal->str);
  memcpy(retVal->str + cl, STR(str)->str, l);
  if (n >= 0 && idris2_isValidCodePoint(ch))
    idris2_setCodePoints(retVal, n + 1);
  return (Idris2_Value *)retVal;
}

Idris2_Value *strAppend(Idris2_Value *a, Idris2_Value *b) {
  size_t la = STR(a)->len, lb = STR(b)->len;
  if (lb == 0)
    return idris2_newReference(a);
  if (la == 0)
    return idris2_newReference(b);
  int64_t na = knownCodePoints(STR(a)), nb = knownCodePoints(STR(b));
  Idris2_String *retVal = idris2_mkEmptyString(la + lb + 1);
  memcpy(retVal->str, STR(a)->str, la);
  memcpy(retVal->str + la, STR(b)->str, lb);
  if (na >= 0 && nb >= 0 && !startsWithContinuation(STR(b)))
    idris2_setCodePoints(retVal, na + nb);
  return (Idris2_Value *)retVal;
}

/* Like the Scheme backends: a negative start or length counts as 0, and the
 * substring stops at the end of the string. */
Idris2_Value *strSubstr(Idris2_Value *start, Idris2_Value *len,
                        Idris2_Value *s) {
  size_t bytes = STR(s)->len;
  char const *input = STR(s)->str, *end = input + bytes;
  int64_t offset = idris2_vp_to_Int64(start);
  int64_t l = idris2_vp_to_Int64(len);
  if (offset < 0)
    offset = 0;
  if (l < 0)
    l = 0;

  char const *from, *to;
  int64_t n;
  int64_t upTo = offset < IDRIS2_COUNT_FROM && l < IDRIS2_COUNT_FROM
                     ? offset + l
                     : IDRIS2_COUNT_FROM;
  if (isNarrow(STR(s), upTo)) {
    from = input + ((uint64_t)offset < bytes ? offset : bytes);
    to = from + ((uint64_t)l < (uint64_t)(end - from) ? l : end - from);
    n = to - from;
  } else {
    int64_t skipped;
    from = utf8_skip(input, end, offset, &skipped);
    to = utf8_skip(from, end, l, &n);
  }
  if (from == input && to == end)
    return idris2_newReference(s);
  Idris2_String *retVal = idris2_mkStringN(from, to - from);
  idris2_setCodePoints(retVal, n);
  return (Idris2_Value *)retVal;
}

Idris2_Value *fastPack(Idris2_Value *charList) {
  Idris2_Constructor *current;

  // (The number of characters is not kept: counting them costs more than
  // counting them later, when it is needed, for the many strings that are
  // packed from short lists, like words.)
  size_t l = 0;
  current = (Idris2_Constructor *)charList;
  while (current != NULL) {
    l += idris2_utf8_encodedLength(idris2_vp_to_Char(current->args[0]));
    current = (Idris2_Constructor *)current->args[1];
  }

  Idris2_String *retVal = idris2_mkEmptyString(l + 1);
  char *p = retVal->str;
  current = (Idris2_Constructor *)charList;
  while (current != NULL) {
    p += idris2_utf8_encode(idris2_vp_to_Char(current->args[0]), p);
    current = (Idris2_Constructor *)current->args[1];
  }
  return (Idris2_Value *)retVal;
}

Idris2_Value *fastUnpack(Idris2_Value *str) {
  char const *p = STR(str)->str, *end = p + STR(str)->len;
  if (p >= end)
    return NULL;

  Idris2_Constructor *retVal = idris2_newConstructor(2, 1);
  retVal->args[0] = idris2_mkChar(idris2_utf8_decode(&p));

  Idris2_Constructor *current = (Idris2_Constructor *)retVal;
  Idris2_Constructor *next;
  while (p < end) {
    next = idris2_newConstructor(2, 1);
    next->args[0] = idris2_mkChar(idris2_utf8_decode(&p));
    current->args[1] = (Idris2_Value *)next;
    current = next;
  }
  current->args[1] = NULL;

  return (Idris2_Value *)retVal;
}

Idris2_Value *fastConcat(Idris2_Value *strList) {
  Idris2_Constructor *current;

  size_t totalLength = 0;
  int64_t n = 0; // the number of code points, -1 when one is not known
  current = (Idris2_Constructor *)strList;
  while (current != NULL) {
    Idris2_String *s = STR(current->args[0]);
    int64_t k = knownCodePoints(s);
    totalLength += s->len;
    n = n < 0 || k < 0 || startsWithContinuation(s) ? -1 : n + k;
    current = (Idris2_Constructor *)current->args[1];
  }

  Idris2_String *retVal = idris2_mkEmptyString(totalLength + 1);
  size_t offset = 0;
  current = (Idris2_Constructor *)strList;
  while (current != NULL) {
    Idris2_String *s = STR(current->args[0]);
    memcpy(retVal->str + offset, s->str, s->len);
    offset += s->len;
    current = (Idris2_Constructor *)current->args[1];
  }
  idris2_setCodePoints(retVal, n);
  return (Idris2_Value *)retVal;
}

/*
 * A string iterator (Data.String.Iterator) is the byte offset of the next
 * character in the string, as the Scheme and JavaScript backends have it.
 * `uncons` and `withIteratorString` are handed the string with the iterator,
 * so nothing else is needed: an iterator is an unboxed value (the offset
 * shifted left by one bit, with the low bit set), with no allocation, no copy
 * of the string and no finaliser.  An offset past the end of the string (an
 * iterator that came from an equal string) reads as the end of the string.
 */
#define IDRIS2_ITERATOR(pos) ((Idris2_Value *)(((uintptr_t)(pos) << 1) | 1))
#define IDRIS2_ITERATOR_POS(it) ((size_t)((uintptr_t)(it) >> 1))

Idris2_Value *stringIteratorNew(Idris2_Value *str) {
  (void)str;
  return IDRIS2_ITERATOR(0);
}

Idris2_Value *stringIteratorToString(void *a, Idris2_Value *str,
                                     Idris2_Value *it, Idris2_Closure *f) {
  (void)a;
  size_t pos = IDRIS2_ITERATOR_POS(it), l = STR(str)->len;
  Idris2_Value *rest;
  if (pos == 0)
    rest = idris2_newReference(str);
  else if (pos >= l)
    rest = (Idris2_Value *)idris2_mkEmptyString(1);
  else {
    Idris2_String *r = idris2_mkStringN(STR(str)->str + pos, l - pos);
    if ((size_t)knownCodePoints(STR(str)) == l) // one byte per character
      idris2_setAscii(r);
    rest = (Idris2_Value *)r;
  }
  return idris2_apply_closure(idris2_newReference((Idris2_Value *)f), rest);
}

// contrib/Data.String.Iterator.uncons :
//   (str : String) -> (1 it : StringIterator str) -> UnconsResult str
Idris2_Value *stringIteratorNext(Idris2_Value *str, Idris2_Value *it) {
  size_t pos = IDRIS2_ITERATOR_POS(it);
  if (pos >= STR(str)->len)
    return NULL; // EOF [nil]

  char const *s = STR(str)->str, *p = s + pos;
  uint32_t c;
  if ((unsigned char)*p < 0x80)
    c = (unsigned char)*p++;
  else
    c = idris2_utf8_decode(&p);

  // Character [cons]
  Idris2_Constructor *retVal = idris2_newConstructor(2, 1);
  retVal->args[0] = idris2_mkChar(c);
  retVal->args[1] = IDRIS2_ITERATOR(p - s);
  return (Idris2_Value *)retVal;
}

void idris2_refc_putChar(uint32_t c) {
  char buf[4];
  fwrite(buf, 1, idris2_utf8_encode(c, buf), stdout);
}

// putStr and fPutStr: the whole string, NUL characters included.
void idris2_refc_putStr(Idris2_Value *str) {
  fwrite(STR(str)->str, 1, STR(str)->len, stdout);
}

// getLine.  idris2_getStr (support/c) gives a line in a buffer from malloc,
// which the `C` calling convention copies into a string; this one reads the
// line into a buffer of its own.  Like idris2_getStr, it reads up to and
// including the newline, and keeps what comes before the first '\r', '\n' or
// NUL; at the end of the input, or on an error, the line is empty.
Idris2_Value *idris2_refc_getStr(void) {
  char local[256];
  char *buf = local;
  size_t cap = sizeof(local), len = 0;
  int keep = 1, ascii = 1, c;

#ifdef _WIN32
#define IDRIS2_GETC(f) getc(f)
#else
#define IDRIS2_GETC(f) getc_unlocked(f)
  flockfile(stdin);
#endif
  while ((c = IDRIS2_GETC(stdin)) != EOF && c != '\n') {
    if (!keep)
      continue;
    if (c == '\r' || c == '\0') {
      keep = 0;
      continue;
    }
    if (len == cap) {
      size_t ncap = cap * 2;
      char *nbuf = buf == local ? malloc(ncap) : realloc(buf, ncap);
      IDRIS2_REFC_VERIFY(nbuf, "malloc failed");
      if (buf == local)
        memcpy(nbuf, local, len);
      buf = nbuf;
      cap = ncap;
    }
    if (c >= 0x80)
      ascii = 0;
    buf[len++] = (char)c;
  }
#ifndef _WIN32
  funlockfile(stdin);
#endif
#undef IDRIS2_GETC

  Idris2_String *s = idris2_mkStringN(buf, len);
  if (ascii)
    idris2_setAscii(s);
  if (buf != local)
    free(buf);
  return (Idris2_Value *)s;
}

int idris2_refc_writeLine(void *f, Idris2_Value *str) {
  size_t l = STR(str)->len;
  return fwrite(STR(str)->str, 1, l, (FILE *)f) == l ? 1 : 0;
}

int64_t idris2_refc_stringByteLength(Idris2_Value *str) {
  return (int64_t)STR(str)->len;
}
