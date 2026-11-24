#include "casts.h"

#include "refc_util.h"

#include <inttypes.h>

Idris2i_1_Value *idris2i_1_mkValidChar(int64_t c) {
  return idris2i_1_mkChar(idris2i_1_isValidCodePoint(c) ? c : 0);
}

/*  conversions from Int8  */
Idris2i_1_Value *idris2i_1_cast_Int8_to_Integer(Idris2i_1_Value *input) {
  return idris2i_1_mkIntegerFromInt64(idris2i_1_vp_to_Int8(input));
}

Idris2i_1_Value *idris2i_1_cast_Int8_to_string(Idris2i_1_Value *input) {
  int8_t x = idris2i_1_vp_to_Int8(input);

  int l = snprintf(NULL, 0, "%" PRId8 "", x);
  Idris2i_1_String *retVal = idris2i_1_mkEmptyString(l + 1);
  sprintf(retVal->str, "%" PRId8 "", x);
  idris2i_1_setAscii(retVal);

  return (Idris2i_1_Value *)retVal;
}

/*  conversions from Int16  */
Idris2i_1_Value *idris2i_1_cast_Int16_to_Integer(Idris2i_1_Value *input) {
  return idris2i_1_mkIntegerFromInt64(idris2i_1_vp_to_Int16(input));
}

Idris2i_1_Value *idris2i_1_cast_Int16_to_string(Idris2i_1_Value *input) {
  int16_t x = idris2i_1_vp_to_Int16(input);

  int l = snprintf(NULL, 0, "%" PRId16 "", x);
  Idris2i_1_String *retVal = idris2i_1_mkEmptyString(l + 1);
  sprintf(retVal->str, "%" PRId16 "", x);
  idris2i_1_setAscii(retVal);

  return (Idris2i_1_Value *)retVal;
}

/*  conversions from Int32  */
Idris2i_1_Value *idris2i_1_cast_Int32_to_Integer(Idris2i_1_Value *input) {
  return idris2i_1_mkIntegerFromInt64(idris2i_1_vp_to_Int32(input));
}

Idris2i_1_Value *idris2i_1_cast_Int32_to_string(Idris2i_1_Value *input) {
  int32_t x = idris2i_1_vp_to_Int32(input);

  int l = snprintf(NULL, 0, "%" PRId32 "", x);
  Idris2i_1_String *retVal = idris2i_1_mkEmptyString(l + 1);
  sprintf(retVal->str, "%" PRId32 "", x);
  idris2i_1_setAscii(retVal);

  return (Idris2i_1_Value *)retVal;
}

/*  conversions from Int64  */
Idris2i_1_Value *idris2i_1_cast_Int64_to_Integer(Idris2i_1_Value *input) {
  return idris2i_1_mkIntegerFromInt64(idris2i_1_vp_to_Int64(input));
}

Idris2i_1_Value *idris2i_1_cast_Int64_to_string(Idris2i_1_Value *input) {
  int64_t from = idris2i_1_vp_to_Int64(input);
  int l = snprintf(NULL, 0, "%" PRId64 "", from);
  Idris2i_1_String *retVal = idris2i_1_mkEmptyString(l + 1);
  sprintf(retVal->str, "%" PRId64 "", from);
  idris2i_1_setAscii(retVal);

  return (Idris2i_1_Value *)retVal;
}

// (A NaN or an infinity, which the Chez backend raises an exception for and
// GMP a SIGFPE, is 0, as in the casts to the fixed width integers.)
Idris2i_1_Value *idris2i_1_mkIntegerFromDouble(double d) {
  if (!isfinite(d))
    return idris2i_1_mkIntegerFromInt64(0);
  Idris2i_1_Integer *retVal = idris2i_1_mkInteger();
  mpz_set_d(retVal->i, d);

  return idris2i_1_normaliseInteger(retVal);
}

Idris2i_1_Value *idris2i_1_cast_Double_to_Integer(Idris2i_1_Value *input) {
  return idris2i_1_mkIntegerFromDouble(idris2i_1_vp_to_Double(input));
}

/*
 * Print a Double the way Chez Scheme does, so that every backend shows the
 * same text: the shortest digits that read back as the same number, in
 * positional notation when the decimal exponent is between -3 and 9 and in
 * scientific notation otherwise ("0.001", "1e-4", "123.0", "1e10"), with
 * "|<bits>" after a subnormal number.
 */
