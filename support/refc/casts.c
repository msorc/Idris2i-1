#include "casts.h"

#include <inttypes.h>

Idris2_Value *idris2_mkValidChar(int64_t c) {
  return idris2_mkChar(idris2_isValidCodePoint(c) ? c : 0);
}

/*  conversions from Int8  */
Idris2_Value *idris2_cast_Int8_to_Integer(Idris2_Value *input) {
  return idris2_mkIntegerFromInt64(idris2_vp_to_Int8(input));
}

Idris2_Value *idris2_cast_Int8_to_string(Idris2_Value *input) {
  int8_t x = idris2_vp_to_Int8(input);

  int l = snprintf(NULL, 0, "%" PRId8 "", x);
  Idris2_String *retVal = idris2_mkEmptyString(l + 1);
  sprintf(retVal->str, "%" PRId8 "", x);
  idris2_setAscii(retVal);

  return (Idris2_Value *)retVal;
}

/*  conversions from Int16  */
Idris2_Value *idris2_cast_Int16_to_Integer(Idris2_Value *input) {
  return idris2_mkIntegerFromInt64(idris2_vp_to_Int16(input));
}

Idris2_Value *idris2_cast_Int16_to_string(Idris2_Value *input) {
  int16_t x = idris2_vp_to_Int16(input);

  int l = snprintf(NULL, 0, "%" PRId16 "", x);
  Idris2_String *retVal = idris2_mkEmptyString(l + 1);
  sprintf(retVal->str, "%" PRId16 "", x);
  idris2_setAscii(retVal);

  return (Idris2_Value *)retVal;
}

/*  conversions from Int32  */
Idris2_Value *idris2_cast_Int32_to_Integer(Idris2_Value *input) {
  return idris2_mkIntegerFromInt64(idris2_vp_to_Int32(input));
}

Idris2_Value *idris2_cast_Int32_to_string(Idris2_Value *input) {
  int32_t x = idris2_vp_to_Int32(input);

  int l = snprintf(NULL, 0, "%" PRId32 "", x);
  Idris2_String *retVal = idris2_mkEmptyString(l + 1);
  sprintf(retVal->str, "%" PRId32 "", x);
  idris2_setAscii(retVal);

  return (Idris2_Value *)retVal;
}

/*  conversions from Int64  */
Idris2_Value *idris2_cast_Int64_to_Integer(Idris2_Value *input) {
  return idris2_mkIntegerFromInt64(idris2_vp_to_Int64(input));
}

Idris2_Value *idris2_cast_Int64_to_string(Idris2_Value *input) {
  int64_t from = idris2_vp_to_Int64(input);
  int l = snprintf(NULL, 0, "%" PRId64 "", from);
  Idris2_String *retVal = idris2_mkEmptyString(l + 1);
  sprintf(retVal->str, "%" PRId64 "", from);
  idris2_setAscii(retVal);

  return (Idris2_Value *)retVal;
}

Idris2_Value *idris2_mkIntegerFromDouble(double d) {
  Idris2_Integer *retVal = idris2_mkInteger();
  mpz_set_d(retVal->i, d);

  return idris2_normaliseInteger(retVal);
}

Idris2_Value *idris2_cast_Double_to_Integer(Idris2_Value *input) {
  return idris2_mkIntegerFromDouble(idris2_vp_to_Double(input));
}

/*
 * Print a Double the way Chez Scheme does, so that every backend shows the
 * same text: the shortest digits that read back as the same number, in
 * positional notation when the decimal exponent is between -3 and 9 and in
 * scientific notation otherwise ("0.001", "1e-4", "123.0", "1e10"), with
 * "|<bits>" after a subnormal number.
 */
/*
 * printf rounds a decimal tie to even, but Chez rounds it up (2.5 -> 3).  When
 * the shortest digits in buf (prec of them, d.ddde<exp>) are a tie, replace
 * them with the rounded up digits, provided those read back as x too.
 */
