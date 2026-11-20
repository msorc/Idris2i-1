#include "prim.h"
#include "refc_util.h"
#include <string.h>
#include <unistd.h>

Idris2_Value *idris2_Data_IORef_prim__newIORef(Idris2_Value *erased,
                                               Idris2_Value *input_value,
                                               Idris2_Value *_world) {
  Idris2_IORef *ioRef = IDRIS2_NEW_VALUE(Idris2_IORef);
  ioRef->header.tag = IOREF_TAG;
  ioRef->lock = 0;
  ioRef->v = idris2_newReference(input_value);
  return (Idris2_Value *)ioRef;
}

Idris2_Value *idris2_readSharedIORef(Idris2_IORef *ioref) {
  idris2_spinLock(&ioref->lock);
  Idris2_Value *v = idris2_newReference(ioref->v);
  idris2_spinUnlock(&ioref->lock);
  return v;
}

Idris2_Value *idris2_Data_IORef_prim__writeIORef(Idris2_Value *erased,
                                                 Idris2_Value *_ioref,
                                                 Idris2_Value *new_value,
                                                 Idris2_Value *_world) {
  Idris2_IORef *ioref = (Idris2_IORef *)_ioref;
  idris2_newReference(new_value);
  Idris2_Value *old;
  if (idris2_isShared(_ioref)) {
    // Other threads see the value from now on.
    idris2_markShared(new_value);
    idris2_spinLock(&ioref->lock);
    old = ioref->v;
    ioref->v = new_value;
    idris2_spinUnlock(&ioref->lock);
  } else {
    old = ioref->v;
    ioref->v = new_value;
  }
  idris2_removeReference(old);
  return NULL;
}

// -----------------------------------
//       System operations
// -----------------------------------

// The names are the ones of the Scheme backends (blodwen-os in support.ss).
#if defined(_WIN32) || defined(_WIN64)
#define IDRIS2_OS_NAME "windows"
#elif defined(__APPLE__) || defined(__MACH__)
#define IDRIS2_OS_NAME "darwin"
#elif defined(__linux__) || defined(__FreeBSD__) || defined(__OpenBSD__) ||    \
    defined(__NetBSD__) || defined(__DragonFly__) || defined(__unix) ||        \
    defined(__unix__)
#define IDRIS2_OS_NAME "unix"
#else
#define IDRIS2_OS_NAME "unknown"
#endif
Idris2_ShortString const idris2_predefined_osstring = {
    IDRIS2_STOCKVAL(STRING_TAG), sizeof(IDRIS2_OS_NAME),
    sizeof(IDRIS2_OS_NAME) - 1, IDRIS2_OS_NAME};

// NOTE: The codegen is obviously determined at compile time,
//       so the backend should optimize it by replacing it with a constant.
//       It would probably also be useful for conditional compilation.
Idris2_ShortString const idris2_predefined_codegenstring = {
    IDRIS2_STOCKVAL(STRING_TAG), 5, 4, "refc"};

// Like blodwen-error-quit of the Scheme backends: the message goes to stdout,
// and the program exits with 1.
Idris2_Value *idris2_crash(Idris2_Value *msg) {
  Idris2_String *str = (Idris2_String *)msg;
  fputs("ERROR: ", stdout);
  fwrite(str->str, 1, str->len, stdout);
  fputc('\n', stdout);
  fflush(stdout);
  idris2_backtracePrint();
  exit(1);
}

Idris2_Value *idris2_crashMsg(const char *msg) {
  fputs(msg, stdout);
  fputc('\n', stdout);
  fflush(stdout);
  idris2_backtracePrint();
  exit(1);
}

// -----------------------------------
//         Array operations
// -----------------------------------

Idris2_Value *idris2_Data_IOArray_Prims_prim__newArray(Idris2_Value *erased,
                                                       Idris2_Value *_length,
                                                       Idris2_Value *v,
                                                       Idris2_Value *_word) {
  int length = idris2_vp_to_Int64(_length);
  Idris2_Array *a = idris2_makeArray(length);

  // (calloc made the slots NULL: nothing to do for a NULL value)
  if (v != NULL) {
    for (int i = 0; i < length; i++) {
      a->arr[i] = idris2_newReference(v);
    }
  }

  return (Idris2_Value *)a;
}