/*
 * The shortest digits that read back as x (positive and finite), the nearest
 * to x of those, and of two at the same distance the greater one, as Chez
 * does (printf would round a tie to even): digits[0..*n) times
 * 10^(*k - *n + 1).  For each number of digits, the candidates are the exact
 * expansion of x truncated to that many digits and the next number up: x is
 * between them.  The nearest of them, which printf would give, need not read
 * back as x when the other one does: the Doubles next to a power of two are
 * not at the same distance on both sides.
 */
static void shortestDigits(double x, char *digits, int *n, int *k) {
  /* A double has an exact decimal expansion of at most 767 digits. */
  char exact[800];
  snprintf(exact, sizeof(exact), "%.*e", 780, x);

  /* digits of the exact expansion, then its exponent */
  char d[800];
  int len = 0;
  char *p = exact;
  while (*p != 'e') {
    if (*p >= '0' && *p <= '9')
      d[len++] = *p;
    p++;
  }
  int e = atoi(p + 1);
  while (len > 1 && d[len - 1] == '0')
    len--;

  for (int prec = 1;; prec++) {
    if (prec >= len) {
      /* x itself has prec digits */
      memcpy(digits, d, len);
      *n = len;
      *k = e;
      return;
    }
    /* The truncation, and the number up from it (a carry out of the first
     * digit makes it 10^(e+1)). */
    char down[20], up[20];
    memcpy(down, d, prec);
    memcpy(up, d, prec);
    int upExp = e;
    int i = prec - 1;
    while (i >= 0 && up[i] == '9')
      up[i--] = '0';
    if (i < 0) {
      up[0] = '1';
      upExp++;
    } else {
      up[i]++;
    }
    char text[40];
    sprintf(text, "%c.%.*se%d", down[0], prec - 1, down + 1, e);
    int downOk = strtod(text, NULL) == x;
    sprintf(text, "%c.%.*se%d", up[0], prec - 1, up + 1, upExp);
    int upOk = strtod(text, NULL) == x;
    if (downOk && upOk) {
      /* the nearest: the rest of the expansion against a half (5000...) */
      int cmp = d[prec] - '5';
      for (int j = prec + 1; cmp == 0 && j < len; j++)
        cmp = d[j] != '0';
      downOk = cmp < 0;
    }
    if (downOk || upOk) {
      memcpy(digits, downOk ? down : up, prec);
      *n = prec;
      *k = downOk ? e : upExp;
      return;
    }
  }
}

static void formatDouble(double x, char *out) {
  if (isnan(x)) {
    strcpy(out, "+nan.0");
    return;
  }
  if (isinf(x)) {
    strcpy(out, x > 0 ? "+inf.0" : "-inf.0");
    return;
  }

  char *o = out;
  if (signbit(x)) {
    *o++ = '-';
    x = -x;
  }
  if (x == 0) {
    strcpy(o, "0.0");
    return;
  }

  char digits[20];
  int n, k;
  shortestDigits(x, digits, &n, &k);
  while (n > 1 && digits[n - 1] == '0')
    n--;

  if (k >= -3 && k <= 9) {
    if (k >= 0) {
      for (int i = 0; i <= k; i++)
        *o++ = i < n ? digits[i] : '0';
      *o++ = '.';
      if (n > k + 1) {
        for (int i = k + 1; i < n; i++)
          *o++ = digits[i];
      } else {
        *o++ = '0';
      }
    } else {
      *o++ = '0';
      *o++ = '.';
      for (int i = 0; i < -k - 1; i++)
        *o++ = '0';
      for (int i = 0; i < n; i++)
        *o++ = digits[i];
    }
    *o = '\0';
  } else {
    *o++ = digits[0];
    if (n > 1) {
      *o++ = '.';
      for (int i = 1; i < n; i++)
        *o++ = digits[i];
    }
    sprintf(o, "e%d", k);
    o += strlen(o);
  }

  if (fpclassify(x) == FP_SUBNORMAL) {
    uint64_t m = (uint64_t)ldexp(x, 1074);
    int bits = 0;
    while (m != 0) {
      bits++;
      m >>= 1;
    }
    sprintf(o, "|%d", bits);
  }
}

