#pragma once

#include "cBackend.h"
#include <float.h>
#include <gmp.h>
#include <math.h>
#include "memoryManagement.h"

int idris2_compareStrings(Idris2_Value *a, Idris2_Value *b);

// Compare two Integers (like mpz_cmp, the sign of the result tells).
int idris2_cmpIntegerSlow(Idris2_Value *x, Idris2_Value *y);
static inline int idris2_cmpInteger(Idris2_Value *x, Idris2_Value *y) {
  if (idris2_isSmallInteger(x) && idris2_isSmallInteger(y)) {
    int64_t a = idris2_smallInteger(x), b = idris2_smallInteger(y);
    return (a > b) - (a < b);
  }
  return idris2_cmpIntegerSlow(x, y);
}

// Is the Integer `x` equal to `n` (an integer literal of 32 bits)?
static inline int idris2_eqIntegerSmall(Idris2_Value *x, int64_t n) {
  if (idris2_isSmallInteger(x))
    return idris2_smallInteger(x) == n;
  return mpz_cmp_si(((Idris2_Integer *)x)->i, (long)n) == 0;
}

// A division by zero (undefined behaviour in C, which traps on x86) stops the
// program with an error, like the exception of the Scheme back ends.  The
// test of the divisor is one well predicted branch (and none for a constant).
// (`__noreturn__`: `noreturn` may be the macro of stdnoreturn.h)
#if defined(__GNUC__) || defined(__clang__)
__attribute__((__noreturn__, __cold__))
#endif
void idris2_divideByZero(void);
#define IDRIS2_CHECK_DIVISOR(d)                                                \
  do {                                                                         \
    if (__builtin_expect((d) == 0, 0))                                         \
      idris2_divideByZero();                                                   \
  } while (0)