Idris2_Value *idris2_Data_IOArray_Prims_prim__arraySet(Idris2_Value *erased,
                                                       Idris2_Value *_array,
                                                       Idris2_Value *index,
                                                       Idris2_Value *v,
                                                       Idris2_Value *_word) {
  Idris2_Array *a = (Idris2_Array *)_array;
  int64_t i = idris2_vp_to_Int64(index);
  if (a->layout != 0) {
    idris2_slotSetGeneric(a, i, v);
    return NULL;
  }
  idris2_newReference(v);
  Idris2_Value *old;
  if (idris2_isShared(_array)) {
    idris2_markShared(v);
    idris2_spinLock(&a->lock);
    old = a->arr[i];
    a->arr[i] = v;
    idris2_spinUnlock(&a->lock);
  } else {
    old = a->arr[i];
    a->arr[i] = v;
  }
  idris2_removeReference(old);
  return NULL;
}

// The copy of a range when an array is shared, or when the ranges overlap in
// one array: the elements are taken into a temporary array (with a reference
// each) under the lock of `src`, then swapped with those of `dst` under its
// lock, and the old elements of `dst` are released after.  The two locks are
// never held at the same time, so that two copies between the same arrays in
// opposite directions cannot deadlock.
static void arrayCopySlow(Idris2_Array *src, int64_t srcPos, Idris2_Array *dst,
                          int64_t dstPos, int64_t len) {
  Idris2_Value *small[16];
  Idris2_Value **tmp = small;
  if (len > 16) {
    tmp = malloc(len * sizeof(Idris2_Value *));
    IDRIS2_REFC_VERIFY(tmp, "malloc failed");
  }
  int srcShared = idris2_isShared((Idris2_Value *)src);
  if (srcShared)
    idris2_spinLock(&src->lock);
  for (int64_t i = 0; i < len; i++)
    tmp[i] = idris2_newReference(src->arr[srcPos + i]);
  if (srcShared)
    idris2_spinUnlock(&src->lock);
  int dstShared = idris2_isShared((Idris2_Value *)dst);
  if (dstShared) {
    for (int64_t i = 0; i < len; i++)
      idris2_markShared(tmp[i]);
    idris2_spinLock(&dst->lock);
  }
  for (int64_t i = 0; i < len; i++) {
    Idris2_Value *old = dst->arr[dstPos + i];
    dst->arr[dstPos + i] = tmp[i];
    tmp[i] = old;
  }
  if (dstShared)
    idris2_spinUnlock(&dst->lock);
  for (int64_t i = 0; i < len; i++)
    idris2_removeReference(tmp[i]);
  if (tmp != small)
    free(tmp);
}

void idris2_arrayCopy(Idris2_Value *erased, Idris2_Value *_src,
                      int64_t srcPos, Idris2_Value *_dst, int64_t dstPos,
                      int64_t len) {
  Idris2_Array *src = (Idris2_Array *)_src;
  Idris2_Array *dst = (Idris2_Array *)_dst;
  if (len <= 0)
    return;
  if (src->layout != 0 || dst->layout != 0) {
    // Arrays with a layout: the slots are copied as bytes between arrays of
    // the same layout, through values otherwise (an array made by code that
    // is generic in the elements, copied to one that is not, say).
    if (src->layout == dst->layout && !idris2_isShared(_src) &&
        !idris2_isShared(_dst)) {
      size_t size = IDRIS2_SLOT_SIZE(src->layout);
      memmove((unsigned char *)dst->arr + (size_t)dstPos * size,
              (unsigned char *)src->arr + (size_t)srcPos * size,
              (size_t)len * size);
      return;
    }
    // (in the order that copies an overlapping range right)
    int up = !(src == dst && srcPos < dstPos);
    for (int64_t k = 0; k < len; k++) {
      int64_t j = up ? k : len - 1 - k;
      Idris2_Value *v = idris2_slotGetGeneric(src, srcPos + j);
      idris2_slotSetGeneric(dst, dstPos + j, v);
      idris2_removeReference(v);
    }
    return;
  }
  if (__builtin_expect(idris2_isShared(_src) || idris2_isShared(_dst) ||
                           (src == dst && srcPos < dstPos + len &&
                            dstPos < srcPos + len),
                       0)) {
    arrayCopySlow(src, srcPos, dst, dstPos, len);
    return;
  }
  // Each slot of `dst` gets its new element before its old one is released:
  // releasing a value may run a finaliser, which sees the arrays in a
  // consistent state (the ranges are disjoint, so `src` is not changed).
  Idris2_Value **from = src->arr + srcPos;
  Idris2_Value **to = dst->arr + dstPos;
  for (int64_t i = 0; i < len; i++) {
    Idris2_Value *old = to[i];
    to[i] = idris2_newReference(from[i]);
    idris2_removeReference(old);
  }
}

