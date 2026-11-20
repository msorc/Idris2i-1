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
// Copy `len` elements of an array from `srcPos` to another (or the same)
// from `dstPos`, as Data.IOArray.Prims.prim__arrayCopy: the ranges are in
// bounds, and may overlap.  The copied elements get a reference each, and
// the overwritten ones lose theirs.
void idris2_arrayCopy(Idris2_Value *erased, Idris2_Value *src, int64_t srcPos,
                      Idris2_Value *dst, int64_t dstPos, int64_t len);
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

// The arrays of the slots of an `IOArray` (`Maybe` of the elements) with a
// layout (see Data.IOArray.Flat and Data.IOArray.Prims): with the layout of
// values (0) they are the arrays above; otherwise each slot is a word that is
// 1 when the slot holds an element, then the element inline: a primitive (8
// bytes: a double, or an integer widened to 64 bits), or the raw fields of a
// record of one constructor (8 bytes each, as in its cell, see
// idris2_newRawConstructor).  The layout is the one that the caller expects:
// the array's own one decides, so any code reads and writes any array
// correctly; when they are the same constant, the access is inline.
#define IDRIS2_LAYOUT_KIND(l) ((unsigned)((l) & 0xff))
#define IDRIS2_LAYOUT_PRIM(l) ((unsigned)(((l) >> 8) & 0xff))
#define IDRIS2_LAYOUT_FIELDS(l) ((size_t)(((l) >> 8) & 0xffff))
#define IDRIS2_LAYOUT_TAG(l) ((int)(((l) >> 24) & 0xffff))
#define IDRIS2_SLOT_SIZE(l)                                                    \
  (8 + (IDRIS2_LAYOUT_KIND(l) == 1 ? 8 : 8 * IDRIS2_LAYOUT_FIELDS(l)))
// (the program is compiled with --directive refc-no-raw-fields: a record has
// no raw fields, and its arrays have the layout of values)
#define idris2_noRawLayout(l) (IDRIS2_LAYOUT_KIND(l) == 2 ? 0 : (l))

Idris2_Value *idris2_newSlots(uint64_t layout, int64_t length, Idris2_Value *v);
Idris2_Value *idris2_slotGetGeneric(Idris2_Array *a, int64_t i);
void idris2_slotSetGeneric(Idris2_Array *a, int64_t i, Idris2_Value *v);

// The element of the slot `slot` of the layout `l`, a new value.
static inline Idris2_Value *idris2_loadSlot(uint64_t l, unsigned char *slot) {
  if (!*(uint64_t *)slot)
    return NULL; // (Nothing)
  unsigned char *p = slot + 8;
  Idris2_Value *x;
  if (IDRIS2_LAYOUT_KIND(l) == 2) {
    size_t n = IDRIS2_LAYOUT_FIELDS(l);
    Idris2_Constructor *c =
        idris2_newRawConstructor(0, (int)n, IDRIS2_LAYOUT_TAG(l));
    memcpy((char *)c + IDRIS2_RAW_OFFSET(0), p, 8 * n);
    x = (Idris2_Value *)c;
  } else {
    switch (IDRIS2_LAYOUT_PRIM(l)) {
    case 1: x = idris2_mkDouble(*(double *)p); break;
    case 2: x = idris2_mkInt64(*(int64_t *)p); break;
    case 3: x = idris2_mkBits64(*(uint64_t *)p); break;
    case 4: x = idris2_mkInt8((int8_t)*(int64_t *)p); break;
    case 5: x = idris2_mkInt16((int16_t)*(int64_t *)p); break;
    case 6: x = idris2_mkInt32((int32_t)*(int64_t *)p); break;
    case 7: x = idris2_mkBits8((uint8_t)*(uint64_t *)p); break;
    case 8: x = idris2_mkBits16((uint16_t)*(uint64_t *)p); break;
    case 9: x = idris2_mkBits32((uint32_t)*(uint64_t *)p); break;
    default: x = idris2_mkChar((uint32_t)*(uint64_t *)p); break;
    }
  }
  Idris2_Constructor *just = idris2_newConstructor(1, 1);
  just->args[0] = x;
  return (Idris2_Value *)just;
}

// Store the slot value `v` (`Maybe` of an element, borrowed) in `slot`.
static inline void idris2_storeSlot(uint64_t l, unsigned char *slot,
                                    Idris2_Value *v) {
  if (!v) {
    *(uint64_t *)slot = 0;
    return;
  }
  *(uint64_t *)slot = 1;
  unsigned char *p = slot + 8;
  Idris2_Value *x = ((Idris2_Constructor *)v)->args[0];
  if (IDRIS2_LAYOUT_KIND(l) == 2) {
    memcpy(p, (char *)x + IDRIS2_RAW_OFFSET(0), 8 * IDRIS2_LAYOUT_FIELDS(l));
    return;
  }
  switch (IDRIS2_LAYOUT_PRIM(l)) {
  case 1: *(double *)p = idris2_vp_to_Double(x); break;
  case 2: *(int64_t *)p = idris2_vp_to_Int64(x); break;
  case 3: *(uint64_t *)p = idris2_vp_to_Bits64(x); break;
  case 4: *(int64_t *)p = idris2_vp_to_Int8(x); break;
  case 5: *(int64_t *)p = idris2_vp_to_Int16(x); break;
  case 6: *(int64_t *)p = idris2_vp_to_Int32(x); break;
  case 7: *(uint64_t *)p = idris2_vp_to_Bits8(x); break;
  case 8: *(uint64_t *)p = idris2_vp_to_Bits16(x); break;
  case 9: *(uint64_t *)p = idris2_vp_to_Bits32(x); break;
  default: *(uint64_t *)p = idris2_vp_to_Char(x); break;
  }
}