#define idris2_binop(ty, op, l, r)                                             \
  ((Idris2_Value *)idris2_mk##ty(idris2_vp_to_##ty(l) op idris2_vp_to_##ty(r)))

/* The unsigned types wrap around: the constructors (idris2_mkBits8, ...)
   truncate the result.  The small ones are computed on `uint32_t` instead of
   the `int` that C promotes them to, which could overflow (`65535 * 65535`). */
#define idris2_uop(ty, op, l, r)                                               \
  ((Idris2_Value *)idris2_mk##ty((uint32_t)idris2_vp_to_##ty(l)                \
                                     op(uint32_t) idris2_vp_to_##ty(r)))

/* Signed fixed size integers wrap around, like in the other backends.  In C
   an overflow of a signed type is undefined behaviour (which the C compiler
   may assume never happens), so the arithmetic is done on unsigned integers
   of at least the same width, and converted back. */
#define idris2_wrapop(ty, cty, uty, op, l, r)                                  \
  ((Idris2_Value *)idris2_mk##ty(                                             \
      (cty)((uty)idris2_vp_to_##ty(l) op (uty)idris2_vp_to_##ty(r))))
#define idris2_wrapop8(op, l, r) idris2_wrapop(Int8, int8_t, uint32_t, op, l, r)
#define idris2_wrapop16(op, l, r)                                              \
  idris2_wrapop(Int16, int16_t, uint32_t, op, l, r)
#define idris2_wrapop32(op, l, r)                                              \
  idris2_wrapop(Int32, int32_t, uint32_t, op, l, r)
#define idris2_wrapop64(op, l, r)                                              \
  idris2_wrapop(Int64, int64_t, uint64_t, op, l, r)

/* add */
#define idris2_add_Bits8(l, r) (idris2_uop(Bits8, +, l, r))
#define idris2_add_Bits16(l, r) (idris2_uop(Bits16, +, l, r))
#define idris2_add_Bits32(l, r) (idris2_binop(Bits32, +, l, r))
#define idris2_add_Bits64(l, r) (idris2_binop(Bits64, +, l, r))
#define idris2_add_Int8(l, r) (idris2_wrapop8(+, l, r))
#define idris2_add_Int16(l, r) (idris2_wrapop16(+, l, r))
#define idris2_add_Int32(l, r) (idris2_wrapop32(+, l, r))
#define idris2_add_Int64(l, r) (idris2_wrapop64(+, l, r))
Idris2_Value *idris2_add_IntegerSlow(Idris2_Value *x, Idris2_Value *y);
static inline Idris2_Value *idris2_add_Integer(Idris2_Value *x,
                                                Idris2_Value *y) {
  // (no overflow: the small integers have 32 bits)
  if (idris2_isSmallInteger(x) && idris2_isSmallInteger(y))
    return idris2_mkIntegerFromInt64(idris2_smallInteger(x) +
                                     idris2_smallInteger(y));
  return idris2_add_IntegerSlow(x, y);
}
#define idris2_add_Double(l, r) (idris2_binop(Double, +, l, r))

/* sub */
#define idris2_sub_Bits8(l, r) (idris2_uop(Bits8, -, l, r))
#define idris2_sub_Bits16(l, r) (idris2_uop(Bits16, -, l, r))
#define idris2_sub_Bits32(l, r) (idris2_binop(Bits32, -, l, r))
#define idris2_sub_Bits64(l, r) (idris2_binop(Bits64, -, l, r))
#define idris2_sub_Int8(l, r) (idris2_wrapop8(-, l, r))
#define idris2_sub_Int16(l, r) (idris2_wrapop16(-, l, r))
#define idris2_sub_Int32(l, r) (idris2_wrapop32(-, l, r))
#define idris2_sub_Int64(l, r) (idris2_wrapop64(-, l, r))
Idris2_Value *idris2_sub_IntegerSlow(Idris2_Value *x, Idris2_Value *y);
static inline Idris2_Value *idris2_sub_Integer(Idris2_Value *x,
                                                Idris2_Value *y) {
  // (no overflow: the small integers have 32 bits)
  if (idris2_isSmallInteger(x) && idris2_isSmallInteger(y))
    return idris2_mkIntegerFromInt64(idris2_smallInteger(x) -
                                     idris2_smallInteger(y));
  return idris2_sub_IntegerSlow(x, y);
}
#define idris2_sub_Double(l, r) (idris2_binop(Double, -, l, r))

/* negate */
#define idris2_negate_Bits8(x)                                                 \
  (idris2_mkBits8(0u - (uint32_t)idris2_vp_to_Bits8(x)))
#define idris2_negate_Bits16(x)                                                \
  (idris2_mkBits16(0u - (uint32_t)idris2_vp_to_Bits16(x)))
#define idris2_negate_Bits32(x)                                                \
  (idris2_mkBits32(0u - (uint32_t)idris2_vp_to_Bits32(x)))
#define idris2_negate_Bits64(x)                                                \
  (idris2_mkBits64(0u - (uint64_t)idris2_vp_to_Bits64(x)))
#define idris2_negate_Int8(x)                                                 \
  (idris2_mkInt8((int8_t)(0u - (uint32_t)idris2_vp_to_Int8(x))))
#define idris2_negate_Int16(x)                                                 \
  (idris2_mkInt16((int16_t)(0u - (uint32_t)idris2_vp_to_Int16(x))))
#define idris2_negate_Int32(x)                                                 \
  (idris2_mkInt32((int32_t)(0u - (uint32_t)idris2_vp_to_Int32(x))))
#define idris2_negate_Int64(x)                                                 \
  (idris2_mkInt64((int64_t)(0u - (uint64_t)idris2_vp_to_Int64(x))))
Idris2_Value *idris2_negate_Integer(Idris2_Value *x);
#define idris2_negate_Double(x) (idris2_mkDouble(-(idris2_vp_to_Double(x))))

/* mul */
#define idris2_mul_Bits8(l, r) (idris2_uop(Bits8, *, l, r))
#define idris2_mul_Bits16(l, r) (idris2_uop(Bits16, *, l, r))
#define idris2_mul_Bits32(l, r) (idris2_binop(Bits32, *, l, r))
#define idris2_mul_Bits64(l, r) (idris2_binop(Bits64, *, l, r))
#define idris2_mul_Int8(l, r) (idris2_wrapop8(*, l, r))
#define idris2_mul_Int16(l, r) (idris2_wrapop16(*, l, r))
#define idris2_mul_Int32(l, r) (idris2_wrapop32(*, l, r))
#define idris2_mul_Int64(l, r) (idris2_wrapop64(*, l, r))
Idris2_Value *idris2_mul_IntegerSlow(Idris2_Value *x, Idris2_Value *y);
static inline Idris2_Value *idris2_mul_Integer(Idris2_Value *x,
                                                Idris2_Value *y) {
  // (no overflow: the small integers have 32 bits)
  if (idris2_isSmallInteger(x) && idris2_isSmallInteger(y))
    return idris2_mkIntegerFromInt64(idris2_smallInteger(x) *
                                     idris2_smallInteger(y));
  return idris2_mul_IntegerSlow(x, y);
}
#define idris2_mul_Double(l, r) (idris2_binop(Double, *, l, r))

/* div */
#define IDRIS2_UNSIGNED_DIVMOD(ty, cty)                                        \
  static inline Idris2_Value *idris2_div_##ty(Idris2_Value *x,                 \
                                              Idris2_Value *y) {               \
    cty d = idris2_vp_to_##ty(y);                                              \
    IDRIS2_CHECK_DIVISOR(d);                                                   \
    return (Idris2_Value *)idris2_mk##ty(idris2_vp_to_##ty(x) / d);            \
  }                                                                            \
  static inline Idris2_Value *idris2_mod_##ty(Idris2_Value *x,                 \
                                              Idris2_Value *y) {               \
    cty d = idris2_vp_to_##ty(y);                                              \
    IDRIS2_CHECK_DIVISOR(d);                                                   \
    return (Idris2_Value *)idris2_mk##ty(idris2_vp_to_##ty(x) % d);            \
  }
IDRIS2_UNSIGNED_DIVMOD(Bits8, uint8_t)
IDRIS2_UNSIGNED_DIVMOD(Bits16, uint16_t)
IDRIS2_UNSIGNED_DIVMOD(Bits32, uint32_t)
IDRIS2_UNSIGNED_DIVMOD(Bits64, uint64_t)

// The signed `div` and `mod` are Euclidean (`mod` is never negative), unlike
// C's `/` and `%`, which truncate.  They are inline, so that a division by a
// constant (`x `mod` 2`) is compiled to shifts and masks instead of a
// division instruction.

// The Euclidean remainder: the truncated one, plus the absolute value of the
// divisor when it is negative.  (`r - denom` and `r + denom` cannot overflow,
// as `r` is between them.)  The divisor -1 is a special case: in C the
// smallest value `% -1` overflows (and traps on x86), but the remainder is 0.
#define IDRIS2_EUCLID_REM(num, denom, rem)                                     \
  do {                                                                         \
    rem = (denom) == -1 ? 0 : (num) % (denom);                                 \
    if (rem < 0)                                                               \
      rem = (denom) < 0 ? rem - (denom) : rem + (denom);                       \
  } while (0)

// The Euclidean quotient: the truncated one, one closer to -infinity (for a
// positive divisor) or +infinity (for a negative one) when the truncated
// remainder is negative.  See Division and Modulus for Computer Scientists
// (Daan Leijen).  The quotient by -1 is the negation, which wraps around for
// the smallest value (as in the other backends) instead of trapping.
// idris2_euclidDiv_Int64 and idris2_euclidMod_Int64 work on C integers: the
// code generator uses them on the Ints that it keeps unboxed.
#define IDRIS2_EUCLID_DIVMOD(ty, cty, uty)                                     \
  static inline cty idris2_euclidDiv_##ty(cty num, cty denom) {                \
    IDRIS2_CHECK_DIVISOR(denom);                                               \
    if (denom == -1)                                                           \
      return (cty)(0u - (uty)num);                                             \
    cty rem = num % denom;                                                     \
    return num / denom + ((rem < 0) ? (denom < 0) ? 1 : -1 : 0);               \
  }                                                                            \
  static inline cty idris2_euclidMod_##ty(cty num, cty denom) {                \
    IDRIS2_CHECK_DIVISOR(denom);                                               \
    cty rem;                                                                   \
    IDRIS2_EUCLID_REM(num, denom, rem);                                        \
    return rem;                                                                \
  }                                                                            \
  static inline Idris2_Value *idris2_div_##ty(Idris2_Value *x,                 \
                                              Idris2_Value *y) {               \
    return (Idris2_Value *)idris2_mk##ty(                                      \
        idris2_euclidDiv_##ty(idris2_vp_to_##ty(x), idris2_vp_to_##ty(y)));    \
  }                                                                            \
  static inline Idris2_Value *idris2_mod_##ty(Idris2_Value *x,                 \
                                              Idris2_Value *y) {               \
    return (Idris2_Value *)idris2_mk##ty(                                      \
        idris2_euclidMod_##ty(idris2_vp_to_##ty(x), idris2_vp_to_##ty(y)));    \
  }
