#pragma once

#include "cBackend.h"

/* A Char from a code point, or the NUL character when the code point is not a
 * Unicode scalar value (like `cast-int-char` of the Scheme backends). */
#define idris2i_1_isValidCodePoint(c)                                             \
  (((c) >= 0 && (c) <= 0xD7FF) || ((c) >= 0xE000 && (c) <= 0x10FFFF))
Idris2i_1_Value *idris2i_1_mkValidChar(int64_t c);
int64_t idris2i_1_double_to_char_code(double d);
#include <gmp.h>
#include <stdio.h>

/* The low 64 bits of an Integer (of its two's complement), which the casts to
 * the fixed width integers keep: the code generator converts them to the
 * integers that it keeps unboxed (`(uint8_t)idris2i_1_integerLow64(x)`). */
uint64_t idris2i_1_integerLow64Slow(Idris2i_1_Value *x);
static inline uint64_t idris2i_1_integerLow64(Idris2i_1_Value *x) {
  if (idris2i_1_isSmallInteger(x))
    return (uint64_t)idris2i_1_smallInteger(x);
  return idris2i_1_integerLow64Slow(x);
}

#define idris2i_1_cast_Int8_to_Bits8(x)                                           \
  (idris2i_1_mkBits8((uint8_t)idris2i_1_vp_to_Int8(x)))
#define idris2i_1_cast_Int8_to_Bits16(x)                                          \
  (idris2i_1_mkBits16((uint16_t)idris2i_1_vp_to_Int8(x)))
#define idris2i_1_cast_Int8_to_Bits32(x)                                          \
  (idris2i_1_mkBits32((uint32_t)idris2i_1_vp_to_Int8(x)))
#define idris2i_1_cast_Int8_to_Bits64(x)                                          \
  (idris2i_1_mkBits64((uint64_t)idris2i_1_vp_to_Int8(x)))
#define idris2i_1_cast_Int8_to_Int16(x)                                           \
  (idris2i_1_mkInt16((int16_t)idris2i_1_vp_to_Int8(x)))
#define idris2i_1_cast_Int8_to_Int32(x)                                           \
  (idris2i_1_mkInt32((int32_t)idris2i_1_vp_to_Int8(x)))
#define idris2i_1_cast_Int8_to_Int64(x)                                           \
  (idris2i_1_mkInt64((int64_t)idris2i_1_vp_to_Int8(x)))
Idris2i_1_Value *idris2i_1_cast_Int8_to_Integer(Idris2i_1_Value *);
#define idris2i_1_cast_Int8_to_Double(x)                                          \
  (idris2i_1_mkDouble((double)idris2i_1_vp_to_Int8(x)))
#define idris2i_1_cast_Int8_to_Char(x)                                            \
  (idris2i_1_mkValidChar(idris2i_1_vp_to_Int8(x)))
Idris2i_1_Value *idris2i_1_cast_Int8_to_string(Idris2i_1_Value *);

#define idris2i_1_cast_Int16_to_Bits8(x)                                          \
  (idris2i_1_mkBits8((uint8_t)idris2i_1_vp_to_Int16(x)))
#define idris2i_1_cast_Int16_to_Bits16(x)                                         \
  (idris2i_1_mkBits16((uint16_t)idris2i_1_vp_to_Int16(x)))
#define idris2i_1_cast_Int16_to_Bits32(x)                                         \
  (idris2i_1_mkBits32((uint32_t)idris2i_1_vp_to_Int16(x)))
#define idris2i_1_cast_Int16_to_Bits64(x)                                         \
  (idris2i_1_mkBits64((uint64_t)idris2i_1_vp_to_Int16(x)))
#define idris2i_1_cast_Int16_to_Int8(x)                                           \
  (idris2i_1_mkInt8((int8_t)idris2i_1_vp_to_Int16(x)))
#define idris2i_1_cast_Int16_to_Int32(x)                                          \
  (idris2i_1_mkInt32((int32_t)idris2i_1_vp_to_Int16(x)))
#define idris2i_1_cast_Int16_to_Int64(x)                                          \
  (idris2i_1_mkInt64((int64_t)idris2i_1_vp_to_Int16(x)))
Idris2i_1_Value *idris2i_1_cast_Int16_to_Integer(Idris2i_1_Value *);
#define idris2i_1_cast_Int16_to_Double(x)                                         \
  (idris2i_1_mkDouble((double)idris2i_1_vp_to_Int16(x)))
#define idris2i_1_cast_Int16_to_Char(x)                                           \
  (idris2i_1_mkValidChar(idris2i_1_vp_to_Int16(x)))