Idris2i_1_Value *idris2i_1_cast_Double_to_string(Idris2i_1_Value *input) {
  char buf[64];
  formatDouble(idris2i_1_vp_to_Double(input), buf);
  Idris2i_1_String *retVal = idris2i_1_mkString(buf);
  idris2i_1_setAscii(retVal);
  return (Idris2i_1_Value *)retVal;
}

// The Double truncated towards zero, modulo 2^64.
uint64_t idris2i_1_double_to_wrapped(double d) {
  if (!isfinite(d))
    return 0;
  if (d >= -9223372036854775808.0 && d < 9223372036854775808.0)
    return (uint64_t)(int64_t)d;
  // |d| >= 2^63: d is an integer, and so is the remainder of its division by
  // 2^64, which fmod computes exactly.  Its magnitude is below 2^64: it is
  // negated as an integer (adding 2^64 to it as a Double would round).
  double t = fmod(d, 18446744073709551616.0);
  uint64_t m = (uint64_t)fabs(t);
  return t < 0 ? -m : m;
}

int64_t idris2i_1_double_to_char_code(double d) {
  if (!(d > -1.0 && d < 1114112.0))
    return -1;
  return (int64_t)d;
}

Idris2i_1_Value *idris2i_1_cast_Char_to_Integer(Idris2i_1_Value *input) {
  return idris2i_1_mkIntegerFromInt64(idris2i_1_vp_to_Char(input));
}

Idris2i_1_Value *idris2i_1_cast_Char_to_string(Idris2i_1_Value *input) {
  uint32_t c = idris2i_1_vp_to_Char(input);
  Idris2i_1_String *retVal =
      idris2i_1_mkEmptyString(idris2i_1_utf8_encodedLength(c) + 1);
  idris2i_1_utf8_encode(c, retVal->str);
  if (idris2i_1_isValidCodePoint(c))
    idris2i_1_setCodePoints(retVal, 1);

  return (Idris2i_1_Value *)retVal;
}

Idris2i_1_Value *idris2i_1_cast_string_to_Char(Idris2i_1_Value *input) {
  char const *s = ((Idris2i_1_String *)input)->str;
  return idris2i_1_mkChar(((Idris2i_1_String *)input)->len == 0
                           ? 0
                           : idris2i_1_utf8_decode(&s));
}

/* Conversions from String, like the Chez backend: the whole string is read
   as a number (an integer, a decimal number or a fraction, see
   `cast-string-int` in support.ss); anything else is 0.  The number is
   truncated towards zero, and wrapped around to fit a fixed size type. */

enum { IDRIS2I_1_NOT_A_NUMBER, IDRIS2I_1_INTEGER_SYNTAX, IDRIS2I_1_DECIMAL_SYNTAX,
       IDRIS2I_1_FRACTION_SYNTAX };

static size_t idris2i_1_digits(char const *s) {
  size_t n = 0;
  while (s[n] >= '0' && s[n] <= '9')
    ++n;
  return n;
}

// The kind of number that `s` is written as.
static int idris2i_1_numberSyntax(char const *s) {
  char const *p = s;
  if (*p == '+' || *p == '-')
    ++p;
  size_t whole = idris2i_1_digits(p);
  p += whole;
  if (*p == '\0')
    return whole > 0 ? IDRIS2I_1_INTEGER_SYNTAX : IDRIS2I_1_NOT_A_NUMBER;
  if (*p == '/') {
    // (a fraction with a zero denominator is no number for Scheme either)
    size_t denom = idris2i_1_digits(p + 1);
    size_t zeros = 0;
    while (zeros < denom && p[1 + zeros] == '0')
      ++zeros;
    return whole > 0 && denom > zeros && p[1 + denom] == '\0'
               ? IDRIS2I_1_FRACTION_SYNTAX
               : IDRIS2I_1_NOT_A_NUMBER;
  }
  size_t frac = 0;
  if (*p == '.') {
    frac = idris2i_1_digits(p + 1);
    p += 1 + frac;
  }
  if (whole + frac == 0)
    return IDRIS2I_1_NOT_A_NUMBER;
  if (*p == 'e' || *p == 'E') {
    ++p;
    if (*p == '+' || *p == '-')
      ++p;
    size_t e = idris2i_1_digits(p);
    if (e == 0)
      return IDRIS2I_1_NOT_A_NUMBER;
    p += e;
  }
  // (a mantissa width, `|<bits>`, as `show` writes after a subnormal Double)
  if (*p == '|') {
    size_t width = idris2i_1_digits(p + 1);
    return width > 0 && p[1 + width] == '\0' ? IDRIS2I_1_DECIMAL_SYNTAX
                                              : IDRIS2I_1_NOT_A_NUMBER;
  }
  return *p == '\0' ? IDRIS2I_1_DECIMAL_SYNTAX : IDRIS2I_1_NOT_A_NUMBER;
}