IDRIS2_EUCLID_DIVMOD(Int8, int8_t, uint32_t)
IDRIS2_EUCLID_DIVMOD(Int16, int16_t, uint32_t)
IDRIS2_EUCLID_DIVMOD(Int32, int32_t, uint32_t)
IDRIS2_EUCLID_DIVMOD(Int64, int64_t, uint64_t)

// The Integers have a fast path for the small ones (see idris2_add_Integer),
// with a divisor that is not 0 (division by 0 is left to the slow path, which
// stops the program).
Idris2_Value *idris2_div_IntegerSlow(Idris2_Value *x, Idris2_Value *y);
static inline Idris2_Value *idris2_div_Integer(Idris2_Value *x,
                                                Idris2_Value *y) {
  if (idris2_isSmallInteger(x) && idris2_isSmallInteger(y) &&
      idris2_smallInteger(y) != 0) {
    int64_t a = idris2_smallInteger(x), b = idris2_smallInteger(y), r;
    IDRIS2_EUCLID_REM(a, b, r);
    return idris2_mkIntegerFromInt64((a - r) / b);
  }
  return idris2_div_IntegerSlow(x, y);
}
#define idris2_div_Double(l, r) (idris2_binop(Double, /, l, r))

/* mod (of the Bits: with div) */
Idris2_Value *idris2_mod_IntegerSlow(Idris2_Value *x, Idris2_Value *y);
static inline Idris2_Value *idris2_mod_Integer(Idris2_Value *x,
                                                Idris2_Value *y) {
  if (idris2_isSmallInteger(x) && idris2_isSmallInteger(y) &&
      idris2_smallInteger(y) != 0) {
    int64_t a = idris2_smallInteger(x), b = idris2_smallInteger(y), r;
    IDRIS2_EUCLID_REM(a, b, r);
    return idris2_mkIntegerFromInt64(r);
  }
  return idris2_mod_IntegerSlow(x, y);
}

