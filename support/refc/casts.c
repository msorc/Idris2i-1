#include "casts.h"

#include <inttypes.h>

Idris2_Value *idris2_mkValidChar(int64_t c) {
  return idris2_mkChar(idris2_isValidCodePoint(c) ? c : 0);
}

/*  conversions from Int8  */
Idris2_Value *idris2_cast_Int8_to_Integer(Idris2_Value *input) {
  Idris2_Integer *retVal = idris2_mkInteger();
  mpz_set_si(retVal->i, idris2_vp_to_Int8(input));

  return (Idris2_Value *)retVal;
}

Idris2_Value *idris2_cast_Int8_to_string(Idris2_Value *input) {
  int8_t x = idris2_vp_to_Int8(input);

  int l = snprintf(NULL, 0, "%" PRId8 "", x);
  Idris2_String *retVal = idris2_mkEmptyString(l + 1);
  sprintf(retVal->str, "%" PRId8 "", x);

  return (Idris2_Value *)retVal;
}

/*  conversions from Int16  */
Idris2_Value *idris2_cast_Int16_to_Integer(Idris2_Value *input) {
  Idris2_Integer *retVal = idris2_mkInteger();
  mpz_set_si(retVal->i, idris2_vp_to_Int16(input));

  return (Idris2_Value *)retVal;
}

Idris2_Value *idris2_cast_Int16_to_string(Idris2_Value *input) {
  int16_t x = idris2_vp_to_Int16(input);

  int l = snprintf(NULL, 0, "%" PRId16 "", x);
  Idris2_String *retVal = idris2_mkEmptyString(l + 1);
  sprintf(retVal->str, "%" PRId16 "", x);

  return (Idris2_Value *)retVal;
}

/*  conversions from Int32  */
Idris2_Value *idris2_cast_Int32_to_Integer(Idris2_Value *input) {
  Idris2_Integer *retVal = idris2_mkInteger();
  mpz_set_si(retVal->i, idris2_vp_to_Int32(input));

  return (Idris2_Value *)retVal;
}

Idris2_Value *idris2_cast_Int32_to_string(Idris2_Value *input) {
  int32_t x = idris2_vp_to_Int32(input);

  int l = snprintf(NULL, 0, "%" PRId32 "", x);
  Idris2_String *retVal = idris2_mkEmptyString(l + 1);
  sprintf(retVal->str, "%" PRId32 "", x);

  return (Idris2_Value *)retVal;
}

/*  conversions from Int64  */
Idris2_Value *idris2_cast_Int64_to_Integer(Idris2_Value *input) {
  Idris2_Integer *retVal = idris2_mkInteger();
  mpz_set_si(retVal->i, idris2_vp_to_Int64(input));

  return (Idris2_Value *)retVal;
}

Idris2_Value *idris2_cast_Int64_to_string(Idris2_Value *input) {
  int64_t from = idris2_vp_to_Int64(input);
  int l = snprintf(NULL, 0, "%" PRId64 "", from);
  Idris2_String *retVal = idris2_mkEmptyString(l + 1);
  sprintf(retVal->str, "%" PRId64 "", from);

  return (Idris2_Value *)retVal;
}

Idris2_Value *idris2_cast_Double_to_Integer(Idris2_Value *input) {
  Idris2_Integer *retVal = idris2_mkInteger();
  mpz_set_d(retVal->i, idris2_vp_to_Double(input));

  return (Idris2_Value *)retVal;
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
  return (Idris2_Value *)idris2_mkString(buf);
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
  Idris2_Integer *retVal = idris2_mkInteger();
  mpz_set_si(retVal->i, idris2_vp_to_Char(input));

  return (Idris2_Value *)retVal;
}

Idris2_Value *idris2_cast_Char_to_string(Idris2_Value *input) {
  uint32_t c = idris2_vp_to_Char(input);
  Idris2_String *retVal =
      idris2_mkEmptyString(idris2_utf8_encodedLength(c) + 1);
  idris2_utf8_encode(c, retVal->str);

  return (Idris2_Value *)retVal;
}

Idris2_Value *idris2_cast_string_to_Char(Idris2_Value *input) {
  char const *s = ((Idris2_String *)input)->str;
  return idris2_mkChar(*s == '\0' ? 0 : idris2_utf8_decode(&s));
}