Idris2i_1_Value *idris2i_1_cast_Int16_to_string(Idris2i_1_Value *);

#define idris2i_1_cast_Int32_to_Bits8(x)                                          \
  (idris2i_1_mkBits8((uint8_t)idris2i_1_vp_to_Int32(x)))
#define idris2i_1_cast_Int32_to_Bits16(x)                                         \
  (idris2i_1_mkBits16((uint16_t)idris2i_1_vp_to_Int32(x)))
#define idris2i_1_cast_Int32_to_Bits32(x)                                         \
  (idris2i_1_mkBits32((uint32_t)idris2i_1_vp_to_Int32(x)))
#define idris2i_1_cast_Int32_to_Bits64(x)                                         \
  (idris2i_1_mkBits64((uint64_t)idris2i_1_vp_to_Int32(x)))
#define idris2i_1_cast_Int32_to_Int8(x)                                           \
  (idris2i_1_mkInt8((int8_t)idris2i_1_vp_to_Int32(x)))
#define idris2i_1_cast_Int32_to_Int16(x)                                          \
  (idris2i_1_mkInt16((int16_t)idris2i_1_vp_to_Int32(x)))
#define idris2i_1_cast_Int32_to_Int64(x)                                          \
  (idris2i_1_mkInt64((int64_t)idris2i_1_vp_to_Int32(x)))
Idris2i_1_Value *idris2i_1_cast_Int32_to_Integer(Idris2i_1_Value *);
#define idris2i_1_cast_Int32_to_Double(x)                                         \
  (idris2i_1_mkDouble((double)idris2i_1_vp_to_Int32(x)))
#define idris2i_1_cast_Int32_to_Char(x)                                           \
  (idris2i_1_mkValidChar(idris2i_1_vp_to_Int32(x)))
Idris2i_1_Value *idris2i_1_cast_Int32_to_string(Idris2i_1_Value *);

#define idris2i_1_cast_Int64_to_Bits8(x)                                          \
  (idris2i_1_mkBits8((uint8_t)idris2i_1_vp_to_Int64(x)))
#define idris2i_1_cast_Int64_to_Bits16(x)                                         \
  (idris2i_1_mkBits16((uint16_t)idris2i_1_vp_to_Int64(x)))
#define idris2i_1_cast_Int64_to_Bits32(x)                                         \
  (idris2i_1_mkBits32((uint32_t)idris2i_1_vp_to_Int64(x)))
#define idris2i_1_cast_Int64_to_Bits64(x)                                         \
  (idris2i_1_mkBits64((uint64_t)idris2i_1_vp_to_Int64(x)))
#define idris2i_1_cast_Int64_to_Int8(x)                                           \
  (idris2i_1_mkInt8((int8_t)idris2i_1_vp_to_Int64(x)))
#define idris2i_1_cast_Int64_to_Int16(x)                                          \
  (idris2i_1_mkInt16((int16_t)idris2i_1_vp_to_Int64(x)))
#define idris2i_1_cast_Int64_to_Int32(x)                                          \
  (idris2i_1_mkInt32((int32_t)idris2i_1_vp_to_Int64(x)))
#define idris2i_1_cast_Int64_to_Int64(x) (idris2i_1_newReference(x))
Idris2i_1_Value *idris2i_1_cast_Int64_to_Integer(Idris2i_1_Value *);
#define idris2i_1_cast_Int64_to_Double(x)                                         \
  (idris2i_1_mkDouble((double)idris2i_1_vp_to_Int64(x)))
#define idris2i_1_cast_Int64_to_Char(x)                                           \
  (idris2i_1_mkValidChar(idris2i_1_vp_to_Int64(x)))
Idris2i_1_Value *idris2i_1_cast_Int64_to_string(Idris2i_1_Value *);

/* Like the Scheme backends, a Double is truncated and then wrapped around to
 * the width of the result.  NaN and the infinities give 0 (the Scheme
 * backends raise an exception). */
uint64_t idris2i_1_double_to_wrapped(double d);
#define idris2i_1_cast_Double_to_Bits8(x)                                         \
  (idris2i_1_mkBits8((uint8_t)idris2i_1_double_to_wrapped(idris2i_1_vp_to_Double(x))))
#define idris2i_1_cast_Double_to_Bits16(x)                                        \
  (idris2i_1_mkBits16((uint16_t)idris2i_1_double_to_wrapped(idris2i_1_vp_to_Double(x))))