/* shiftl, shiftr

   Like the Scheme backends (`ash`, then the result wraps around): a shift by
   the width of the type or more gives 0 (or -1, for a right shift of a
   negative number), where it is undefined behaviour in C.  A shift of a
   signed type by a negative count goes the other way.
   idris2_shiftLeft_Int64 and idris2_shiftRight_Int64 work on C integers: the
   code generator uses them on the Ints that it keeps unboxed. */
#define IDRIS2_SHIFTS_UNSIGNED(ty, cty, uty, bits)                             \
  static inline cty idris2_shiftLeft_##ty(cty x, cty n) {                      \
    return n >= (bits) ? 0 : (cty)((uty)x << n);                               \
  }                                                                            \
  static inline cty idris2_shiftRight_##ty(cty x, cty n) {                     \
    return n >= (bits) ? 0 : (cty)(x >> n);                                    \
  }                                                                            \
  static inline Idris2_Value *idris2_shiftl_##ty(Idris2_Value *x,              \
                                                 Idris2_Value *n) {            \
    return idris2_mk##ty(                                                      \
        idris2_shiftLeft_##ty(idris2_vp_to_##ty(x), idris2_vp_to_##ty(n)));    \
  }                                                                            \
  static inline Idris2_Value *idris2_shiftr_##ty(Idris2_Value *x,              \
                                                 Idris2_Value *n) {            \
    return idris2_mk##ty(                                                      \
        idris2_shiftRight_##ty(idris2_vp_to_##ty(x), idris2_vp_to_##ty(n)));   \
  }
