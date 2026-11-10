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

/* Skip at most n code points. */
static char const *utf8_skip(char const *s, int64_t n) {
  while (n > 0 && *s != '\0') {
    if ((unsigned char)*s < 0x80)
      s++;
    else
      idris2_utf8_decode(&s);
    n--;
  }
  return s;
}

int64_t idris2_utf8_length(char const *s) {
  int64_t n = 0;
  while (*s != '\0') {
    if ((unsigned char)*s < 0x80)
      s++;
    else
      idris2_utf8_decode(&s);
    n++;
  }
  return n;
}

/* An Idris String that holds the l bytes at s. */
static Idris2_Value *stringOfBytes(char const *s, size_t l) {
  Idris2_String *retVal = idris2_mkEmptyString(l + 1);
  if (l > 0)
    memcpy(retVal->str, s, l);
  return (Idris2_Value *)retVal;
}

Idris2_Value *stringLength(Idris2_Value *str) {
  return idris2_mkInt64(idris2_utf8_length(((Idris2_String *)str)->str));
}

Idris2_Value *head(Idris2_Value *str) {
  return idris2_cast_string_to_Char(str);
}

Idris2_Value *tail(Idris2_Value *input) {
  char const *s = ((Idris2_String *)input)->str;
  char const *rest = utf8_skip(s, 1);
  return stringOfBytes(rest, strlen(rest));
}

Idris2_Value *reverse(Idris2_Value *str) {
  char const *input = ((Idris2_String *)str)->str;
  size_t l = strlen(input);
  Idris2_String *retVal = idris2_mkEmptyString(l + 1);
  if (l == 0)
    return (Idris2_Value *)retVal;

  /* Copy the encoding of each code point to the mirrored position. */
  char *end = retVal->str + l;
  char const *p = input;
  while (*p != '\0') {
    char const *start = p;
    if ((unsigned char)*p < 0x80)
      p++;
    else
      idris2_utf8_decode(&p);
    end -= p - start;
    memcpy(end, start, p - start);
  }
  return (Idris2_Value *)retVal;
}

Idris2_Value *strIndex(Idris2_Value *str, Idris2_Value *i) {
  int64_t idx = idris2_vp_to_Int64(i);
  char const *s = ((Idris2_String *)str)->str;
  if (idx < 0)
    return idris2_mkChar(0);
  s = utf8_skip(s, idx);
  return idris2_mkChar(*s == '\0' ? 0 : idris2_utf8_decode(&s));
}

Idris2_Value *strCons(Idris2_Value *c, Idris2_Value *str) {
  char const *s = ((Idris2_String *)str)->str;
  uint32_t ch = idris2_vp_to_Char(c);
  size_t l = strlen(s);
  int cl = idris2_utf8_encodedLength(ch);
  Idris2_String *retVal = idris2_mkEmptyString(cl + l + 1);
  idris2_utf8_encode(ch, retVal->str);
  memcpy(retVal->str + cl, s, l);
  return (Idris2_Value *)retVal;
}

Idris2_Value *strAppend(Idris2_Value *a, Idris2_Value *b) {
  size_t la = strlen(((Idris2_String *)a)->str);
  size_t lb = strlen(((Idris2_String *)b)->str);
  Idris2_String *retVal = idris2_mkEmptyString(la + lb + 1);
  if (la + lb == 0)
    return (Idris2_Value *)retVal;
  memcpy(retVal->str, ((Idris2_String *)a)->str, la);
  memcpy(retVal->str + la, ((Idris2_String *)b)->str, lb);
  return (Idris2_Value *)retVal;
}

/* Like the Scheme backends: a negative start or length counts as 0, and the
 * substring stops at the end of the string. */
Idris2_Value *strSubstr(Idris2_Value *start, Idris2_Value *len,
                        Idris2_Value *s) {
  char const *input = ((Idris2_String *)s)->str;
  int64_t offset = idris2_vp_to_Int64(start);
  int64_t l = idris2_vp_to_Int64(len);
  if (offset < 0)
    offset = 0;
  if (l < 0)
    l = 0;

  char const *from = utf8_skip(input, offset);
  char const *to = utf8_skip(from, l);
  return stringOfBytes(from, to - from);
}

