#include "mathFunctions.h"
#include "memoryManagement.h"
#include "runtime.h"

/* The operations on the fixed width types are in mathFunctions.h. */

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
  int64_t rem;
  IDRIS2_EUCLID_REM(num, denom, rem);
  return rem;
}

IDRIS2_INTEGER_OP2(
    idris2_div_IntegerSlow,
    // (by 0: GMP reports the division by zero)
    if (b != 0) return idris2_mkIntegerFromInt64(
        (a - idris2_euclidRem(a, b)) / b);
    , {
      mpz_t rem, yq;
      mpz_inits(rem, yq, NULL);
      mpz_mod(rem, ma, mb);
      mpz_sub(yq, ma, rem);
      mpz_divexact(retVal->i, yq, mb);
      mpz_clears(rem, yq, NULL);
    })
IDRIS2_INTEGER_OP2(idris2_mod_IntegerSlow,
                   if (b != 0) return idris2_mkIntegerFromInt64(
                       idris2_euclidRem(a, b));,
                   mpz_mod(retVal->i, ma, mb))
// (a shift by a negative count goes the other way, like `ash`; the right
// shift is arithmetic: the floor of the division)
#define IDRIS2_INTEGER_SHIFT(dst, x, n, left)                                  \
  do {                                                                         \
    if ((mpz_sgn(n) >= 0) == (left))                                           \
      mpz_mul_2exp(dst, x, (mp_bitcnt_t)mpz_get_ui(n));                        \
    else                                                                       \
      mpz_fdiv_q_2exp(dst, x, (mp_bitcnt_t)mpz_get_ui(n));                     \
  } while (0)
IDRIS2_INTEGER_OP2(
    idris2_shiftl_Integer,
    if (b >= 0 && b < 32) return idris2_mkIntegerFromInt64(a * ((int64_t)1 << b));
    if (b < 0) return idris2_mkIntegerFromInt64(b <= -63 ? (a < 0 ? -1 : 0)
                                                          : a >> -b);
    , IDRIS2_INTEGER_SHIFT(retVal->i, ma, mb, 1))
IDRIS2_INTEGER_OP2(
    idris2_shiftr_Integer,
    if (b >= 0) return idris2_mkIntegerFromInt64(b >= 63 ? (a < 0 ? -1 : 0)
                                                         : a >> b);
    if (b > -32) return idris2_mkIntegerFromInt64(a * ((int64_t)1 << -b));
    , IDRIS2_INTEGER_SHIFT(retVal->i, ma, mb, 0))

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