// The Double nearest to num/den (den > 0), the even one of two at the same
// distance, as `exact->inexact` of Chez (mpq_get_d truncates instead).  The
// quotient is taken with at least 55 bits, the lowest of which is set when
// the division is not exact: then the bits below the 53 of the result (or
// below 2^-1074, for a subnormal result) tell which way to round, and a
// remainder is never taken for a tie.
static double idris2i_1_fractionToDouble(mpz_srcptr num, mpz_srcptr den) {
  int sign = mpz_sgn(num);
  if (sign == 0)
    return 0.0;
  // num/den is in [2^(n-m-1), 2^(n-m+1)): num/den * 2^e in [2^54, 2^56), but
  // with no bit below 2^-1076.
  long n = (long)mpz_sizeinbase(num, 2), m = (long)mpz_sizeinbase(den, 2);
  long e = 55 - (n - m);
  if (e > 1076)
    e = 1076;
  mpz_t a, b, r;
  mpz_inits(a, b, r, NULL);
  mpz_abs(a, num);
  mpz_set(b, den);
  if (e >= 0)
    mpz_mul_2exp(a, a, (mp_bitcnt_t)e);
  else
    mpz_mul_2exp(b, b, (mp_bitcnt_t)-e);
  mpz_tdiv_qr(a, r, a, b);
  // (the quotient has at most 56 bits)
  uint64_t quot = idris2i_1_mpzLow64(a) | (mpz_sgn(r) != 0);
  mpz_clears(a, b, r, NULL);

  int bits = 64 - __builtin_clzll(quot);
  long drop = bits - 53 > e - 1074 ? bits - 53 : e - 1074;
  uint64_t mant = quot >> drop;
  uint64_t rest = quot & (((uint64_t)1 << drop) - 1);
  uint64_t half = (uint64_t)1 << (drop - 1);
  if (rest > half || (rest == half && (mant & 1)))
    ++mant;
  double d = ldexp((double)mant, (int)(drop - e));
  return sign < 0 ? -d : d;
}