IDRIS2_SHIFTS_UNSIGNED(Bits8, uint8_t, uint32_t, 8)
IDRIS2_SHIFTS_UNSIGNED(Bits16, uint16_t, uint32_t, 16)
IDRIS2_SHIFTS_UNSIGNED(Bits32, uint32_t, uint32_t, 32)
IDRIS2_SHIFTS_UNSIGNED(Bits64, uint64_t, uint64_t, 64)

// (the left shifts are done on unsigned integers, where an overflow is not
// undefined behaviour; the right shift of a negative number on its
// complement, which is not negative)
#define IDRIS2_SHIFTS_SIGNED(ty, cty, uty, bits)                               \
  static inline cty idris2_arithShiftRight_##ty(cty x, uint64_t n) {           \
    if (n >= (bits))                                                           \
      return x < 0 ? -1 : 0;                                                   \
    return x < 0 ? (cty)~((cty)~x >> n) : (cty)(x >> n);                       \
  }                                                                            \
  static inline cty idris2_logicShiftLeft_##ty(cty x, uint64_t n) {            \
    return n >= (bits) ? 0 : (cty)((uty)x << n);                               \
  }                                                                            \
  static inline cty idris2_shiftLeft_##ty(cty x, cty n) {                      \
    return n >= 0 ? idris2_logicShiftLeft_##ty(x, (uint64_t)n)                 \
                  : idris2_arithShiftRight_##ty(x, 0u - (uint64_t)n);          \
  }                                                                            \
  static inline cty idris2_shiftRight_##ty(cty x, cty n) {                     \
    return n >= 0 ? idris2_arithShiftRight_##ty(x, (uint64_t)n)                \
                  : idris2_logicShiftLeft_##ty(x, 0u - (uint64_t)n);           \
  }                                                                            \
  static inline Idris2_Value *idris2_shiftl_##ty(Idris2_Value *x,              \
                                                 Idris2_Value *n) {            \
    return idris2_mk##ty(                                                      \
        idris2_shiftLeft_##ty(idris2_vp_to_##ty(x), idris2_vp_to_##ty(n)));    \
  }                                                                            \
  static inline Idris2_Value *idris2_shiftr_##ty(Idris2_Value *x,              \
                                                 Idris2_Value *n) {            \
    return idris2_mk##ty(                                                      \
        idris2_shiftRight_##ty(idris2_vp_to_##ty(x), idris2_vp_to_##ty(n)));   \
  }
IDRIS2_SHIFTS_SIGNED(Int8, int8_t, uint32_t, 8)
IDRIS2_SHIFTS_SIGNED(Int16, int16_t, uint32_t, 16)
IDRIS2_SHIFTS_SIGNED(Int32, int32_t, uint32_t, 32)
IDRIS2_SHIFTS_SIGNED(Int64, int64_t, uint64_t, 64)

Idris2_Value *idris2_shiftl_Integer(Idris2_Value *x, Idris2_Value *y);
Idris2_Value *idris2_shiftr_Integer(Idris2_Value *x, Idris2_Value *y);

/* and */
#define idris2_and_Bits8(l, r) (idris2_binop(Bits8, &, l, r))
#define idris2_and_Bits16(l, r) (idris2_binop(Bits16, &, l, r))
#define idris2_and_Bits32(l, r) (idris2_binop(Bits32, &, l, r))
#define idris2_and_Bits64(l, r) (idris2_binop(Bits64, &, l, r))
#define idris2_and_Int8(l, r) (idris2_binop(Int8, &, l, r))
#define idris2_and_Int16(l, r) (idris2_binop(Int16, &, l, r))
#define idris2_and_Int32(l, r) (idris2_binop(Int32, &, l, r))
#define idris2_and_Int64(l, r) (idris2_binop(Int64, &, l, r))
Idris2_Value *idris2_and_Integer(Idris2_Value *x, Idris2_Value *y);