// The accesses that the RefC back end makes of the elements of flat arrays
// (see Compiler.RefC.FlatOpt): an element read is its presence and its
// fields, as words (8 bytes: a double, an int64_t or a uint64_t), and an
// element written is written from its fields or from its value, without a
// value for the `Maybe`.  Inline when the array has the layout that the
// caller expects and is not shared, through values otherwise.
static inline unsigned char *idris2_slotFast(uint64_t l, Idris2_Value *array,
                                             int64_t i) {
  Idris2_Array *a = (Idris2_Array *)array;
  if (l != 0 && __builtin_expect(a->layout == l && !idris2_isShared(array), 1))
    return (unsigned char *)a->arr + (size_t)i * IDRIS2_SLOT_SIZE(l);
  return NULL;
}
static inline double idris2_wordToDouble(uint64_t w) {
  double d;
  memcpy(&d, &w, sizeof d);
  return d;
}
static inline uint64_t idris2_doubleToWord(double d) {
  uint64_t w;
  memcpy(&w, &d, sizeof w);
  return w;
}
int64_t idris2_slotPresentGeneric(Idris2_Value *array, int64_t i);
uint64_t idris2_slotWordGeneric(uint64_t l, Idris2_Value *array, int64_t i,
                                int j);
void idris2_slotStoreWordsGeneric(uint64_t l, Idris2_Value *array, int64_t i,
                                  const uint64_t *w);
void idris2_slotStoreElemGeneric(uint64_t l, Idris2_Value *array, int64_t i,
                                 Idris2_Value *x);

static inline int64_t idris2_slotPresent(uint64_t l, Idris2_Value *array,
                                         int64_t i) {
  unsigned char *s = idris2_slotFast(l, array, i);
  if (s)
    return *(uint64_t *)s != 0;
  return idris2_slotPresentGeneric(array, i);
}
static inline uint64_t idris2_slotWord(uint64_t l, Idris2_Value *array,
                                       int64_t i, int j) {
  unsigned char *s = idris2_slotFast(l, array, i);
  if (s)
    return *(uint64_t *)(s + 8 + 8 * (size_t)j);
  return idris2_slotWordGeneric(l, array, i, j);
}
static inline void idris2_slotStoreWords(uint64_t l, Idris2_Value *array,
                                         int64_t i, const uint64_t *w) {
  unsigned char *s = idris2_slotFast(l, array, i);
  if (s) {
    *(uint64_t *)s = 1;
    memcpy(s + 8, w, IDRIS2_SLOT_SIZE(l) - 8);
    return;
  }
  idris2_slotStoreWordsGeneric(l, array, i, w);
}
// (the element `x`, a record of raw fields or a primitive, is borrowed)
static inline void idris2_slotStoreElem(uint64_t l, Idris2_Value *array,
                                        int64_t i, Idris2_Value *x) {
  unsigned char *s = idris2_slotFast(l, array, i);
  if (s && IDRIS2_LAYOUT_KIND(l) == 2) {
    *(uint64_t *)s = 1;
    memcpy(s + 8, (char *)x + IDRIS2_RAW_OFFSET(0), IDRIS2_SLOT_SIZE(l) - 8);
    return;
  }
  idris2_slotStoreElemGeneric(l, array, i, x);
}

static inline Idris2_Value *idris2_slotGet(uint64_t expected,
                                           Idris2_Value *array, int64_t i) {
  Idris2_Array *a = (Idris2_Array *)array;
  if (expected != 0 &&
      __builtin_expect(a->layout == expected && !idris2_isShared(array), 1))
    return idris2_loadSlot(expected, (unsigned char *)a->arr +
                                         (size_t)i * IDRIS2_SLOT_SIZE(expected));
  if (a->layout == 0)
    return idris2_arrayGet(array, i);
  return idris2_slotGetGeneric(a, i);
}

static inline void idris2_slotSet(uint64_t expected, Idris2_Value *array,
                                  int64_t i, Idris2_Value *v) {
  Idris2_Array *a = (Idris2_Array *)array;
  if (expected != 0 &&
      __builtin_expect(a->layout == expected && !idris2_isShared(array), 1)) {
    idris2_storeSlot(expected,
                     (unsigned char *)a->arr + (size_t)i * IDRIS2_SLOT_SIZE(expected),
                     v);
    return;
  }
  idris2_slotSetGeneric(a, i, v);
}

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