Idris2_Value *idris2_cast_string_to_Bits8(Idris2_Value *input) {
  Idris2_String *from = (Idris2_String *)input;
  return (Idris2_Value *)idris2_mkBits8((uint8_t)atoi(from->str));
}

Idris2_Value *idris2_cast_string_to_Bits16(Idris2_Value *input) {
  Idris2_String *from = (Idris2_String *)input;
  return (Idris2_Value *)idris2_mkBits16((uint16_t)atoi(from->str));
}

Idris2_Value *idris2_cast_string_to_Bits32(Idris2_Value *input) {
  Idris2_String *from = (Idris2_String *)input;
  return (Idris2_Value *)idris2_mkBits32((uint32_t)atoi(from->str));
}

Idris2_Value *idris2_cast_string_to_Bits64(Idris2_Value *input) {
  Idris2_String *from = (Idris2_String *)input;
  return (Idris2_Value *)idris2_mkBits64((uint64_t)atoi(from->str));
}

Idris2_Value *idris2_cast_string_to_Int8(Idris2_Value *input) {
  Idris2_String *from = (Idris2_String *)input;
  return (Idris2_Value *)idris2_mkInt8((int8_t)atoi(from->str));
}

Idris2_Value *idris2_cast_string_to_Int16(Idris2_Value *input) {
  Idris2_String *from = (Idris2_String *)input;
  return (Idris2_Value *)idris2_mkInt16((int16_t)atoi(from->str));
}

Idris2_Value *idris2_cast_string_to_Int32(Idris2_Value *input) {
  Idris2_String *from = (Idris2_String *)input;
  return (Idris2_Value *)idris2_mkInt32((int32_t)atoi(from->str));
}

Idris2_Value *idris2_cast_string_to_Int64(Idris2_Value *input) {
  Idris2_String *from = (Idris2_String *)input;
  return (Idris2_Value *)idris2_mkInt64((int64_t)atoi(from->str));
}

Idris2_Value *idris2_cast_string_to_Integer(Idris2_Value *input) {
  Idris2_String *from = (Idris2_String *)input;

  Idris2_Integer *retVal = idris2_mkInteger();
  mpz_set_str(retVal->i, from->str, 10);

  return (Idris2_Value *)retVal;
}

Idris2_Value *idris2_cast_string_to_Double(Idris2_Value *input) {
  return (Idris2_Value *)idris2_mkDouble(atof(((Idris2_String *)input)->str));
}

/*  conversions from Bits8  */
Idris2_Value *idris2_cast_Bits8_to_Integer(Idris2_Value *input) {
  Idris2_Integer *retVal = idris2_mkInteger();
  mpz_set_ui(retVal->i, idris2_vp_to_Bits8(input));

  return (Idris2_Value *)retVal;
}

Idris2_Value *idris2_cast_Bits8_to_string(Idris2_Value *input) {
  uint8_t x = idris2_vp_to_Bits8(input);

  int l = snprintf(NULL, 0, "%" PRIu8 "", x);
  Idris2_String *retVal = idris2_mkEmptyString(l + 1);
  sprintf(retVal->str, "%" PRIu8 "", x);

  return (Idris2_Value *)retVal;
}

/*  conversions from Bits16  */
Idris2_Value *idris2_cast_Bits16_to_Integer(Idris2_Value *input) {
  Idris2_Integer *retVal = idris2_mkInteger();
  mpz_set_ui(retVal->i, idris2_vp_to_Bits16(input));

  return (Idris2_Value *)retVal;
}

Idris2_Value *idris2_cast_Bits16_to_string(Idris2_Value *input) {
  uint16_t x = idris2_vp_to_Bits16(input);

  int l = snprintf(NULL, 0, "%" PRIu16 "", x);
  Idris2_String *retVal = idris2_mkEmptyString(l + 1);
  sprintf(retVal->str, "%" PRIu16 "", x);

  return (Idris2_Value *)retVal;
}

/*  conversions from Bits32  */
Idris2_Value *idris2_cast_Bits32_to_Integer(Idris2_Value *input) {
  Idris2_Integer *retVal = idris2_mkInteger();
  mpz_set_ui(retVal->i, idris2_vp_to_Bits32(input));

  return (Idris2_Value *)retVal;
}

Idris2_Value *idris2_cast_Bits32_to_string(Idris2_Value *input) {
  uint32_t x = idris2_vp_to_Bits32(input);

  int l = snprintf(NULL, 0, "%" PRIu32 "", x);
  Idris2_String *retVal = idris2_mkEmptyString(l + 1);
  sprintf(retVal->str, "%" PRIu32 "", x);

  return (Idris2_Value *)retVal;
}