/* or */
#define idris2_or_Bits8(l, r) (idris2_binop(Bits8, |, l, r))
#define idris2_or_Bits16(l, r) (idris2_binop(Bits16, |, l, r))
#define idris2_or_Bits32(l, r) (idris2_binop(Bits32, |, l, r))
#define idris2_or_Bits64(l, r) (idris2_binop(Bits64, |, l, r))
#define idris2_or_Int8(l, r) (idris2_binop(Int8, |, l, r))
#define idris2_or_Int16(l, r) (idris2_binop(Int16, |, l, r))
#define idris2_or_Int32(l, r) (idris2_binop(Int32, |, l, r))
#define idris2_or_Int64(l, r) (idris2_binop(Int64, |, l, r))
Idris2_Value *idris2_or_Integer(Idris2_Value *x, Idris2_Value *y);

/* xor */
#define idris2_xor_Bits8(l, r) (idris2_binop(Bits8, ^, l, r))
#define idris2_xor_Bits16(l, r) (idris2_binop(Bits16, ^, l, r))
#define idris2_xor_Bits32(l, r) (idris2_binop(Bits32, ^, l, r))
#define idris2_xor_Bits64(l, r) (idris2_binop(Bits64, ^, l, r))
#define idris2_xor_Int8(l, r) (idris2_binop(Int8, ^, l, r))
#define idris2_xor_Int16(l, r) (idris2_binop(Int16, ^, l, r))
#define idris2_xor_Int32(l, r) (idris2_binop(Int32, ^, l, r))
#define idris2_xor_Int64(l, r) (idris2_binop(Int64, ^, l, r))
Idris2_Value *idris2_xor_Integer(Idris2_Value *x, Idris2_Value *y);