char *fastPack(Idris2_Value *charList) {
  Idris2_Constructor *current;

  size_t l = 0;
  current = (Idris2_Constructor *)charList;
  while (current != NULL) {
    l += idris2_utf8_encodedLength(idris2_vp_to_Char(current->args[0]));
    current = (Idris2_Constructor *)current->args[1];
  }

  char *retVal = malloc(l + 1);
  IDRIS2_REFC_VERIFY(retVal, "malloc failed");
  retVal[l] = 0;

  char *p = retVal;
  current = (Idris2_Constructor *)charList;
  while (current != NULL) {
    p += idris2_utf8_encode(idris2_vp_to_Char(current->args[0]), p);
    current = (Idris2_Constructor *)current->args[1];
  }

  return retVal;
}

Idris2_Value *fastUnpack(char *str) {
  char const *p = str;
  if (*p == '\0') {
    return NULL;
  }

  Idris2_Constructor *retVal = idris2_newConstructor(2, 1);
  retVal->args[0] = idris2_mkChar(idris2_utf8_decode(&p));

  Idris2_Constructor *current = (Idris2_Constructor *)retVal;
  Idris2_Constructor *next;
  while (*p != '\0') {
    next = idris2_newConstructor(2, 1);
    next->args[0] = idris2_mkChar(idris2_utf8_decode(&p));
    current->args[1] = (Idris2_Value *)next;
    current = next;
  }
  current->args[1] = NULL;

  return (Idris2_Value *)retVal;
}

char *fastConcat(Idris2_Value *strList) {
  Idris2_Constructor *current;

  int totalLength = 0;
  current = (Idris2_Constructor *)strList;
  while (current != NULL) {
    totalLength += strlen(((Idris2_String *)current->args[0])->str);
    current = (Idris2_Constructor *)current->args[1];
  }

  char *retVal = malloc(totalLength + 1);
  retVal[totalLength] = '\0';

  char *currentStr;
  int currentStrLen;
  int offset = 0;
  current = (Idris2_Constructor *)strList;
  while (current != NULL) {
    currentStr = ((Idris2_String *)current->args[0])->str;
    currentStrLen = strlen(currentStr);
    memcpy(retVal + offset, currentStr, currentStrLen);

    offset += currentStrLen;
    current = (Idris2_Constructor *)current->args[1];
  }

  return retVal;
}

typedef struct {
  char *str;
  int pos;
} String_Iterator;

Idris2_Value *stringIteratorNew(char *str) {
  int l = strlen(str);

  String_Iterator *it = (String_Iterator *)malloc(sizeof(String_Iterator));
  IDRIS2_REFC_VERIFY(it, "malloc failed");
  it->str = (char *)malloc(l + 1);
  it->pos = 0;
  memcpy(it->str, str, l + 1); // Take a copy of str, in case it gets GCed

  return (Idris2_Value *)idris2_makeGCPointer(
      it, (Idris2_Closure *)idris2_mkClosure(
              (Idris2_Value * (*)()) onCollectStringIterator, 2, 0));
}

Idris2_Value *onCollectStringIterator(Idris2_Pointer *ptr, void *null) {
  String_Iterator *it = (String_Iterator *)ptr->p;
  free(it->str);
  free(it);
  return NULL;
}

Idris2_Value *stringIteratorToString(void *a, char *str, Idris2_Value *it_p,
                                     Idris2_Closure *f) {
  String_Iterator *it = ((Idris2_GCPointer *)it_p)->p->p;
  Idris2_Value *strVal = (Idris2_Value *)idris2_mkString(it->str + it->pos);
  return idris2_apply_closure(idris2_newReference((Idris2_Value *)f), strVal);
}

// contrib/Data.String.Iterator.uncons :
//   (str : String) -> (1 it : StringIterator str) -> UnconsResult str
Idris2_Value *stringIteratorNext(char *s, Idris2_Value *it_p) {
  String_Iterator *it = (String_Iterator *)((Idris2_GCPointer *)it_p)->p->p;
  char const *p = it->str + it->pos;

  if (*p == '\0')
    return NULL; // EOF [nil]

  uint32_t c = idris2_utf8_decode(&p);
  it->pos = p - it->str; // Ok to do this as StringIterator linear

  // Character [cons]
  Idris2_Constructor *retVal =
      (Idris2_Constructor *)idris2_newConstructor(2, 1);
  retVal->args[0] = idris2_mkChar(c);
  retVal->args[1] = idris2_newReference(it_p);

  return (Idris2_Value *)retVal;
}

void idris2_refc_putChar(uint32_t c) {
  char buf[4];
  fwrite(buf, 1, idris2_utf8_encode(c, buf), stdout);
}