static void roundTiesUp(double x, int prec, char *buf) {
  /* A double has an exact decimal expansion of at most 767 digits. */
  char exact[800];
  snprintf(exact, sizeof(exact), "%.*e", 780, x);

  /* digits of the exact expansion, then its exponent */
  char d[800];
  int n = 0;
  char *p = exact;
  while (*p != 'e') {
    if (*p >= '0' && *p <= '9')
      d[n++] = *p;
    p++;
  }
  int e = atoi(p + 1);

  if (n <= prec || d[prec] != '5')
    return;
  for (int i = prec + 1; i < n; i++)
    if (d[i] != '0')
      return;

  /* Truncate to prec digits and add one in the last place. */
  int i = prec - 1;
  while (i >= 0 && d[i] == '9') {
    d[i] = '0';
    i--;
  }
  if (i < 0) {
    memmove(d + 1, d, prec - 1);
    d[0] = '1';
    e++;
  } else {
    d[i]++;
  }

  char up[40];
  char *o = up;
  *o++ = d[0];
  if (prec > 1) {
    *o++ = '.';
    memcpy(o, d + 1, prec - 1);
    o += prec - 1;
  }
  sprintf(o, "e%d", e);
  if (strtod(up, NULL) == x)
    strcpy(buf, up);
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

  char buf[40];
  int prec;
  for (prec = 1; prec < 17; prec++) {
    snprintf(buf, sizeof(buf), "%.*e", prec - 1, x);
    if (strtod(buf, NULL) == x)
      break;
  }
  snprintf(buf, sizeof(buf), "%.*e", prec - 1, x);
  roundTiesUp(x, prec, buf);

  /* buf is d[.ddd]e<exponent> */
  char digits[20];
  int n = 0;
  char *p = buf;
  while (*p != 'e') {
    if (*p >= '0' && *p <= '9')
      digits[n++] = *p;
    p++;
  }
  int k = atoi(p + 1);
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

Idris2_Value *idris2_cast_Double_to_string(Idris2_Value *input) {
  char buf[64];
  formatDouble(idris2_vp_to_Double(input), buf);
  Idris2_String *retVal = idris2_mkString(buf);
  idris2_setAscii(retVal);
  return (Idris2_Value *)retVal;
}

uint64_t idris2_double_to_wrapped(double d) {
  if (!isfinite(d))
    return 0;
  if (fabs(d) < 9.2e18)
    return (uint64_t)(int64_t)d;
  double t = fmod(trunc(d), 18446744073709551616.0);
  if (t < 0)
    t += 18446744073709551616.0;
  if (t >= 18446744073709551616.0)
    return 0;
  return (uint64_t)t;
}

int64_t idris2_double_to_char_code(double d) {
  if (!(d > -1.0 && d < 1114112.0))
    return -1;
  return (int64_t)d;
}

Idris2_Value *idris2_cast_Char_to_Integer(Idris2_Value *input) {
  return idris2_mkIntegerFromInt64(idris2_vp_to_Char(input));
}

Idris2_Value *idris2_cast_Char_to_string(Idris2_Value *input) {
  uint32_t c = idris2_vp_to_Char(input);
  Idris2_String *retVal =
      idris2_mkEmptyString(idris2_utf8_encodedLength(c) + 1);
  idris2_utf8_encode(c, retVal->str);
  if (idris2_isValidCodePoint(c))
    idris2_setCodePoints(retVal, 1);

  return (Idris2_Value *)retVal;
}

Idris2_Value *idris2_cast_string_to_Char(Idris2_Value *input) {
  char const *s = ((Idris2_String *)input)->str;
  return idris2_mkChar(((Idris2_String *)input)->len == 0
                           ? 0
                           : idris2_utf8_decode(&s));
}

/* Conversions from String, like the Chez backend: the whole string is read
   as a number (an integer, a decimal number or a fraction, see
   `cast-string-int` in support.ss); anything else is 0.  The number is
   truncated towards zero, and wrapped around to fit a fixed size type. */

enum { IDRIS2_NOT_A_NUMBER, IDRIS2_INTEGER_SYNTAX, IDRIS2_DECIMAL_SYNTAX,
       IDRIS2_FRACTION_SYNTAX };

static size_t idris2_digits(char const *s) {
  size_t n = 0;
  while (s[n] >= '0' && s[n] <= '9')
    ++n;
  return n;
}

// The kind of number that `s` is written as.
static int idris2_numberSyntax(char const *s) {
  char const *p = s;
  if (*p == '+' || *p == '-')
    ++p;
  size_t whole = idris2_digits(p);
  p += whole;
  if (*p == '\0')
    return whole > 0 ? IDRIS2_INTEGER_SYNTAX : IDRIS2_NOT_A_NUMBER;
  if (*p == '/') {
    // (a fraction with a zero denominator is no number for Scheme either)
    size_t denom = idris2_digits(p + 1);
    size_t zeros = 0;
    while (zeros < denom && p[1 + zeros] == '0')
      ++zeros;
    return whole > 0 && denom > zeros && p[1 + denom] == '\0'
               ? IDRIS2_FRACTION_SYNTAX
               : IDRIS2_NOT_A_NUMBER;
  }
  size_t frac = 0;
  if (*p == '.') {
    frac = idris2_digits(p + 1);
    p += 1 + frac;
  }
  if (whole + frac == 0)
    return IDRIS2_NOT_A_NUMBER;
  if (*p == 'e' || *p == 'E') {
    ++p;
    if (*p == '+' || *p == '-')
      ++p;
    size_t e = idris2_digits(p);
    if (e == 0)
      return IDRIS2_NOT_A_NUMBER;
    p += e;
  }
  return *p == '\0' ? IDRIS2_DECIMAL_SYNTAX : IDRIS2_NOT_A_NUMBER;
}

// The digits of an integer or of a fraction, for GMP (which does not take a
// '+' sign).
static char const *idris2_gmpDigits(char const *s) {
  return *s == '+' ? s + 1 : s;
}

// The number in `s`, truncated towards zero, in `out` (which is initialised).
static void idris2_parseInteger(Idris2_String *str, mpz_t out) {
  char const *s = str->str;
  // (a string with a NUL character in it is not a number)
  switch (strlen(s) == str->len ? idris2_numberSyntax(s)
                                : IDRIS2_NOT_A_NUMBER) {
  case IDRIS2_INTEGER_SYNTAX:
    mpz_set_str(out, idris2_gmpDigits(s), 10);
    break;
  case IDRIS2_DECIMAL_SYNTAX: {
    double d = strtod(s, NULL);
    if (isfinite(d))
      mpz_set_d(out, trunc(d));
    else
      mpz_set_ui(out, 0);
    break;
  }
  case IDRIS2_FRACTION_SYNTAX: {
    mpq_t q;
    mpq_init(q);
    mpq_set_str(q, idris2_gmpDigits(s), 10);
    mpz_tdiv_q(out, mpq_numref(q), mpq_denref(q));
    mpq_clear(q);
    break;
  }
  default:
    mpz_set_ui(out, 0);
  }
}

Idris2_Value *idris2_cast_string_to_Integer(Idris2_Value *input) {
  Idris2_Integer *retVal = idris2_mkInteger();
  idris2_parseInteger((Idris2_String *)input, retVal->i);
  return idris2_normaliseInteger(retVal);
}

// A string to a fixed size integer: through an Integer, which wraps around.
#define IDRIS2_CAST_STRING_TO(ty)                                              \
  Idris2_Value *idris2_cast_string_to_##ty(Idris2_Value *input) {              \
    Idris2_Value *i = idris2_cast_string_to_Integer(input);                    \
    Idris2_Value *r = idris2_cast_Integer_to_##ty(i);                          \
    idris2_removeReference(i);                                                 \
    return r;                                                                  \
  }
