#pragma once

#include "cBackend.h"
#include "casts.h"

/* UTF-8 helpers.  idris2_utf8_decode reads the code point at *p and moves *p
 * past it; invalid bytes decode to U+FFFD.  idris2_utf8_encode writes 1 to 4
 * bytes and returns their number. */
uint32_t idris2_utf8_decode(char const **p);
int idris2_utf8_encode(uint32_t c, char *out);
int idris2_utf8_encodedLength(uint32_t c);
int64_t idris2_utf8_length(char const *s, size_t len);
// The number of code points of a string (counted once, see stringOps.c).
int64_t idris2_stringCodePoints(Idris2_Value *str);

// Compare two strings, byte by byte (which, for UTF-8, is the order of the
// code points).
int idris2_compareStrings(Idris2_Value *a, Idris2_Value *b);

Idris2_Value *stringLength(Idris2_Value *str);
Idris2_Value *head(Idris2_Value *str);
Idris2_Value *tail(Idris2_Value *str);
Idris2_Value *reverse(Idris2_Value *str);
Idris2_Value *strIndex(Idris2_Value *str, Idris2_Value *i);
Idris2_Value *strCons(Idris2_Value *c, Idris2_Value *str);
Idris2_Value *strAppend(Idris2_Value *a, Idris2_Value *b);
Idris2_Value *strSubstr(Idris2_Value *start, Idris2_Value *len,
                        Idris2_Value *s);
// The functions of the `RefC` calling convention take and give strings as
// Idris values (see RefC.idr).
Idris2_Value *fastPack(Idris2_Value *charList);
Idris2_Value *fastUnpack(Idris2_Value *str);
Idris2_Value *fastConcat(Idris2_Value *strList);

// Data.String.Iterator: an iterator is an unboxed byte offset into the string
// (see stringOps.c).
Idris2_Value *stringIteratorNew(Idris2_Value *str);
Idris2_Value *stringIteratorToString(void *a, Idris2_Value *str,
                                     Idris2_Value *it, Idris2_Closure *f);
Idris2_Value *stringIteratorNext(Idris2_Value *str, Idris2_Value *it);

/* putChar: write the UTF-8 encoding of a character to stdout. */
void idris2_refc_putChar(uint32_t c);
void idris2_refc_putStr(Idris2_Value *str);
int idris2_refc_writeLine(void *f, Idris2_Value *str);
int64_t idris2_refc_stringByteLength(Idris2_Value *str);