#define idris2_cmpop(ty, op, l, r)                                             \
  (idris2_mkBool((idris2_vp_to_##ty(l) op idris2_vp_to_##ty(r)) ? 1 : 0))

/* lt */
#define idris2_lt_Bits8(l, r) (idris2_cmpop(Bits8, <, l, r))
#define idris2_lt_Bits16(l, r) (idris2_cmpop(Bits16, <, l, r))
#define idris2_lt_Bits32(l, r) (idris2_cmpop(Bits32, <, l, r))
#define idris2_lt_Bits64(l, r) (idris2_cmpop(Bits64, <, l, r))
#define idris2_lt_Int8(l, r) (idris2_cmpop(Int8, <, l, r))
#define idris2_lt_Int16(l, r) (idris2_cmpop(Int16, <, l, r))
#define idris2_lt_Int32(l, r) (idris2_cmpop(Int32, <, l, r))
#define idris2_lt_Int64(l, r) (idris2_cmpop(Int64, <, l, r))
#define idris2_lt_Integer(l, r)                                                \
  (idris2_mkBool(                                                              \
      idris2_cmpInteger((l), (r)) < 0))
#define idris2_lt_Double(l, r) (idris2_cmpop(Double, <, l, r))
#define idris2_lt_Char(l, r) (idris2_cmpop(Char, <, l, r))
#define idris2_lt_string(l, r)                                                 \
  (idris2_mkBool(                                                              \
      idris2_compareStrings((l), (r)) < 0))

/* gt */
#define idris2_gt_Bits8(l, r) (idris2_cmpop(Bits8, >, l, r))
#define idris2_gt_Bits16(l, r) (idris2_cmpop(Bits16, >, l, r))
#define idris2_gt_Bits32(l, r) (idris2_cmpop(Bits32, >, l, r))
#define idris2_gt_Bits64(l, r) (idris2_cmpop(Bits64, >, l, r))
#define idris2_gt_Int8(l, r) (idris2_cmpop(Int8, >, l, r))
#define idris2_gt_Int16(l, r) (idris2_cmpop(Int16, >, l, r))
#define idris2_gt_Int32(l, r) (idris2_cmpop(Int32, >, l, r))
#define idris2_gt_Int64(l, r) (idris2_cmpop(Int64, >, l, r))
#define idris2_gt_Integer(l, r)                                                \
  (idris2_mkBool(                                                              \
      idris2_cmpInteger((l), (r)) > 0))
#define idris2_gt_Double(l, r) (idris2_cmpop(Double, >, l, r))
#define idris2_gt_Char(l, r) (idris2_cmpop(Char, >, l, r))
#define idris2_gt_string(l, r)                                                 \
  (idris2_mkBool(                                                              \
      idris2_compareStrings((l), (r)) > 0))

/* eq */
#define idris2_eq_Bits8(l, r) (idris2_cmpop(Bits8, ==, l, r))
#define idris2_eq_Bits16(l, r) (idris2_cmpop(Bits16, ==, l, r))
#define idris2_eq_Bits32(l, r) (idris2_cmpop(Bits32, ==, l, r))
#define idris2_eq_Bits64(l, r) (idris2_cmpop(Bits64, ==, l, r))
#define idris2_eq_Int8(l, r) (idris2_cmpop(Int8, ==, l, r))
#define idris2_eq_Int16(l, r) (idris2_cmpop(Int16, ==, l, r))
#define idris2_eq_Int32(l, r) (idris2_cmpop(Int32, ==, l, r))
#define idris2_eq_Int64(l, r) (idris2_cmpop(Int64, ==, l, r))
#define idris2_eq_Integer(l, r)                                                \
  (idris2_mkBool(                                                              \
      idris2_cmpInteger((l), (r)) == 0))
#define idris2_eq_Double(l, r) (idris2_cmpop(Double, ==, l, r))
#define idris2_eq_Char(l, r) (idris2_cmpop(Char, ==, l, r))
#define idris2_eq_string(l, r)                                                 \
  (idris2_mkBool(                                                              \
      idris2_compareStrings((l), (r)) == 0))

/* lte */
#define idris2_lte_Bits8(l, r) (idris2_cmpop(Bits8, <=, l, r))
#define idris2_lte_Bits16(l, r) (idris2_cmpop(Bits16, <=, l, r))
#define idris2_lte_Bits32(l, r) (idris2_cmpop(Bits32, <=, l, r))
#define idris2_lte_Bits64(l, r) (idris2_cmpop(Bits64, <=, l, r))
#define idris2_lte_Int8(l, r) (idris2_cmpop(Int8, <=, l, r))
#define idris2_lte_Int16(l, r) (idris2_cmpop(Int16, <=, l, r))
#define idris2_lte_Int32(l, r) (idris2_cmpop(Int32, <=, l, r))
#define idris2_lte_Int64(l, r) (idris2_cmpop(Int64, <=, l, r))
#define idris2_lte_Integer(l, r)                                               \
  (idris2_mkBool(                                                              \
      idris2_cmpInteger((l), (r)) <= 0))
#define idris2_lte_Double(l, r) (idris2_cmpop(Double, <=, l, r))
#define idris2_lte_Char(l, r) (idris2_cmpop(Char, <=, l, r))
#define idris2_lte_string(l, r)                                                \
  (idris2_mkBool(                                                              \
      idris2_compareStrings((l), (r)) <= 0))

/* gte */
#define idris2_gte_Bits8(l, r) (idris2_cmpop(Bits8, >=, l, r))
#define idris2_gte_Bits16(l, r) (idris2_cmpop(Bits16, >=, l, r))
#define idris2_gte_Bits32(l, r) (idris2_cmpop(Bits32, >=, l, r))
#define idris2_gte_Bits64(l, r) (idris2_cmpop(Bits64, >=, l, r))
#define idris2_gte_Int8(l, r) (idris2_cmpop(Int8, >=, l, r))
#define idris2_gte_Int16(l, r) (idris2_cmpop(Int16, >=, l, r))
#define idris2_gte_Int32(l, r) (idris2_cmpop(Int32, >=, l, r))
#define idris2_gte_Int64(l, r) (idris2_cmpop(Int64, >=, l, r))
#define idris2_gte_Integer(l, r)                                               \
  (idris2_mkBool(                                                              \
      idris2_cmpInteger((l), (r)) >= 0))
#define idris2_gte_Double(l, r) (idris2_cmpop(Double, >=, l, r))
#define idris2_gte_Char(l, r) (idris2_cmpop(Char, >=, l, r))
#define idris2_gte_string(l, r)                                                \
  (idris2_mkBool(                                                              \
      idris2_compareStrings((l), (r)) >= 0))

/* IEEE constants of Data.Double */
double idris2_flonumUnitRoundoff(void);
double idris2_flonumEpsilon(void);
double idris2_flonumNaN(void);
double idris2_flonumInf(void);