// A decimal number (see idris2i_1_numberSyntax) as a Double.  Without a mantissa
// width, that is what strtod reads.  With one, `x|p`, the exact value of x is
// rounded to p bits first (to the nearest, ties to even), then to a Double, as
// Chez does (so that a subnormal one reads back as `show` writes it).
static double idris2i_1_decimalToDouble(char const *s) {
  char const *bar = strchr(s, '|');
  if (bar == NULL)
    return strtod(s, NULL);

  char const *p = s;
  int negative = *p == '-';
  if (*p == '+' || *p == '-')
    ++p;
  // the digits of x without the point and its leading zeros, and the exponent
  // of their last one
  size_t len = (size_t)(bar - p);
  char *digits = malloc(len + 1);
  IDRIS2I_1_REFC_VERIFY(digits, "malloc failed");
  size_t nd = 0;
  long long exp10 = 0;
  int point = 0;
  for (; *p != '|' && *p != 'e' && *p != 'E'; ++p) {
    if (*p == '.') {
      point = 1;
    } else {
      if (nd > 0 || *p != '0')
        digits[nd++] = *p;
      if (point)
        --exp10;
    }
  }
  digits[nd] = '\0';
  if (*p == 'e' || *p == 'E') {
    // (saturated: beyond the bounds below, only the sign of the exponent
    // matters)
    ++p;
    int eneg = *p == '-';
    if (*p == '+' || *p == '-')
      ++p;
    long long e = 0;
    for (; *p != '|'; ++p)
      if (e < 1000000000)
        e = 10 * e + (*p - '0');
    exp10 += eneg ? -e : e;
  }
  unsigned long width = 0;
  for (++p; *p != '\0'; ++p)
    if (width < 1000000000)
      width = 10 * width + (unsigned long)(*p - '0');

  double d;
  if (nd == 0 || width == 0) {
    d = 0.0;
  } else if ((long long)nd + exp10 > 310) {
    // x >= 10^310 (rounding to p bits keeps it above the largest Double)
    d = INFINITY;
  } else if ((long long)nd + exp10 < -330) {
    // x < 10^-330 (and below half the smallest subnormal after rounding)
    d = 0.0;
  } else {
    mpz_t num, den, a, b, r;
    mpz_inits(num, den, a, b, r, NULL);
    mpz_set_str(num, digits, 10);
    mpz_set_ui(den, 1);
    if (exp10 >= 0) {
      mpz_ui_pow_ui(a, 10, (unsigned long)exp10);
      mpz_mul(num, num, a);
    } else {
      mpz_ui_pow_ui(den, 10, (unsigned long)-exp10);
    }
    long n = (long)mpz_sizeinbase(num, 2), m = (long)mpz_sizeinbase(den, 2);
    // A width of at least the bits of num and den, and 55 more, leaves the
    // Double that x rounds to as it is (Chez caps the width there).
    if (width < (unsigned long)(n + m + 55)) {
      // x in [2^k, 2^(k+1)), then q = x * 2^(p - 1 - k) rounded, of p bits
      long k = n - m;
      if (k >= 0) {
        mpz_mul_2exp(a, den, (mp_bitcnt_t)k);
        if (mpz_cmp(num, a) < 0)
          --k;
      } else {
        mpz_mul_2exp(a, num, (mp_bitcnt_t)-k);
        if (mpz_cmp(a, den) < 0)
          --k;
      }
      long sh = (long)width - 1 - k;
      mpz_set(a, num);
      mpz_set(b, den);
      if (sh >= 0)
        mpz_mul_2exp(a, a, (mp_bitcnt_t)sh);
      else
        mpz_mul_2exp(b, b, (mp_bitcnt_t)-sh);
      mpz_tdiv_qr(a, r, a, b);
      mpz_mul_2exp(r, r, 1);
      int c = mpz_cmp(r, b);
      if (c > 0 || (c == 0 && mpz_odd_p(a)))
        mpz_add_ui(a, a, 1);
      // x is now a * 2^-sh
      mpz_set_ui(den, 1);
      if (sh >= 0) {
        mpz_set(num, a);
        mpz_mul_2exp(den, den, (mp_bitcnt_t)sh);
      } else {
        mpz_mul_2exp(num, a, (mp_bitcnt_t)-sh);
      }
    }
    d = idris2i_1_fractionToDouble(num, den);
    mpz_clears(num, den, a, b, r, NULL);
  }
  free(digits);
  return negative ? -d : d;
}

// The digits of an integer or of a fraction, for GMP (which does not take a
// '+' sign).
static char const *idris2i_1_gmpDigits(char const *s) {
  return *s == '+' ? s + 1 : s;
}

// The number in `s`, truncated towards zero, in `out` (which is initialised).
static void idris2i_1_parseInteger(Idris2i_1_String *str, mpz_t out) {
  char const *s = str->str;
  // (a string with a NUL character in it is not a number)
  switch (strlen(s) == str->len ? idris2i_1_numberSyntax(s)
                                : IDRIS2I_1_NOT_A_NUMBER) {
  case IDRIS2I_1_INTEGER_SYNTAX:
    mpz_set_str(out, idris2i_1_gmpDigits(s), 10);
    break;
  case IDRIS2I_1_DECIMAL_SYNTAX: {
    double d = idris2i_1_decimalToDouble(s);
    if (isfinite(d))
      mpz_set_d(out, trunc(d));
    else
      mpz_set_ui(out, 0);
    break;
  }
  case IDRIS2I_1_FRACTION_SYNTAX: {
    mpq_t q;
    mpq_init(q);
    mpq_set_str(q, idris2i_1_gmpDigits(s), 10);
    mpz_tdiv_q(out, mpq_numref(q), mpq_denref(q));
    mpq_clear(q);
    break;
  }
  default:
    mpz_set_ui(out, 0);
  }
}

Idris2i_1_Value *idris2i_1_cast_string_to_Integer(Idris2i_1_Value *input) {
  Idris2i_1_Integer *retVal = idris2i_1_mkInteger();
  idris2i_1_parseInteger((Idris2i_1_String *)input, retVal->i);
  return idris2i_1_normaliseInteger(retVal);
}