IDRIS2_CAST_STRING_TO(Bits8)
IDRIS2_CAST_STRING_TO(Bits16)
IDRIS2_CAST_STRING_TO(Bits32)
IDRIS2_CAST_STRING_TO(Bits64)
IDRIS2_CAST_STRING_TO(Int8)
IDRIS2_CAST_STRING_TO(Int16)
IDRIS2_CAST_STRING_TO(Int32)
IDRIS2_CAST_STRING_TO(Int64)

// Is `s` the letters of `word` (in lower case), in any case?
static int idris2_isWord(char const *s, char const *word) {
  for (; *word != '\0'; ++s, ++word)
    if (*s != *word && !(*word >= 'a' && *word <= 'z' && *s == *word - 32))
      return 0;
  return *s == '\0';
}

Idris2_Value *idris2_cast_string_to_Double(Idris2_Value *input) {
  char const *s = ((Idris2_String *)input)->str;
  int wellFormed = strlen(s) == ((Idris2_String *)input)->len;
  // The values that are no numbers, written as `show` (and Scheme) writes
  // them: a sign, then `inf.0` or `nan.0` in any case, and nothing else
  // (`inf`, `nan` and `Infinity`, which strtod reads, are not numbers).
  if (wellFormed && (s[0] == '+' || s[0] == '-')) {
    if (idris2_isWord(s + 1, "inf.0"))
      return idris2_mkDouble(s[0] == '-' ? -INFINITY : INFINITY);
    if (idris2_isWord(s + 1, "nan.0"))
      return idris2_mkDouble(NAN);
  }
  switch (wellFormed ? idris2_numberSyntax(s) : IDRIS2_NOT_A_NUMBER) {
  case IDRIS2_INTEGER_SYNTAX:
  case IDRIS2_DECIMAL_SYNTAX:
    return idris2_mkDouble(strtod(s, NULL));
  case IDRIS2_FRACTION_SYNTAX: {
    mpq_t q;
    mpq_init(q);
    mpq_set_str(q, idris2_gmpDigits(s), 10);
    mpq_canonicalize(q);
    double d = mpq_get_d(q);
    mpq_clear(q);
    return idris2_mkDouble(d);
  }
  default:
    return idris2_mkDouble(0.0);
  }
}