#define idris2i_1_cast_Double_to_Bits32(x)                                        \
  (idris2i_1_mkBits32((uint32_t)idris2i_1_double_to_wrapped(idris2i_1_vp_to_Double(x))))
#define idris2i_1_cast_Double_to_Bits64(x)                                        \
  (idris2i_1_mkBits64(idris2i_1_double_to_wrapped(idris2i_1_vp_to_Double(x))))
#define idris2i_1_cast_Double_to_Int8(x)                                          \
  (idris2i_1_mkInt8((int8_t)idris2i_1_double_to_wrapped(idris2i_1_vp_to_Double(x))))
#define idris2i_1_cast_Double_to_Int16(x)                                         \
  (idris2i_1_mkInt16((int16_t)idris2i_1_double_to_wrapped(idris2i_1_vp_to_Double(x))))
#define idris2i_1_cast_Double_to_Int32(x)                                         \
  (idris2i_1_mkInt32((int32_t)idris2i_1_double_to_wrapped(idris2i_1_vp_to_Double(x))))
#define idris2i_1_cast_Double_to_Int64(x)                                         \
  (idris2i_1_mkInt64((int64_t)idris2i_1_double_to_wrapped(idris2i_1_vp_to_Double(x))))
Idris2i_1_Value *idris2i_1_cast_Double_to_Integer(Idris2i_1_Value *);
/* The casts of a C double (which the code generator keeps unboxed, see
 * Compiler.RefC.Unbox) to and from an Integer. */
Idris2i_1_Value *idris2i_1_mkIntegerFromDouble(double d);
double idris2i_1_integerToDoubleSlow(Idris2i_1_Value *x);
static inline double idris2i_1_integerToDouble(Idris2i_1_Value *x) {
  if (idris2i_1_isSmallInteger(x))
    return (double)idris2i_1_smallInteger(x);
  return idris2i_1_integerToDoubleSlow(x);
}
#define idris2i_1_cast_Double_to_Char(x)                                          \
  (idris2i_1_mkValidChar(idris2i_1_double_to_char_code(idris2i_1_vp_to_Double(x))))
Idris2i_1_Value *idris2i_1_cast_Double_to_string(Idris2i_1_Value *);

#define idris2i_1_cast_Char_to_Bits8(x)                                           \
  (idris2i_1_mkBits8((uint8_t)idris2i_1_vp_to_Char(x)))
#define idris2i_1_cast_Char_to_Bits16(x)                                          \
  (idris2i_1_mkBits16((uint16_t)idris2i_1_vp_to_Char(x)))
#define idris2i_1_cast_Char_to_Bits32(x)                                          \
  (idris2i_1_mkBits32((uint32_t)idris2i_1_vp_to_Char(x)))
#define idris2i_1_cast_Char_to_Bits64(x)                                          \
  (idris2i_1_mkBits64((uint64_t)idris2i_1_vp_to_Char(x)))
#define idris2i_1_cast_Char_to_Int8(x)                                            \
  (idris2i_1_mkInt8((int8_t)idris2i_1_vp_to_Char(x)))
#define idris2i_1_cast_Char_to_Int16(x)                                           \
  (idris2i_1_mkInt16((int16_t)idris2i_1_vp_to_Char(x)))
#define idris2i_1_cast_Char_to_Int32(x)                                           \
  (idris2i_1_mkInt32((int32_t)idris2i_1_vp_to_Char(x)))
#define idris2i_1_cast_Char_to_Int64(x)                                           \
  (idris2i_1_mkInt64((int64_t)idris2i_1_vp_to_Char(x)))
Idris2i_1_Value *idris2i_1_cast_Char_to_Integer(Idris2i_1_Value *);
#define idris2i_1_cast_Char_to_Double(x)                                          \
  (idris2i_1_mkDouble((double)idris2i_1_vp_to_Char(x)))
Idris2i_1_Value *idris2i_1_cast_Char_to_string(Idris2i_1_Value *);

Idris2i_1_Value *idris2i_1_cast_string_to_Bits8(Idris2i_1_Value *);
Idris2i_1_Value *idris2i_1_cast_string_to_Bits16(Idris2i_1_Value *);
Idris2i_1_Value *idris2i_1_cast_string_to_Bits32(Idris2i_1_Value *);
Idris2i_1_Value *idris2i_1_cast_string_to_Bits64(Idris2i_1_Value *);
Idris2i_1_Value *idris2i_1_cast_string_to_Int8(Idris2i_1_Value *);
Idris2i_1_Value *idris2i_1_cast_string_to_Int16(Idris2i_1_Value *);
Idris2i_1_Value *idris2i_1_cast_string_to_Int32(Idris2i_1_Value *);
Idris2i_1_Value *idris2i_1_cast_string_to_Int64(Idris2i_1_Value *);
Idris2i_1_Value *idris2i_1_cast_string_to_Integer(Idris2i_1_Value *);
Idris2i_1_Value *idris2i_1_cast_string_to_Double(Idris2i_1_Value *);
Idris2i_1_Value *idris2i_1_cast_string_to_Char(Idris2i_1_Value *);