// A string to a fixed size integer: through an Integer, which wraps around.
#define IDRIS2I_1_CAST_STRING_TO(ty)                                              \
  Idris2i_1_Value *idris2i_1_cast_string_to_##ty(Idris2i_1_Value *input) {              \
    Idris2i_1_Value *i = idris2i_1_cast_string_to_Integer(input);                    \
    Idris2i_1_Value *r = idris2i_1_cast_Integer_to_##ty(i);                          \
    idris2i_1_removeReference(i);                                                 \
    return r;                                                                  \
  }
IDRIS2I_1_CAST_STRING_TO(Bits8)
IDRIS2I_1_CAST_STRING_TO(Bits16)
IDRIS2I_1_CAST_STRING_TO(Bits32)
IDRIS2I_1_CAST_STRING_TO(Bits64)
IDRIS2I_1_CAST_STRING_TO(Int8)
IDRIS2I_1_CAST_STRING_TO(Int16)
IDRIS2I_1_CAST_STRING_TO(Int32)
IDRIS2I_1_CAST_STRING_TO(Int64)

// Is `s` the letters of `word` (in lower case), in any case?
static int idris2i_1_isWord(char const *s, char const *word) {
  for (; *word != '\0'; ++s, ++word)
    if (*s != *word && !(*word >= 'a' && *word <= 'z' && *s == *word - 32))
      return 0;
  return *s == '\0';
}

Idris2i_1_Value *idris2i_1_cast_string_to_Double(Idris2i_1_Value *input) {
  char const *s = ((Idris2i_1_String *)input)->str;
  int wellFormed = strlen(s) == ((Idris2i_1_String *)input)->len;
  // The values that are no numbers, written as `show` (and Scheme) writes
  // them: a sign, then `inf.0` or `nan.0` in any case, and nothing else
  // (`inf`, `nan` and `Infinity`, which strtod reads, are not numbers).
  if (wellFormed && (s[0] == '+' || s[0] == '-')) {
    if (idris2i_1_isWord(s + 1, "inf.0"))
      return idris2i_1_mkDouble(s[0] == '-' ? -INFINITY : INFINITY);
    if (idris2i_1_isWord(s + 1, "nan.0"))
      return idris2i_1_mkDouble(NAN);
  }
  switch (wellFormed ? idris2i_1_numberSyntax(s) : IDRIS2I_1_NOT_A_NUMBER) {
  case IDRIS2I_1_INTEGER_SYNTAX:
    return idris2i_1_mkDouble(strtod(s, NULL));
  case IDRIS2I_1_DECIMAL_SYNTAX:
    return idris2i_1_mkDouble(idris2i_1_decimalToDouble(s));
  case IDRIS2I_1_FRACTION_SYNTAX: {
    mpq_t q;
    mpq_init(q);
    mpq_set_str(q, idris2i_1_gmpDigits(s), 10);
    double d = idris2i_1_fractionToDouble(mpq_numref(q), mpq_denref(q));
    mpq_clear(q);
    return idris2i_1_mkDouble(d);
  }
  default:
    return idris2i_1_mkDouble(0.0);
  }
}

/*  conversions from Bits8  */
Idris2i_1_Value *idris2i_1_cast_Bits8_to_Integer(Idris2i_1_Value *input) {
  return idris2i_1_mkIntegerFromUInt64(idris2i_1_vp_to_Bits8(input));
}

Idris2i_1_Value *idris2i_1_cast_Bits8_to_string(Idris2i_1_Value *input) {
  uint8_t x = idris2i_1_vp_to_Bits8(input);

  int l = snprintf(NULL, 0, "%" PRIu8 "", x);
  Idris2i_1_String *retVal = idris2i_1_mkEmptyString(l + 1);
  sprintf(retVal->str, "%" PRIu8 "", x);
  idris2i_1_setAscii(retVal);

  return (Idris2i_1_Value *)retVal;
}

/*  conversions from Bits16  */
Idris2i_1_Value *idris2i_1_cast_Bits16_to_Integer(Idris2i_1_Value *input) {
  return idris2i_1_mkIntegerFromUInt64(idris2i_1_vp_to_Bits16(input));
}