// The arrays of slots with a layout (see prim.h).

Idris2_Value *idris2_newSlots(uint64_t layout, int64_t length,
                              Idris2_Value *v) {
  if (layout == 0)
    return idris2_Data_IOArray_Prims_prim__newArray(
        NULL, idris2_mkInt64(length), v, NULL);
  Idris2_Array *a = IDRIS2_NEW_VALUE(Idris2_Array);
  a->header.tag = ARRAY_TAG;
  a->lock = 0;
  a->capacity = (int)length;
  a->layout = layout;
  size_t size = IDRIS2_SLOT_SIZE(layout);
  a->arr = (Idris2_Value **)calloc(length > 0 ? (size_t)length : 1, size);
  IDRIS2_REFC_VERIFY(a->arr, "malloc failed");
  // (calloc made every slot empty)
  if (v != NULL)
    for (int64_t i = 0; i < length; i++)
      idris2_storeSlot(layout, (unsigned char *)a->arr + (size_t)i * size, v);
  return (Idris2_Value *)a;
}

// A slot of an array with a layout other than the one that the caller
// expected, or shared (its slots are read and written under its lock, as
// they are not words).
Idris2_Value *idris2_slotGetGeneric(Idris2_Array *a, int64_t i) {
  if (a->layout == 0)
    return idris2_arrayGet((Idris2_Value *)a, i);
  unsigned char *slot =
      (unsigned char *)a->arr + (size_t)i * IDRIS2_SLOT_SIZE(a->layout);
  if (!idris2_isShared((Idris2_Value *)a))
    return idris2_loadSlot(a->layout, slot);
  size_t size = IDRIS2_SLOT_SIZE(a->layout);
  unsigned char *copy = malloc(size);
  IDRIS2_REFC_VERIFY(copy, "malloc failed");
  idris2_spinLock(&a->lock);
  memcpy(copy, slot, size);
  idris2_spinUnlock(&a->lock);
  Idris2_Value *r = idris2_loadSlot(a->layout, copy);
  free(copy);
  return r;
}

void idris2_slotSetGeneric(Idris2_Array *a, int64_t i, Idris2_Value *v) {
  if (a->layout == 0) {
    idris2_Data_IOArray_Prims_prim__arraySet(NULL, (Idris2_Value *)a,
                                             idris2_mkInt64(i), v, NULL);
    return;
  }
  size_t size = IDRIS2_SLOT_SIZE(a->layout);
  unsigned char *slot = (unsigned char *)a->arr + (size_t)i * size;
  if (!idris2_isShared((Idris2_Value *)a)) {
    idris2_storeSlot(a->layout, slot, v);
    return;
  }
  unsigned char *copy = malloc(size);
  IDRIS2_REFC_VERIFY(copy, "malloc failed");
  idris2_storeSlot(a->layout, copy, v);
  idris2_spinLock(&a->lock);
  memcpy(slot, copy, size);
  idris2_spinUnlock(&a->lock);
  free(copy);
}

// The accesses of prim.h through values.
static Idris2_Value *slotValue(Idris2_Value *array, int64_t i) {
  Idris2_Array *a = (Idris2_Array *)array;
  return a->layout == 0 ? idris2_arrayGet(array, i) : idris2_slotGetGeneric(a, i);
}

Idris2_Value *idris2_slotSnapGeneric(Idris2_Value *array, int64_t i) {
  return slotValue(array, i);
}

// The word `j` of the element of a snapshot (the `Maybe` of a slot, see
// prim.h) of the layout `l` that the caller expects (the element is a record
// of raw fields, or a primitive).  (The snapshot is the caller's, released
// after its last use.)
uint64_t idris2_slotWordOf(uint64_t l, Idris2_Value *snap, int j) {
  if (!snap)
    return 0;
  Idris2_Value *x = ((Idris2_Constructor *)snap)->args[0];
  if (IDRIS2_LAYOUT_KIND(l) == 2)
    return idris2_rawField(x, 0, j, uint64_t);
  switch (IDRIS2_LAYOUT_PRIM(l)) {
  case 1: return idris2_doubleToWord(idris2_vp_to_Double(x));
  case 3: return idris2_vp_to_Bits64(x);
  default: return (uint64_t)idris2_vp_to_Int64(x);
  }
}

