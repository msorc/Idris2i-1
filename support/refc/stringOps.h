#pragma once

#include "cBackend.h"
#include "casts.h"

/* UTF-8 helpers.  idris2i_1_utf8_decode reads the code point at *p and moves *p
 * past it; invalid bytes decode to U+FFFD.  idris2i_1_utf8_encode writes 1 to 4
 * bytes and returns their number. */
uint32_t idris2i_1_utf8_decode(char const **p);
int idris2i_1_utf8_encode(uint32_t c, char *out);
int idris2i_1_utf8_encodedLength(uint32_t c);
int64_t idris2i_1_utf8_length(char const *s, size_t len);
// The number of code points of a string (counted once, see stringOps.c).
int64_t idris2i_1_stringCodePoints(Idris2i_1_Value *str);

// Compare two strings, byte by byte (which, for UTF-8, is the order of the
// code points).
int idris2i_1_compareStrings(Idris2i_1_Value *a, Idris2i_1_Value *b);

Idris2i_1_Value *stringLength(Idris2i_1_Value *str);
Idris2i_1_Value *head(Idris2i_1_Value *str);
Idris2i_1_Value *tail(Idris2i_1_Value *str);
Idris2i_1_Value *reverse(Idris2i_1_Value *str);
Idris2i_1_Value *strIndex(Idris2i_1_Value *str, Idris2i_1_Value *i);
Idris2i_1_Value *strCons(Idris2i_1_Value *c, Idris2i_1_Value *str);
Idris2i_1_Value *strAppend(Idris2i_1_Value *a, Idris2i_1_Value *b);
Idris2i_1_Value *strSubstr(Idris2i_1_Value *start, Idris2i_1_Value *len,
                        Idris2i_1_Value *s);
// The functions of the `RefC` calling convention take and give strings as
// Idris values (see RefC.idr).
Idris2i_1_Value *fastPack(Idris2i_1_Value *charList);
Idris2i_1_Value *fastUnpack(Idris2i_1_Value *str);
Idris2i_1_Value *fastConcat(Idris2i_1_Value *strList);

// Data.String.Iterator: an iterator is an unboxed byte offset into the string
// (see stringOps.c).
Idris2i_1_Value *stringIteratorNew(Idris2i_1_Value *str);
Idris2i_1_Value *stringIteratorToString(void *a, Idris2i_1_Value *str,
                                     Idris2i_1_Value *it, Idris2i_1_Closure *f);
Idris2i_1_Value *stringIteratorNext(Idris2i_1_Value *str, Idris2i_1_Value *it);

/* putChar: write the UTF-8 encoding of a character to stdout. */
void idris2i_1_refc_putChar(uint32_t c);
void idris2i_1_refc_putStr(Idris2i_1_Value *str);
Idris2i_1_Value *idris2i_1_refc_getStr(void);
int idris2i_1_refc_writeLine(void *f, Idris2i_1_Value *str);
int64_t idris2i_1_refc_stringByteLength(Idris2i_1_Value *str);