Idris2i_1_Value *idris2i_1_cast_Bits16_to_string(Idris2i_1_Value *input) {
  uint16_t x = idris2i_1_vp_to_Bits16(input);

  int l = snprintf(NULL, 0, "%" PRIu16 "", x);
  Idris2i_1_String *retVal = idris2i_1_mkEmptyString(l + 1);
  sprintf(retVal->str, "%" PRIu16 "", x);
  idris2i_1_setAscii(retVal);

  return (Idris2i_1_Value *)retVal;
}

/*  conversions from Bits32  */
Idris2i_1_Value *idris2i_1_cast_Bits32_to_Integer(Idris2i_1_Value *input) {
  return idris2i_1_mkIntegerFromUInt64(idris2i_1_vp_to_Bits32(input));
}

Idris2i_1_Value *idris2i_1_cast_Bits32_to_string(Idris2i_1_Value *input) {
  uint32_t x = idris2i_1_vp_to_Bits32(input);

  int l = snprintf(NULL, 0, "%" PRIu32 "", x);
  Idris2i_1_String *retVal = idris2i_1_mkEmptyString(l + 1);
  sprintf(retVal->str, "%" PRIu32 "", x);
  idris2i_1_setAscii(retVal);

  return (Idris2i_1_Value *)retVal;
}

/*  conversions from Bits64  */
Idris2i_1_Value *idris2i_1_cast_Bits64_to_Integer(Idris2i_1_Value *input) {
  return idris2i_1_mkIntegerFromUInt64(idris2i_1_vp_to_Bits64(input));
}

Idris2i_1_Value *idris2i_1_cast_Bits64_to_string(Idris2i_1_Value *input) {
  uint64_t x = idris2i_1_vp_to_Bits64(input);

  int l = snprintf(NULL, 0, "%" PRIu64 "", x);
  Idris2i_1_String *retVal = idris2i_1_mkEmptyString(l + 1);
  sprintf(retVal->str, "%" PRIu64 "", x);
  idris2i_1_setAscii(retVal);

  return (Idris2i_1_Value *)retVal;
}

/*  conversions from Integer */
uint64_t mpz_get_lsb(mpz_srcptr i, mp_bitcnt_t b) {
  mpz_t r;
  mpz_init(r);
  mpz_fdiv_r_2exp(r, i, b);
  uint64_t retVal = idris2i_1_mpzLow64(r);
  mpz_clear(r);
  return retVal;
}

uint64_t idris2i_1_integerLow64Slow(Idris2i_1_Value *input) {
  IDRIS2I_1_INTEGER_MPZ(fromi, input);
  return mpz_get_lsb(fromi, 64);
}

Idris2i_1_Value *idris2i_1_cast_Integer_to_Bits8(Idris2i_1_Value *input) {
  if (idris2i_1_isSmallInteger(input)) {
    int64_t n = idris2i_1_smallInteger(input);
    return (Idris2i_1_Value *)idris2i_1_mkBits8((uint8_t)n);
  }
  IDRIS2I_1_INTEGER_MPZ(fromi, input);
  return (Idris2i_1_Value *)idris2i_1_mkBits8((uint8_t)mpz_get_lsb(fromi, 8));
}

Idris2i_1_Value *idris2i_1_cast_Integer_to_Bits16(Idris2i_1_Value *input) {
  if (idris2i_1_isSmallInteger(input)) {
    int64_t n = idris2i_1_smallInteger(input);
    return (Idris2i_1_Value *)idris2i_1_mkBits16((uint16_t)n);
  }
  IDRIS2I_1_INTEGER_MPZ(fromi, input);
  return (Idris2i_1_Value *)idris2i_1_mkBits16((uint16_t)mpz_get_lsb(fromi, 16));
}

Idris2i_1_Value *idris2i_1_cast_Integer_to_Bits32(Idris2i_1_Value *input) {
  if (idris2i_1_isSmallInteger(input)) {
    int64_t n = idris2i_1_smallInteger(input);
    return (Idris2i_1_Value *)idris2i_1_mkBits32((uint32_t)n);
  }
  IDRIS2I_1_INTEGER_MPZ(fromi, input);
  return (Idris2i_1_Value *)idris2i_1_mkBits32((uint32_t)mpz_get_lsb(fromi, 32));
}