/*  conversions from Bits8  */
Idris2_Value *idris2_cast_Bits8_to_Integer(Idris2_Value *input) {
  return idris2_mkIntegerFromUInt64(idris2_vp_to_Bits8(input));
}

Idris2_Value *idris2_cast_Bits8_to_string(Idris2_Value *input) {
  uint8_t x = idris2_vp_to_Bits8(input);

  int l = snprintf(NULL, 0, "%" PRIu8 "", x);
  Idris2_String *retVal = idris2_mkEmptyString(l + 1);
  sprintf(retVal->str, "%" PRIu8 "", x);
  idris2_setAscii(retVal);

  return (Idris2_Value *)retVal;
}

/*  conversions from Bits16  */
Idris2_Value *idris2_cast_Bits16_to_Integer(Idris2_Value *input) {
  return idris2_mkIntegerFromUInt64(idris2_vp_to_Bits16(input));
}

Idris2_Value *idris2_cast_Bits16_to_string(Idris2_Value *input) {
  uint16_t x = idris2_vp_to_Bits16(input);

  int l = snprintf(NULL, 0, "%" PRIu16 "", x);
  Idris2_String *retVal = idris2_mkEmptyString(l + 1);
  sprintf(retVal->str, "%" PRIu16 "", x);
  idris2_setAscii(retVal);

  return (Idris2_Value *)retVal;
}

/*  conversions from Bits32  */
Idris2_Value *idris2_cast_Bits32_to_Integer(Idris2_Value *input) {
  return idris2_mkIntegerFromUInt64(idris2_vp_to_Bits32(input));
}

Idris2_Value *idris2_cast_Bits32_to_string(Idris2_Value *input) {
  uint32_t x = idris2_vp_to_Bits32(input);

  int l = snprintf(NULL, 0, "%" PRIu32 "", x);
  Idris2_String *retVal = idris2_mkEmptyString(l + 1);
  sprintf(retVal->str, "%" PRIu32 "", x);
  idris2_setAscii(retVal);

  return (Idris2_Value *)retVal;
}

/*  conversions from Bits64  */
Idris2_Value *idris2_cast_Bits64_to_Integer(Idris2_Value *input) {
  return idris2_mkIntegerFromUInt64(idris2_vp_to_Bits64(input));
}

Idris2_Value *idris2_cast_Bits64_to_string(Idris2_Value *input) {
  uint64_t x = idris2_vp_to_Bits64(input);

  int l = snprintf(NULL, 0, "%" PRIu64 "", x);
  Idris2_String *retVal = idris2_mkEmptyString(l + 1);
  sprintf(retVal->str, "%" PRIu64 "", x);
  idris2_setAscii(retVal);

  return (Idris2_Value *)retVal;
}

/*  conversions from Integer */
uint64_t mpz_get_lsb(mpz_srcptr i, mp_bitcnt_t b) {
  mpz_t r;
  mpz_init(r);
  mpz_fdiv_r_2exp(r, i, b);
  uint64_t retVal = idris2_mpzLow64(r);
  mpz_clear(r);
  return retVal;
}

uint64_t idris2_integerLow64Slow(Idris2_Value *input) {
  IDRIS2_INTEGER_MPZ(fromi, input);
  return mpz_get_lsb(fromi, 64);
}

Idris2_Value *idris2_cast_Integer_to_Bits8(Idris2_Value *input) {
  if (idris2_isSmallInteger(input)) {
    int64_t n = idris2_smallInteger(input);
    return (Idris2_Value *)idris2_mkBits8((uint8_t)n);
  }
  IDRIS2_INTEGER_MPZ(fromi, input);
  return (Idris2_Value *)idris2_mkBits8((uint8_t)mpz_get_lsb(fromi, 8));
}

Idris2_Value *idris2_cast_Integer_to_Bits16(Idris2_Value *input) {
  if (idris2_isSmallInteger(input)) {
    int64_t n = idris2_smallInteger(input);
    return (Idris2_Value *)idris2_mkBits16((uint16_t)n);
  }
  IDRIS2_INTEGER_MPZ(fromi, input);
  return (Idris2_Value *)idris2_mkBits16((uint16_t)mpz_get_lsb(fromi, 16));
}