#define idris2i_1_cast_Bits8_to_Bits16(x)                                         \
  (idris2i_1_mkBits16((uint16_t)idris2i_1_vp_to_Bits8(x)))
#define idris2i_1_cast_Bits8_to_Bits32(x)                                         \
  (idris2i_1_mkBits32((uint32_t)idris2i_1_vp_to_Bits8(x)))
#define idris2i_1_cast_Bits8_to_Bits64(x)                                         \
  (idris2i_1_mkBits64((uint64_t)idris2i_1_vp_to_Bits8(x)))
#define idris2i_1_cast_Bits8_to_Int8(x)                                           \
  (idris2i_1_mkInt8((int8_t)idris2i_1_vp_to_Bits8(x)))
#define idris2i_1_cast_Bits8_to_Int16(x)                                          \
  (idris2i_1_mkInt16((int16_t)idris2i_1_vp_to_Bits8(x)))
#define idris2i_1_cast_Bits8_to_Int32(x)                                          \
  (idris2i_1_mkInt32((int32_t)idris2i_1_vp_to_Bits8(x)))
#define idris2i_1_cast_Bits8_to_Int64(x)                                          \
  (idris2i_1_mkInt64((int64_t)idris2i_1_vp_to_Bits8(x)))
Idris2i_1_Value *idris2i_1_cast_Bits8_to_Integer(Idris2i_1_Value *input);
#define idris2i_1_cast_Bits8_to_Double(x)                                         \
  (idris2i_1_mkDouble((double)idris2i_1_vp_to_Bits8(x)))
#define idris2i_1_cast_Bits8_to_Char(x)                                           \
  (idris2i_1_mkValidChar(idris2i_1_vp_to_Bits8(x)))
Idris2i_1_Value *idris2i_1_cast_Bits8_to_string(Idris2i_1_Value *input);

#define idris2i_1_cast_Bits16_to_Bits8(x)                                         \
  (idris2i_1_mkBits8((uint8_t)idris2i_1_vp_to_Bits16(x)))
#define idris2i_1_cast_Bits16_to_Bits32(x)                                        \
  (idris2i_1_mkBits32((uint32_t)idris2i_1_vp_to_Bits16(x)))
#define idris2i_1_cast_Bits16_to_Bits64(x)                                        \
  (idris2i_1_mkBits64((uint64_t)idris2i_1_vp_to_Bits16(x)))
#define idris2i_1_cast_Bits16_to_Int8(x)                                          \
  (idris2i_1_mkInt8((int8_t)idris2i_1_vp_to_Bits16(x)))
#define idris2i_1_cast_Bits16_to_Int16(x)                                         \
  (idris2i_1_mkInt16((int16_t)idris2i_1_vp_to_Bits16(x)))
#define idris2i_1_cast_Bits16_to_Int32(x)                                         \
  (idris2i_1_mkInt32((int32_t)idris2i_1_vp_to_Bits16(x)))
#define idris2i_1_cast_Bits16_to_Int64(x)                                         \
  (idris2i_1_mkInt64((int64_t)idris2i_1_vp_to_Bits16(x)))
Idris2i_1_Value *idris2i_1_cast_Bits16_to_Integer(Idris2i_1_Value *input);
#define idris2i_1_cast_Bits16_to_Double(x)                                        \
  (idris2i_1_mkDouble((double)idris2i_1_vp_to_Bits16(x)))
#define idris2i_1_cast_Bits16_to_Char(x)                                          \
  (idris2i_1_mkValidChar(idris2i_1_vp_to_Bits16(x)))
Idris2i_1_Value *idris2i_1_cast_Bits16_to_string(Idris2i_1_Value *input);

#define idris2i_1_cast_Bits32_to_Bits8(x)                                         \
  (idris2i_1_mkBits8((uint8_t)idris2i_1_vp_to_Bits32(x)))
#define idris2i_1_cast_Bits32_to_Bits16(x)                                        \
  (idris2i_1_mkBits16((uint16_t)idris2i_1_vp_to_Bits32(x)))
