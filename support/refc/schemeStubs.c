#include "schemeStubs.h"

static void scheme_unavailable(char const *what) {
  fprintf(stderr,
          "INTERNAL ERROR: %s: the Scheme evaluator is not available when "
          "Idris2i-1 is compiled with the RefC backend\n",
          what);
  abort();
}

Idris2i_1_Value *idris2i_1_refc_scheme_eval_scheme(Idris2i_1_Value *expr) {
  (void)expr;
  return NULL;
}

int64_t idris2i_1_refc_scheme_eval_okay(Idris2i_1_Value *obj) {
  (void)obj;
  return 0;
}

Idris2i_1_Value *idris2i_1_refc_scheme_get_eval_result(Idris2i_1_Value *obj) {
  (void)obj;
  scheme_unavailable("getEvalResult");
  return NULL;
}

void idris2i_1_refc_scheme_debug_scheme(Idris2i_1_Value *obj) { (void)obj; }

#define NOT_A(kind)                                                            \
  int64_t idris2i_1_refc_scheme_is_##kind(Idris2i_1_Value *obj) {                    \
    (void)obj;                                                                 \
    return 0;                                                                  \
  }
NOT_A(number)
NOT_A(integer)
NOT_A(float)
NOT_A(char)
NOT_A(string)
NOT_A(procedure)
NOT_A(symbol)
NOT_A(nil)
NOT_A(pair)
NOT_A(vector)
NOT_A(box)
#undef NOT_A

#define UNREACHABLE(ret, name, ...)                                            \
  ret idris2i_1_refc_scheme_##name(__VA_ARGS__) {                                 \
    scheme_unavailable(#name);                                                 \
    return 0;                                                                  \
  }
UNREACHABLE(Idris2i_1_Value *, id_integer, Idris2i_1_Value *obj)
UNREACHABLE(Idris2i_1_Value *, id_string, Idris2i_1_Value *obj)
UNREACHABLE(double, id_float, Idris2i_1_Value *obj)
UNREACHABLE(char, id_char, Idris2i_1_Value *obj)
UNREACHABLE(Idris2i_1_Value *, car, Idris2i_1_Value *obj)
UNREACHABLE(Idris2i_1_Value *, cdr, Idris2i_1_Value *obj)
UNREACHABLE(Idris2i_1_Value *, apply, Idris2i_1_Value *fn, Idris2i_1_Value *arg)
UNREACHABLE(Idris2i_1_Value *, force, Idris2i_1_Value *obj)
UNREACHABLE(Idris2i_1_Value *, vector_ref, Idris2i_1_Value *obj, Idris2i_1_Value *idx)
UNREACHABLE(Idris2i_1_Value *, unbox, Idris2i_1_Value *obj)
UNREACHABLE(Idris2i_1_Value *, vector_length, Idris2i_1_Value *obj)
UNREACHABLE(Idris2i_1_Value *, vector_list, Idris2i_1_Value *obj)
UNREACHABLE(Idris2i_1_Value *, read_symbol, Idris2i_1_Value *obj)
#undef UNREACHABLE

Idris2i_1_Value *idris2i_1_refc_scheme_make_symbol(Idris2i_1_Value *name) {
  (void)name;
  return NULL;
}

void idris2i_1_refc_gc(int64_t generation) { (void)generation; }