Idris2i_1_Value *idris2i_1_cast_Integer_to_Bits64(Idris2i_1_Value *input) {
  if (idris2i_1_isSmallInteger(input)) {
    int64_t n = idris2i_1_smallInteger(input);
    return (Idris2i_1_Value *)idris2i_1_mkBits64((uint64_t)n);
  }
  IDRIS2I_1_INTEGER_MPZ(fromi, input);
  return (Idris2i_1_Value *)idris2i_1_mkBits64((uint64_t)mpz_get_lsb(fromi, 64));
}

Idris2i_1_Value *idris2i_1_cast_Integer_to_Int8(Idris2i_1_Value *input) {
  if (idris2i_1_isSmallInteger(input)) {
    int64_t n = idris2i_1_smallInteger(input);
    return (Idris2i_1_Value *)idris2i_1_mkInt8((int8_t)n);
  }
  IDRIS2I_1_INTEGER_MPZ(fromi, input);
  return (Idris2i_1_Value *)idris2i_1_mkInt8((int8_t)mpz_get_lsb(fromi, 8));
}

Idris2i_1_Value *idris2i_1_cast_Integer_to_Int16(Idris2i_1_Value *input) {
  if (idris2i_1_isSmallInteger(input)) {
    int64_t n = idris2i_1_smallInteger(input);
    return (Idris2i_1_Value *)idris2i_1_mkInt16((int16_t)n);
  }
  IDRIS2I_1_INTEGER_MPZ(fromi, input);
  return (Idris2i_1_Value *)idris2i_1_mkInt16((int16_t)mpz_get_lsb(fromi, 16));
}

Idris2i_1_Value *idris2i_1_cast_Integer_to_Int32(Idris2i_1_Value *input) {
  if (idris2i_1_isSmallInteger(input)) {
    int64_t n = idris2i_1_smallInteger(input);
    return (Idris2i_1_Value *)idris2i_1_mkInt32((int32_t)n);
  }
  IDRIS2I_1_INTEGER_MPZ(fromi, input);
  return (Idris2i_1_Value *)idris2i_1_mkInt32((int32_t)mpz_get_lsb(fromi, 32));
}

Idris2i_1_Value *idris2i_1_cast_Integer_to_Int64(Idris2i_1_Value *input) {
  if (idris2i_1_isSmallInteger(input)) {
    int64_t n = idris2i_1_smallInteger(input);
    return (Idris2i_1_Value *)idris2i_1_mkInt64(n);
  }
  IDRIS2I_1_INTEGER_MPZ(fromi, input);
  return (Idris2i_1_Value *)idris2i_1_mkInt64((int64_t)mpz_get_lsb(fromi, 64));
}

double idris2i_1_integerToDoubleSlow(Idris2i_1_Value *input) {
  IDRIS2I_1_INTEGER_MPZ(fromi, input);
  // mpz_get_d truncates, but the other backends round to the nearest Double,
  // as strtod does.
  if (mpz_fits_slong_p(fromi) && sizeof(long) >= 8)
    return (double)mpz_get_si(fromi);
  char *digits = mpz_get_str(NULL, 10, fromi);
  double d = strtod(digits, NULL);
  free(digits);
  return d;
}

Idris2i_1_Value *idris2i_1_cast_Integer_to_Double(Idris2i_1_Value *input) {
  return (Idris2i_1_Value *)idris2i_1_mkDouble(idris2i_1_integerToDouble(input));
}

Idris2i_1_Value *idris2i_1_cast_Integer_to_Char(Idris2i_1_Value *input) {
  if (idris2i_1_isSmallInteger(input)) {
    int64_t n = idris2i_1_smallInteger(input);
    return (Idris2i_1_Value *)idris2i_1_mkValidChar(n);
  }
  IDRIS2I_1_INTEGER_MPZ(fromi, input);
  if (!mpz_fits_slong_p(fromi))
    return idris2i_1_mkChar(0);
  return idris2i_1_mkValidChar(mpz_get_si(fromi));
}

Idris2i_1_Value *idris2i_1_cast_Integer_to_string(Idris2i_1_Value *input) {
  IDRIS2I_1_INTEGER_MPZ(fromi, input);
  Idris2i_1_String *retVal = idris2i_1_mkStringOwned(mpz_get_str(NULL, 10, fromi));
  idris2i_1_setAscii(retVal);
  return (Idris2i_1_Value *)retVal;
}
