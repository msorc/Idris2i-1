#pragma once

#include "cBackend.h"

/*
 * Stand-ins for the in-process Scheme evaluator of the compiler
 * (src/Libraries/Utils/Scheme.idr), which exists only when the compiler runs
 * on Chez.  Evaluation always fails, so a compiler built with RefC reports
 * that the Scheme evaluator is unavailable instead of using it.  The
 * accessors can only be reached after a successful evaluation, so they abort.
 */

Idris2i_1_Value *idris2i_1_refc_scheme_eval_scheme(Idris2i_1_Value *expr);
int64_t idris2i_1_refc_scheme_eval_okay(Idris2i_1_Value *obj);
Idris2i_1_Value *idris2i_1_refc_scheme_get_eval_result(Idris2i_1_Value *obj);
void idris2i_1_refc_scheme_debug_scheme(Idris2i_1_Value *obj);

int64_t idris2i_1_refc_scheme_is_number(Idris2i_1_Value *obj);
int64_t idris2i_1_refc_scheme_is_integer(Idris2i_1_Value *obj);
int64_t idris2i_1_refc_scheme_is_float(Idris2i_1_Value *obj);
int64_t idris2i_1_refc_scheme_is_char(Idris2i_1_Value *obj);
int64_t idris2i_1_refc_scheme_is_string(Idris2i_1_Value *obj);
int64_t idris2i_1_refc_scheme_is_procedure(Idris2i_1_Value *obj);
int64_t idris2i_1_refc_scheme_is_symbol(Idris2i_1_Value *obj);
int64_t idris2i_1_refc_scheme_is_nil(Idris2i_1_Value *obj);
int64_t idris2i_1_refc_scheme_is_pair(Idris2i_1_Value *obj);
int64_t idris2i_1_refc_scheme_is_vector(Idris2i_1_Value *obj);
int64_t idris2i_1_refc_scheme_is_box(Idris2i_1_Value *obj);

Idris2i_1_Value *idris2i_1_refc_scheme_id_integer(Idris2i_1_Value *obj);
Idris2i_1_Value *idris2i_1_refc_scheme_id_string(Idris2i_1_Value *obj);
double idris2i_1_refc_scheme_id_float(Idris2i_1_Value *obj);
char idris2i_1_refc_scheme_id_char(Idris2i_1_Value *obj);
Idris2i_1_Value *idris2i_1_refc_scheme_car(Idris2i_1_Value *obj);
Idris2i_1_Value *idris2i_1_refc_scheme_cdr(Idris2i_1_Value *obj);
Idris2i_1_Value *idris2i_1_refc_scheme_apply(Idris2i_1_Value *fn, Idris2i_1_Value *arg);
Idris2i_1_Value *idris2i_1_refc_scheme_force(Idris2i_1_Value *obj);
Idris2i_1_Value *idris2i_1_refc_scheme_vector_ref(Idris2i_1_Value *obj,
                                            Idris2i_1_Value *idx);
Idris2i_1_Value *idris2i_1_refc_scheme_unbox(Idris2i_1_Value *obj);
Idris2i_1_Value *idris2i_1_refc_scheme_vector_length(Idris2i_1_Value *obj);
Idris2i_1_Value *idris2i_1_refc_scheme_vector_list(Idris2i_1_Value *obj);
Idris2i_1_Value *idris2i_1_refc_scheme_make_symbol(Idris2i_1_Value *name);
Idris2i_1_Value *idris2i_1_refc_scheme_read_symbol(Idris2i_1_Value *obj);

/* There is no tracing collector to run: memory is reference counted. */
void idris2i_1_refc_gc(int64_t generation);