/*  conversions from Bits64  */
Idris2_Value *idris2_cast_Bits64_to_Integer(Idris2_Value *input) {
  Idris2_Integer *retVal = idris2_mkInteger();
  mpz_set_ui(retVal->i, idris2_vp_to_Bits64(input));

  return (Idris2_Value *)retVal;
}

Idris2_Value *idris2_cast_Bits64_to_string(Idris2_Value *input) {
  uint64_t x = idris2_vp_to_Bits64(input);

  int l = snprintf(NULL, 0, "%" PRIu64 "", x);
  Idris2_String *retVal = idris2_mkEmptyString(l + 1);
  sprintf(retVal->str, "%" PRIu64 "", x);

  return (Idris2_Value *)retVal;
}

/*  conversions from Integer */
uint64_t mpz_get_lsb(mpz_t i, mp_bitcnt_t b) {
  mpz_t r;
  mpz_init(r);
  mpz_fdiv_r_2exp(r, i, b);
  uint64_t retVal = mpz_get_ui(r);
  mpz_clear(r);
  return retVal;
}

Idris2_Value *idris2_cast_Integer_to_Bits8(Idris2_Value *input) {
  Idris2_Integer *from = (Idris2_Integer *)input;
  return (Idris2_Value *)idris2_mkBits8((uint8_t)mpz_get_lsb(from->i, 8));
}

Idris2_Value *idris2_cast_Integer_to_Bits16(Idris2_Value *input) {
  Idris2_Integer *from = (Idris2_Integer *)input;
  return (Idris2_Value *)idris2_mkBits16((uint16_t)mpz_get_lsb(from->i, 16));
}

Idris2_Value *idris2_cast_Integer_to_Bits32(Idris2_Value *input) {
  Idris2_Integer *from = (Idris2_Integer *)input;
  return (Idris2_Value *)idris2_mkBits32((uint32_t)mpz_get_lsb(from->i, 32));
}

Idris2_Value *idris2_cast_Integer_to_Bits64(Idris2_Value *input) {
  Idris2_Integer *from = (Idris2_Integer *)input;
  return (Idris2_Value *)idris2_mkBits64((uint64_t)mpz_get_lsb(from->i, 64));
}

Idris2_Value *idris2_cast_Integer_to_Int8(Idris2_Value *input) {
  Idris2_Integer *from = (Idris2_Integer *)input;
  return (Idris2_Value *)idris2_mkInt8((int8_t)mpz_get_lsb(from->i, 8));
}

Idris2_Value *idris2_cast_Integer_to_Int16(Idris2_Value *input) {
  Idris2_Integer *from = (Idris2_Integer *)input;
  return (Idris2_Value *)idris2_mkInt16((int16_t)mpz_get_lsb(from->i, 16));
}

Idris2_Value *idris2_cast_Integer_to_Int32(Idris2_Value *input) {
  Idris2_Integer *from = (Idris2_Integer *)input;
  return (Idris2_Value *)idris2_mkInt32((int32_t)mpz_get_lsb(from->i, 32));
}

Idris2_Value *idris2_cast_Integer_to_Int64(Idris2_Value *input) {
  Idris2_Integer *from = (Idris2_Integer *)input;
  return (Idris2_Value *)idris2_mkInt64((int64_t)mpz_get_lsb(from->i, 64));
}

Idris2_Value *idris2_cast_Integer_to_Double(Idris2_Value *input) {
  Idris2_Integer *from = (Idris2_Integer *)input;
  return (Idris2_Value *)idris2_mkDouble(mpz_get_d(from->i));
}

Idris2_Value *idris2_cast_Integer_to_Char(Idris2_Value *input) {
  Idris2_Integer *from = (Idris2_Integer *)input;
  if (!mpz_fits_slong_p(from->i))
    return idris2_mkChar(0);
  return idris2_mkValidChar(mpz_get_si(from->i));
}

Idris2_Value *idris2_cast_Integer_to_string(Idris2_Value *input) {
  Idris2_Integer *from = (Idris2_Integer *)input;

  Idris2_String *retVal = IDRIS2_NEW_VALUE(Idris2_String);
  retVal->header.tag = STRING_TAG;
  retVal->str = mpz_get_str(NULL, 10, from->i);

  return (Idris2_Value *)retVal;
}
