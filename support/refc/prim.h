#pragma once

#include "cBackend.h"

// IORef

Idris2_Value *idris2_Data_IORef_prim__newIORef(Idris2_Value *, Idris2_Value *,
                                               Idris2_Value *);
// A shared IORef (see memoryManagement.h) is read and written under its
// lock: otherwise a writer could release the old value between the read of
// the value and the new reference to it.
Idris2_Value *idris2_readSharedIORef(Idris2_IORef *ioref);
static inline Idris2_Value *idris2_readIORef(Idris2_Value *ioref) {
  Idris2_IORef *r = (Idris2_IORef *)ioref;
  if (__builtin_expect(idris2_isShared(ioref), 0))
    return idris2_readSharedIORef(r);
  return idris2_newReference(r->v);
}
#define idris2_Data_IORef_prim__readIORef(erased, ioref, world)                \
  (idris2_readIORef(ioref))

Idris2_Value *idris2_Data_IORef_prim__writeIORef(Idris2_Value *, Idris2_Value *,
                                                 Idris2_Value *,
                                                 Idris2_Value *);

// Sys

extern Idris2_ShortString const idris2_predefined_osstring;
extern Idris2_ShortString const idris2_predefined_codegenstring;
#define idris2_System_Info_prim__os()                                          \
  ((Idris2_Value *)&idris2_predefined_osstring)
#define idris2_System_Info_prim__codegen()                                     \
  ((Idris2_Value *)&idris2_predefined_codegenstring)
// `idris_crash`: print the message and stop.  (Like idris2_crashMsg, it does
// not return, which also keeps the C compiler from making its call a jump,
// so that the frame of the caller is in the backtrace.)
#if defined(__GNUC__) || defined(__clang__)
__attribute__((noreturn, cold))
#endif
Idris2_Value *idris2_crash(Idris2_Value *msg);
// A crash of the compiled code itself (a case without a clause for the value,
// a hole): print the message and stop, like the Scheme backends.  It has a
// result type to be used as an expression, but it does not return.
#if defined(__GNUC__) || defined(__clang__)
__attribute__((noreturn, cold))
#endif
Idris2_Value *idris2_crashMsg(const char *msg);

// Array

Idris2_Value *idris2_Data_IOArray_Prims_prim__newArray(Idris2_Value *,
                                                       Idris2_Value *,
                                                       Idris2_Value *,
                                                       Idris2_Value *);
Idris2_Value *idris2_sharedArrayGet(Idris2_Array *array, int64_t i);
static inline Idris2_Value *idris2_arrayGet(Idris2_Value *array, int64_t i) {
  Idris2_Array *a = (Idris2_Array *)array;
  if (__builtin_expect(idris2_isShared(array), 0))
    return idris2_sharedArrayGet(a, i);
  return idris2_newReference(a->arr[i]);
}
#define idris2_Data_IOArray_Prims_prim__arrayGet(rased, array, i, word)        \
  (idris2_arrayGet((array), idris2_vp_to_Int64(i)))
Idris2_Value *idris2_Data_IOArray_Prims_prim__arraySet(Idris2_Value *,
                                                       Idris2_Value *,
                                                       Idris2_Value *,
                                                       Idris2_Value *,
                                                       Idris2_Value *);

// Pointer
Idris2_Value *idris2_Prelude_IO_prim__onCollect(Idris2_Value *, Idris2_Value *,
                                                Idris2_Value *, Idris2_Value *);
Idris2_Value *idris2_Prelude_IO_prim__onCollectAny(Idris2_Value *,
                                                   Idris2_Value *,
                                                   Idris2_Value *);

extern char const idris2_constr_Int[];
extern char const idris2_constr_Int8[];
extern char const idris2_constr_Int16[];
extern char const idris2_constr_Int32[];
extern char const idris2_constr_Int64[];
extern char const idris2_constr_Bits8[];
extern char const idris2_constr_Bits16[];
extern char const idris2_constr_Bits32[];
extern char const idris2_constr_Bits64[];
extern char const idris2_constr_Double[];
extern char const idris2_constr_Integer[];
extern char const idris2_constr_Char[];
extern char const idris2_constr_String[];
extern char const idris2_constr____gt[];
