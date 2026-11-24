#include "mathFunctions.h"
#include "memoryManagement.h"
#include "prim.h"
#include "runtime.h"

/* The operations on the fixed width types are in mathFunctions.h. */

double idris2i_1_flonumUnitRoundoff(void) { return DBL_EPSILON / 2; }
double idris2i_1_flonumEpsilon(void) { return DBL_EPSILON; }
double idris2i_1_flonumNaN(void) { return NAN; }
double idris2i_1_flonumInf(void) { return INFINITY; }

void idris2i_1_divideByZero(void) {
  idris2i_1_crashCheck("ERROR: Division by zero");
}

/* Integers (see idris2i_1_integerMpz) */

#define IDRIS2I_1_INTEGER_OP2(name, fast, ...)                                    \
  Idris2i_1_Value *name(Idris2i_1_Value *x, Idris2i_1_Value *y) {                       \
    if (idris2i_1_isSmallInteger(x) && idris2i_1_isSmallInteger(y)) {                \
      int64_t a = idris2i_1_smallInteger(x), b = idris2i_1_smallInteger(y);          \
      (void)a;                                                                 \
      (void)b;                                                                 \
      fast                                                                     \
    }                                                                          \
    IDRIS2I_1_INTEGER_MPZ(ma, x);                                                 \
    IDRIS2I_1_INTEGER_MPZ(mb, y);                                                 \
    Idris2i_1_Integer *retVal = idris2i_1_mkInteger();                               \
    __VA_ARGS__;                                                               \
    return idris2i_1_normaliseInteger(retVal);                                    \
  }

// The small integers have 32 bits: these do not overflow.
IDRIS2I_1_INTEGER_OP2(idris2i_1_add_IntegerSlow,
                   return idris2i_1_mkIntegerFromInt64(a + b);,
                   mpz_add(retVal->i, ma, mb))
IDRIS2I_1_INTEGER_OP2(idris2i_1_sub_IntegerSlow,
                   return idris2i_1_mkIntegerFromInt64(a - b);,
                   mpz_sub(retVal->i, ma, mb))
IDRIS2I_1_INTEGER_OP2(idris2i_1_mul_IntegerSlow,
                   return idris2i_1_mkIntegerFromInt64(a * b);,
                   mpz_mul(retVal->i, ma, mb))
IDRIS2I_1_INTEGER_OP2(idris2i_1_and_Integer,
                   return idris2i_1_mkIntegerFromInt64(a & b);,
                   mpz_and(retVal->i, ma, mb))
IDRIS2I_1_INTEGER_OP2(idris2i_1_or_Integer,
                   return idris2i_1_mkIntegerFromInt64(a | b);,
                   mpz_ior(retVal->i, ma, mb))
IDRIS2I_1_INTEGER_OP2(idris2i_1_xor_Integer,
                   return idris2i_1_mkIntegerFromInt64(a ^ b);,
                   mpz_xor(retVal->i, ma, mb))

// The remainder of the Euclidean division (non-negative, like mpz_mod).
static int64_t idris2i_1_euclidRem(int64_t num, int64_t denom) {
  int64_t rem;
  IDRIS2I_1_EUCLID_REM(num, denom, rem);
  return rem;
}

IDRIS2I_1_INTEGER_OP2(
    idris2i_1_div_IntegerSlow,
    if (b != 0) return idris2i_1_mkIntegerFromInt64(
        (a - idris2i_1_euclidRem(a, b)) / b);
    , {
      // (GMP would raise SIGFPE)
      if (mpz_sgn(mb) == 0)
        idris2i_1_divideByZero();
      mpz_t rem, yq;
      mpz_inits(rem, yq, NULL);
      mpz_mod(rem, ma, mb);
      mpz_sub(yq, ma, rem);
      mpz_divexact(retVal->i, yq, mb);
      mpz_clears(rem, yq, NULL);
    })
IDRIS2I_1_INTEGER_OP2(idris2i_1_mod_IntegerSlow,
                   if (b != 0) return idris2i_1_mkIntegerFromInt64(
                       idris2i_1_euclidRem(a, b));,
                   if (mpz_sgn(mb) == 0) idris2i_1_divideByZero();
                   mpz_mod(retVal->i, ma, mb))
// (a shift by a negative count goes the other way, like `ash`; the right
// shift is arithmetic: the floor of the division)
static void idris2i_1_shiftInteger(mpz_ptr dst, mpz_srcptr x, mpz_srcptr n,
                                int left) {
  int up = (mpz_sgn(n) >= 0) == left;
  // A count that is no mp_bitcnt_t (mpz_get_ui would keep its low bits): a
  // shift right by it leaves the sign, and a shift left makes a number that
  // no memory holds (the Chez backend runs out of memory too), unless it is 0.
  if (mpz_cmpabs_ui(n, ULONG_MAX) > 0) {
    if (!up)
      mpz_set_si(dst, mpz_sgn(x) < 0 ? -1 : 0);
    else if (mpz_sgn(x) == 0)
      mpz_set_ui(dst, 0);
    else
      idris2i_1_crashCheck("ERROR: Integer shifted left by too many bits");
    return;
  }
  if (up)
    mpz_mul_2exp(dst, x, (mp_bitcnt_t)mpz_get_ui(n));
  else
    mpz_fdiv_q_2exp(dst, x, (mp_bitcnt_t)mpz_get_ui(n));
}
IDRIS2I_1_INTEGER_OP2(
    idris2i_1_shiftl_Integer,
    if (b >= 0 && b < 32) return idris2i_1_mkIntegerFromInt64(a * ((int64_t)1 << b));
    if (b < 0) return idris2i_1_mkIntegerFromInt64(b <= -63 ? (a < 0 ? -1 : 0)
                                                          : a >> -b);
    , idris2i_1_shiftInteger(retVal->i, ma, mb, 1))
IDRIS2I_1_INTEGER_OP2(
    idris2i_1_shiftr_Integer,
    if (b >= 0) return idris2i_1_mkIntegerFromInt64(b >= 63 ? (a < 0 ? -1 : 0)
                                                         : a >> b);
    if (b > -32) return idris2i_1_mkIntegerFromInt64(a * ((int64_t)1 << -b));
    , idris2i_1_shiftInteger(retVal->i, ma, mb, 0))

Idris2i_1_Value *idris2i_1_negate_Integer(Idris2i_1_Value *x) {
  if (idris2i_1_isSmallInteger(x))
    return idris2i_1_mkIntegerFromInt64(-idris2i_1_smallInteger(x));
  Idris2i_1_Integer *retVal = idris2i_1_mkInteger();
  mpz_neg(retVal->i, ((Idris2i_1_Integer *)x)->i);
  return idris2i_1_normaliseInteger(retVal);
}

int idris2i_1_cmpIntegerSlow(Idris2i_1_Value *x, Idris2i_1_Value *y) {
  IDRIS2I_1_INTEGER_MPZ(a, x);
  IDRIS2I_1_INTEGER_MPZ(b, y);
  return mpz_cmp(a, b);
}