// The element of the layout `l` (a record or a primitive) made from words.
static Idris2_Value *elemOfWords(uint64_t l, const uint64_t *w) {
  if (IDRIS2_LAYOUT_KIND(l) == 2) {
    size_t n = IDRIS2_LAYOUT_FIELDS(l);
    Idris2_Constructor *c =
        idris2_newRawConstructor(0, (int)n, IDRIS2_LAYOUT_TAG(l));
    memcpy((char *)c + IDRIS2_RAW_OFFSET(0), w, 8 * n);
    return (Idris2_Value *)c;
  }
  switch (IDRIS2_LAYOUT_PRIM(l)) {
  case 1: return idris2_mkDouble(idris2_wordToDouble(w[0]));
  case 3: return idris2_mkBits64(w[0]);
  default: return idris2_mkInt64((int64_t)w[0]);
  }
}

static void storeJust(Idris2_Value *array, int64_t i, Idris2_Value *x) {
  Idris2_Constructor *just = idris2_newConstructor(1, 1);
  just->args[0] = x;
  idris2_slotSetGeneric((Idris2_Array *)array, i, (Idris2_Value *)just);
  idris2_removeReference((Idris2_Value *)just);
}

void idris2_slotStoreWordsGeneric(uint64_t l, Idris2_Value *array, int64_t i,
                                  const uint64_t *w) {
  storeJust(array, i, elemOfWords(l, w));
}

void idris2_slotStoreElemGeneric(uint64_t l, Idris2_Value *array, int64_t i,
                                 Idris2_Value *x) {
  (void)l;
  storeJust(array, i, idris2_newReference(x));
}

Idris2_Value *idris2_sharedArrayGet(Idris2_Array *a, int64_t i) {
  idris2_spinLock(&a->lock);
  Idris2_Value *v = idris2_newReference(a->arr[i]);
  idris2_spinUnlock(&a->lock);
  return v;
}

//
// -----------------------------------
//      Pointer operations
// -----------------------------------

Idris2_Value *idris2_Prelude_IO_prim__onCollect(Idris2_Value *_erased,
                                                Idris2_Value *_anyPtr,
                                                Idris2_Value *_freeingFunction,
                                                Idris2_Value *_world) {
  Idris2_GCPointer *retVal = IDRIS2_NEW_VALUE(Idris2_GCPointer);
  retVal->header.tag = GC_POINTER_TAG;
  retVal->p = (Idris2_Pointer *)idris2_newReference(_anyPtr);
  retVal->onCollectFct =
      (Idris2_Closure *)idris2_newReference(_freeingFunction);
  return (Idris2_Value *)retVal;
}

Idris2_Value *
idris2_Prelude_IO_prim__onCollectAny(Idris2_Value *_anyPtr,
                                     Idris2_Value *_freeingFunction,
                                     Idris2_Value *_world) {
  Idris2_GCPointer *retVal = IDRIS2_NEW_VALUE(Idris2_GCPointer);
  retVal->header.tag = GC_POINTER_TAG;
  retVal->p = (Idris2_Pointer *)idris2_newReference(_anyPtr);
  retVal->onCollectFct =
      (Idris2_Closure *)idris2_newReference(_freeingFunction);
  return (Idris2_Value *)retVal;
}

char const idris2_constr_Int[] = "Int";
char const idris2_constr_Int8[] = "Int8";
char const idris2_constr_Int16[] = "Int16";
char const idris2_constr_Int32[] = "Int32";
char const idris2_constr_Int64[] = "Int64";
char const idris2_constr_Bits8[] = "Bits8";
char const idris2_constr_Bits16[] = "Bits16";
char const idris2_constr_Bits32[] = "Bits32";
char const idris2_constr_Bits64[] = "Bits64";
char const idris2_constr_Double[] = "Double";
char const idris2_constr_Integer[] = "Integer";
char const idris2_constr_Char[] = "Char";
char const idris2_constr_String[] = "String";
char const idris2_constr____gt[] = "->";
