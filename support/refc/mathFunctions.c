#include "mathFunctions.h"
#include "memoryManagement.h"
#include "runtime.h"

/* add */

/* sub */

/* negate */

/* mul */

/* div */
Idris2_Value *idris2_div_Int8(Idris2_Value *x, Idris2_Value *y) {
  // Correction term added to convert from truncated division (C default) to
  // Euclidean division For proof of correctness, see Division and Modulus for
  // Computer Scientists (Daan Leijen)
  // https://www.microsoft.com/en-us/research/publication/division-and-modulus-for-computer-scientists/

  int8_t num = idris2_vp_to_Int8(x);
  int8_t denom = idris2_vp_to_Int8(y);
  int8_t rem = num % denom;
  return idris2_mkInt8(num / denom + ((rem < 0) ? (denom < 0) ? 1 : -1 : 0));
}
Idris2_Value *idris2_div_Int16(Idris2_Value *x, Idris2_Value *y) {
  // Correction term added to convert from truncated division (C default) to
  // Euclidean division For proof of correctness, see Division and Modulus for
  // Computer Scientists (Daan Leijen)
  // https://www.microsoft.com/en-us/research/publication/division-and-modulus-for-computer-scientists/

  int16_t num = idris2_vp_to_Int16(x);
  int16_t denom = idris2_vp_to_Int16(y);
  int16_t rem = num % denom;
  return idris2_mkInt16(num / denom + ((rem < 0) ? (denom < 0) ? 1 : -1 : 0));
}
Idris2_Value *idris2_div_Int32(Idris2_Value *x, Idris2_Value *y) {
  // Correction term added to convert from truncated division (C default) to
  // Euclidean division For proof of correctness, see Division and Modulus for
  // Computer Scientists (Daan Leijen)
  // https://www.microsoft.com/en-us/research/publication/division-and-modulus-for-computer-scientists/

  int32_t num = idris2_vp_to_Int32(x);
  int32_t denom = idris2_vp_to_Int32(y);
  int32_t rem = num % denom;
  return idris2_mkInt32(num / denom + ((rem < 0) ? (denom < 0) ? 1 : -1 : 0));
}
Idris2_Value *idris2_div_Int64(Idris2_Value *x, Idris2_Value *y) {
  // Correction term added to convert from truncated division (C default) to
  // Euclidean division For proof of correctness, see Division and Modulus for
  // Computer Scientists (Daan Leijen)
  // https://www.microsoft.com/en-us/research/publication/division-and-modulus-for-computer-scientists/

  int64_t num = idris2_vp_to_Int64(x);
  int64_t denom = idris2_vp_to_Int64(y);
  int64_t rem = num % denom;
  return (Idris2_Value *)idris2_mkInt64(num / denom +
                                        ((rem < 0) ? (denom < 0) ? 1 : -1 : 0));
}


/* mod */
Idris2_Value *idris2_mod_Int8(Idris2_Value *x, Idris2_Value *y) {
  int8_t num = idris2_vp_to_Int8(x);
  int8_t denom = idris2_vp_to_Int8(y);
  denom = (denom < 0) ? -denom : denom;
  return (Idris2_Value *)idris2_mkInt8(num % denom + (num < 0 ? denom : 0));
}

Idris2_Value *idris2_mod_Int16(Idris2_Value *x, Idris2_Value *y) {
  int16_t num = idris2_vp_to_Int16(x);
  int16_t denom = idris2_vp_to_Int16(y);
  denom = (denom < 0) ? -denom : denom;
  return (Idris2_Value *)idris2_mkInt16(num % denom + (num < 0 ? denom : 0));
}
Idris2_Value *idris2_mod_Int32(Idris2_Value *x, Idris2_Value *y) {
  int32_t num = idris2_vp_to_Int32(x);
  int32_t denom = idris2_vp_to_Int32(y);
  denom = (denom < 0) ? -denom : denom;
  return (Idris2_Value *)idris2_mkInt32(num % denom + (num < 0 ? denom : 0));
}
Idris2_Value *idris2_mod_Int64(Idris2_Value *x, Idris2_Value *y) {
  int64_t num = idris2_vp_to_Int64(x);
  int64_t denom = idris2_vp_to_Int64(y);
  denom = (denom < 0) ? -denom : denom;
  return (Idris2_Value *)idris2_mkInt64(num % denom + (num < 0 ? denom : 0));
}

/* shiftl */

/* shiftr */

/* and */

/* or */

/* xor */