#define idris2i_1_cast_Bits32_to_Bits64(x)                                        \
  (idris2i_1_mkBits64((uint64_t)idris2i_1_vp_to_Bits32(x)))
#define idris2i_1_cast_Bits32_to_Int8(x)                                          \
  (idris2i_1_mkInt8((int8_t)idris2i_1_vp_to_Bits32(x)))
#define idris2i_1_cast_Bits32_to_Int16(x)                                         \
  (idris2i_1_mkInt16((int16_t)idris2i_1_vp_to_Bits32(x)))
#define idris2i_1_cast_Bits32_to_Int32(x)                                         \
  (idris2i_1_mkInt32((int32_t)idris2i_1_vp_to_Bits32(x)))
#define idris2i_1_cast_Bits32_to_Int64(x)                                         \
  (idris2i_1_mkInt64((int64_t)idris2i_1_vp_to_Bits32(x)))
Idris2i_1_Value *idris2i_1_cast_Bits32_to_Integer(Idris2i_1_Value *input);
#define idris2i_1_cast_Bits32_to_Double(x)                                        \
  (idris2i_1_mkDouble((double)idris2i_1_vp_to_Bits32(x)))
#define idris2i_1_cast_Bits32_to_Char(x)                                          \
  (idris2i_1_mkValidChar(idris2i_1_vp_to_Bits32(x)))
Idris2i_1_Value *idris2i_1_cast_Bits32_to_string(Idris2i_1_Value *input);

#define idris2i_1_cast_Bits64_to_Bits8(x)                                         \
  (idris2i_1_mkBits8((uint8_t)idris2i_1_vp_to_Bits64(x)))
#define idris2i_1_cast_Bits64_to_Bits16(x)                                        \
  (idris2i_1_mkBits16((uint16_t)idris2i_1_vp_to_Bits64(x)))
#define idris2i_1_cast_Bits64_to_Bits32(x)                                        \
  (idris2i_1_mkBits32((uint32_t)idris2i_1_vp_to_Bits64(x)))
#define idris2i_1_cast_Bits64_to_Int8(x)                                          \
  (idris2i_1_mkInt8((int8_t)idris2i_1_vp_to_Bits64(x)))
#define idris2i_1_cast_Bits64_to_Int16(x)                                         \
  (idris2i_1_mkInt16((int16_t)idris2i_1_vp_to_Bits64(x)))
#define idris2i_1_cast_Bits64_to_Int32(x)                                         \
  (idris2i_1_mkInt32((int32_t)idris2i_1_vp_to_Bits64(x)))
#define idris2i_1_cast_Bits64_to_Int64(x)                                         \
  (idris2i_1_mkInt64((int64_t)idris2i_1_vp_to_Bits64(x)))
Idris2i_1_Value *idris2i_1_cast_Bits64_to_Integer(Idris2i_1_Value *input);
#define idris2i_1_cast_Bits64_to_Double(x)                                        \
  (idris2i_1_mkDouble((double)idris2i_1_vp_to_Bits64(x)))
#define idris2i_1_cast_Bits64_to_Char(x)                                          \
  (idris2i_1_mkValidChar(idris2i_1_vp_to_Bits64(x)))
Idris2i_1_Value *idris2i_1_cast_Bits64_to_string(Idris2i_1_Value *input);

Idris2i_1_Value *idris2i_1_cast_Integer_to_Bits8(Idris2i_1_Value *input);
Idris2i_1_Value *idris2i_1_cast_Integer_to_Bits16(Idris2i_1_Value *input);
Idris2i_1_Value *idris2i_1_cast_Integer_to_Bits32(Idris2i_1_Value *input);
Idris2i_1_Value *idris2i_1_cast_Integer_to_Bits64(Idris2i_1_Value *input);
Idris2i_1_Value *idris2i_1_cast_Integer_to_Int8(Idris2i_1_Value *input);
Idris2i_1_Value *idris2i_1_cast_Integer_to_Int16(Idris2i_1_Value *input);
Idris2i_1_Value *idris2i_1_cast_Integer_to_Int32(Idris2i_1_Value *input);
Idris2i_1_Value *idris2i_1_cast_Integer_to_Int64(Idris2i_1_Value *input);
Idris2i_1_Value *idris2i_1_cast_Integer_to_Double(Idris2i_1_Value *input);
Idris2i_1_Value *idris2i_1_cast_Integer_to_Char(Idris2i_1_Value *input);
Idris2i_1_Value *idris2i_1_cast_Integer_to_string(Idris2i_1_Value *input);