Idris2_Value *idris2_cast_Integer_to_Bits32(Idris2_Value *input) {
  if (idris2_isSmallInteger(input)) {
    int64_t n = idris2_smallInteger(input);
    return (Idris2_Value *)idris2_mkBits32((uint32_t)n);
  }
  IDRIS2_INTEGER_MPZ(fromi, input);
  return (Idris2_Value *)idris2_mkBits32((uint32_t)mpz_get_lsb(fromi, 32));
}

Idris2_Value *idris2_cast_Integer_to_Bits64(Idris2_Value *input) {
  if (idris2_isSmallInteger(input)) {
    int64_t n = idris2_smallInteger(input);
    return (Idris2_Value *)idris2_mkBits64((uint64_t)n);
  }
  IDRIS2_INTEGER_MPZ(fromi, input);
  return (Idris2_Value *)idris2_mkBits64((uint64_t)mpz_get_lsb(fromi, 64));
}

Idris2_Value *idris2_cast_Integer_to_Int8(Idris2_Value *input) {
  if (idris2_isSmallInteger(input)) {
    int64_t n = idris2_smallInteger(input);
    return (Idris2_Value *)idris2_mkInt8((int8_t)n);
  }
  IDRIS2_INTEGER_MPZ(fromi, input);
  return (Idris2_Value *)idris2_mkInt8((int8_t)mpz_get_lsb(fromi, 8));
}

Idris2_Value *idris2_cast_Integer_to_Int16(Idris2_Value *input) {
  if (idris2_isSmallInteger(input)) {
    int64_t n = idris2_smallInteger(input);
    return (Idris2_Value *)idris2_mkInt16((int16_t)n);
  }
  IDRIS2_INTEGER_MPZ(fromi, input);
  return (Idris2_Value *)idris2_mkInt16((int16_t)mpz_get_lsb(fromi, 16));
}

Idris2_Value *idris2_cast_Integer_to_Int32(Idris2_Value *input) {
  if (idris2_isSmallInteger(input)) {
    int64_t n = idris2_smallInteger(input);
    return (Idris2_Value *)idris2_mkInt32((int32_t)n);
  }
  IDRIS2_INTEGER_MPZ(fromi, input);
  return (Idris2_Value *)idris2_mkInt32((int32_t)mpz_get_lsb(fromi, 32));
}

Idris2_Value *idris2_cast_Integer_to_Int64(Idris2_Value *input) {
  if (idris2_isSmallInteger(input)) {
    int64_t n = idris2_smallInteger(input);
    return (Idris2_Value *)idris2_mkInt64(n);
  }
  IDRIS2_INTEGER_MPZ(fromi, input);
  return (Idris2_Value *)idris2_mkInt64((int64_t)mpz_get_lsb(fromi, 64));
}

double idris2_integerToDoubleSlow(Idris2_Value *input) {
  IDRIS2_INTEGER_MPZ(fromi, input);
  // mpz_get_d truncates, but the other backends round to the nearest Double,
  // as strtod does.
  if (mpz_fits_slong_p(fromi) && sizeof(long) >= 8)
    return (double)mpz_get_si(fromi);
  char *digits = mpz_get_str(NULL, 10, fromi);
  double d = strtod(digits, NULL);
  free(digits);
  return d;
}

Idris2_Value *idris2_cast_Integer_to_Double(Idris2_Value *input) {
  return (Idris2_Value *)idris2_mkDouble(idris2_integerToDouble(input));
}

Idris2_Value *idris2_cast_Integer_to_Char(Idris2_Value *input) {
  if (idris2_isSmallInteger(input)) {
    int64_t n = idris2_smallInteger(input);
    return (Idris2_Value *)idris2_mkValidChar(n);
  }
  IDRIS2_INTEGER_MPZ(fromi, input);
  if (!mpz_fits_slong_p(fromi))
    return idris2_mkChar(0);
  return idris2_mkValidChar(mpz_get_si(fromi));
}

Idris2_Value *idris2_cast_Integer_to_string(Idris2_Value *input) {
  IDRIS2_INTEGER_MPZ(fromi, input);
  Idris2_String *retVal = idris2_mkStringOwned(mpz_get_str(NULL, 10, fromi));
  idris2_setAscii(retVal);
  return (Idris2_Value *)retVal;
}