double idris2_flonumUnitRoundoff(void) { return DBL_EPSILON / 2; }
double idris2_flonumEpsilon(void) { return DBL_EPSILON; }
double idris2_flonumNaN(void) { return NAN; }
double idris2_flonumInf(void) { return INFINITY; }

/* Integers (see idris2_integerMpz) */

#define IDRIS2_INTEGER_OP2(name, fast, ...)                                    \
  Idris2_Value *name(Idris2_Value *x, Idris2_Value *y) {                       \
    if (idris2_isSmallInteger(x) && idris2_isSmallInteger(y)) {                \
      int64_t a = idris2_smallInteger(x), b = idris2_smallInteger(y);          \
      (void)a;                                                                 \
      (void)b;                                                                 \
      fast                                                                     \
    }                                                                          \
    IDRIS2_INTEGER_MPZ(ma, x);                                                 \
    IDRIS2_INTEGER_MPZ(mb, y);                                                 \
    Idris2_Integer *retVal = idris2_mkInteger();                               \
    __VA_ARGS__;                                                               \
    return idris2_normaliseInteger(retVal);                                    \
  }

// The small integers have 32 bits: these do not overflow.
IDRIS2_INTEGER_OP2(idris2_add_IntegerSlow,
                   return idris2_mkIntegerFromInt64(a + b);,
                   mpz_add(retVal->i, ma, mb))
IDRIS2_INTEGER_OP2(idris2_sub_IntegerSlow,
                   return idris2_mkIntegerFromInt64(a - b);,
                   mpz_sub(retVal->i, ma, mb))
IDRIS2_INTEGER_OP2(idris2_mul_IntegerSlow,
                   return idris2_mkIntegerFromInt64(a * b);,
                   mpz_mul(retVal->i, ma, mb))
IDRIS2_INTEGER_OP2(idris2_and_Integer,
                   return idris2_mkIntegerFromInt64(a & b);,
                   mpz_and(retVal->i, ma, mb))
IDRIS2_INTEGER_OP2(idris2_or_Integer,
                   return idris2_mkIntegerFromInt64(a | b);,
                   mpz_ior(retVal->i, ma, mb))
IDRIS2_INTEGER_OP2(idris2_xor_Integer,
                   return idris2_mkIntegerFromInt64(a ^ b);,
                   mpz_xor(retVal->i, ma, mb))

// The remainder of the Euclidean division (non-negative, like mpz_mod).
static int64_t idris2_euclidRem(int64_t num, int64_t denom) {
  int64_t rem = num % denom;
  return rem < 0 ? rem + (denom < 0 ? -denom : denom) : rem;
}

IDRIS2_INTEGER_OP2(
    idris2_div_Integer,
    return idris2_mkIntegerFromInt64((a - idris2_euclidRem(a, b)) / b);
    , {
      mpz_t rem, yq;
      mpz_inits(rem, yq, NULL);
      mpz_mod(rem, ma, mb);
      mpz_sub(yq, ma, rem);
      mpz_divexact(retVal->i, yq, mb);
      mpz_clears(rem, yq, NULL);
    })
IDRIS2_INTEGER_OP2(idris2_mod_Integer,
                   return idris2_mkIntegerFromInt64(idris2_euclidRem(a, b));,
                   mpz_mod(retVal->i, ma, mb))
IDRIS2_INTEGER_OP2(
    idris2_shiftl_Integer,
    if (b >= 0 && b < 32) return idris2_mkIntegerFromInt64(a * ((int64_t)1 << b));
    , mpz_mul_2exp(retVal->i, ma, (mp_bitcnt_t)mpz_get_ui(mb)))
// (an arithmetic shift of a signed integer: the floor of the division)
IDRIS2_INTEGER_OP2(
    idris2_shiftr_Integer,
    if (b >= 0) return idris2_mkIntegerFromInt64(b >= 63 ? (a < 0 ? -1 : 0)
                                                         : a >> b);
    , mpz_fdiv_q_2exp(retVal->i, ma, (mp_bitcnt_t)mpz_get_ui(mb)))

Idris2_Value *idris2_negate_Integer(Idris2_Value *x) {
  if (idris2_isSmallInteger(x))
    return idris2_mkIntegerFromInt64(-idris2_smallInteger(x));
  Idris2_Integer *retVal = idris2_mkInteger();
  mpz_neg(retVal->i, ((Idris2_Integer *)x)->i);
  return idris2_normaliseInteger(retVal);
}

int idris2_cmpIntegerSlow(Idris2_Value *x, Idris2_Value *y) {
  IDRIS2_INTEGER_MPZ(a, x);
  IDRIS2_INTEGER_MPZ(b, y);
  return mpz_cmp(a, b);
}
