#include "prim.h"
#include "crash.h"
#include "refc_util.h"
#include <inttypes.h>
#include <limits.h>
#include <string.h>
#include <unistd.h>

Idris2i_1_Value *idris2i_1_Data_IORef_prim__newIORef(Idris2i_1_Value *erased,
                                               Idris2i_1_Value *input_value,
                                               Idris2i_1_Value *_world) {
  Idris2i_1_IORef *ioRef = IDRIS2I_1_NEW_VALUE(Idris2i_1_IORef);
  ioRef->header.tag = IOREF_TAG;
  ioRef->lock = 0;
  ioRef->v = idris2i_1_newReference(input_value);
  return (Idris2i_1_Value *)ioRef;
}

Idris2i_1_Value *idris2i_1_readSharedIORef(Idris2i_1_IORef *ioref) {
  idris2i_1_spinLock(&ioref->lock);
  Idris2i_1_Value *v = idris2i_1_newReference(ioref->v);
  idris2i_1_spinUnlock(&ioref->lock);
  return v;
}

Idris2i_1_Value *idris2i_1_Data_IORef_prim__writeIORef(Idris2i_1_Value *erased,
                                                 Idris2i_1_Value *_ioref,
                                                 Idris2i_1_Value *new_value,
                                                 Idris2i_1_Value *_world) {
  Idris2i_1_IORef *ioref = (Idris2i_1_IORef *)_ioref;
  idris2i_1_newReference(new_value);
  Idris2i_1_Value *old;
  if (idris2i_1_isShared(_ioref)) {
    // Other threads see the value from now on.
    idris2i_1_markShared(new_value);
    idris2i_1_spinLock(&ioref->lock);
    old = ioref->v;
    ioref->v = new_value;
    idris2i_1_spinUnlock(&ioref->lock);
  } else {
    old = ioref->v;
    ioref->v = new_value;
  }
  idris2i_1_removeReference(old);
  return NULL;
}

// -----------------------------------
//       System operations
// -----------------------------------

// The names are the ones of the Scheme backends (blodwen-os in support.ss).
#if defined(_WIN32) || defined(_WIN64)
#define IDRIS2I_1_OS_NAME "windows"
#elif defined(__APPLE__) || defined(__MACH__)
#define IDRIS2I_1_OS_NAME "darwin"
#elif defined(__linux__) || defined(__FreeBSD__) || defined(__OpenBSD__) ||    \
    defined(__NetBSD__) || defined(__DragonFly__) || defined(__unix) ||        \
    defined(__unix__)
#define IDRIS2I_1_OS_NAME "unix"
#else
#define IDRIS2I_1_OS_NAME "unknown"
#endif
Idris2i_1_ShortString const idris2i_1_predefined_osstring = {
    IDRIS2I_1_STOCKVAL(STRING_TAG), sizeof(IDRIS2I_1_OS_NAME),
    sizeof(IDRIS2I_1_OS_NAME) - 1, IDRIS2I_1_OS_NAME};

// NOTE: The codegen is obviously determined at compile time,
//       so the backend should optimize it by replacing it with a constant.
//       It would probably also be useful for conditional compilation.
Idris2i_1_ShortString const idris2i_1_predefined_codegenstring = {
    IDRIS2I_1_STOCKVAL(STRING_TAG), 5, 4, "refc"};

// Like blodwen-error-quit of the Scheme backends: the message goes to stdout,
// and the program exits with 1.  Inside a crash boundary (see crash.c), the
// boundary gets the message instead.  (The clause that the elaborator adds
// to a function that does not cover every input crashes with this too, with
// a message that says so.)
Idris2i_1_Value *idris2i_1_crash(Idris2i_1_Value *msg) {
  Idris2i_1_String *str = (Idris2i_1_String *)msg;
  if (idris2i_1_crashCatchable()) {
    static const char missing[] = "Unhandled input for ";
    int isMissing = str->len >= sizeof(missing) - 1 &&
                    memcmp(str->str, missing, sizeof(missing) - 1) == 0;
    idris2i_1_crashThrow(isMissing ? IDRIS2I_1_CRASH_MISSING_CASE : IDRIS2I_1_CRASH_CALL,
                      str->str, str->len);
  }
  fputs("ERROR: ", stdout);
  fwrite(str->str, 1, str->len, stdout);
  fputc('\n', stdout);
  fflush(stdout);
  idris2i_1_backtracePrint();
  exit(1);
}

// The message of a boundary, without the "ERROR: " that the messages of
// the crashes of the compiled code start with (that of idris_crash does not
// have it either).
static void idris2i_1_crashThrowMsg(int kind, const char *msg) {
  static const char prefix[] = "ERROR: ";
  if (strncmp(msg, prefix, sizeof(prefix) - 1) == 0)
    msg += sizeof(prefix) - 1;
  idris2i_1_crashThrow(kind, msg, strlen(msg));
}

#if defined(__GNUC__) || defined(__clang__)
__attribute__((__noreturn__))
#endif
static void idris2i_1_crashExit(const char *msg) {
  fputs(msg, stdout);
  fputc('\n', stdout);
  fflush(stdout);
  idris2i_1_backtracePrint();
  exit(1);
}

Idris2i_1_Value *idris2i_1_crashMsg(const char *msg) {
  if (idris2i_1_crashCatchable())
    idris2i_1_crashThrowMsg(IDRIS2I_1_CRASH_MISSING_CASE, msg);
  idris2i_1_crashExit(msg);
}

void idris2i_1_crashCheck(const char *msg) {
  if (idris2i_1_crashCatchable())
    idris2i_1_crashThrowMsg(IDRIS2I_1_CRASH_FAILED_CHECK, msg);
  idris2i_1_crashExit(msg);
}

// -----------------------------------
//         Array operations
// -----------------------------------

// The length of a new array, which its `capacity` (an int) holds: an array
// of more elements than that would be smaller than its length says, and one
// of a negative length is no array (Chez raises an exception for it).
static int arrayLength(int64_t length) {
  if (length < 0 || length > INT_MAX) {
    char msg[64];
    snprintf(msg, sizeof(msg), "ERROR: Invalid array length: %" PRId64,
             length);
    idris2i_1_crashCheck(msg);
  }
  return (int)length;
}

Idris2i_1_Value *idris2i_1_Data_IOArray_Prims_prim__newArray(Idris2i_1_Value *erased,
                                                       Idris2i_1_Value *_length,
                                                       Idris2i_1_Value *v,
                                                       Idris2i_1_Value *_word) {
  int length = arrayLength(idris2i_1_vp_to_Int64(_length));
  Idris2i_1_Array *a = idris2i_1_makeArray(length);

  // (calloc made the slots NULL: nothing to do for a NULL value)
  if (v != NULL) {
    for (int i = 0; i < length; i++) {
      a->arr[i] = idris2i_1_newReference(v);
    }
  }

  return (Idris2i_1_Value *)a;
}

Idris2i_1_Value *idris2i_1_Data_IOArray_Prims_prim__arraySet(Idris2i_1_Value *erased,
                                                       Idris2i_1_Value *_array,
                                                       Idris2i_1_Value *index,
                                                       Idris2i_1_Value *v,
                                                       Idris2i_1_Value *_word) {
  Idris2i_1_Array *a = (Idris2i_1_Array *)_array;
  int64_t i = idris2i_1_vp_to_Int64(index);
  idris2i_1_newReference(v);
  Idris2i_1_Value *old;
  if (idris2i_1_isShared(_array)) {
    idris2i_1_markShared(v);
    idris2i_1_spinLock(&a->lock);
    old = a->arr[i];
    a->arr[i] = v;
    idris2i_1_spinUnlock(&a->lock);
  } else {
    old = a->arr[i];
    a->arr[i] = v;
  }
  idris2i_1_removeReference(old);
  return NULL;
}

// The copy of a range when an array is shared, or when the ranges overlap in
// one array: the elements are taken into a temporary array (with a reference
// each) under the lock of `src`, then swapped with those of `dst` under its
// lock, and the old elements of `dst` are released after.  The two locks are
// never held at the same time, so that two copies between the same arrays in
// opposite directions cannot deadlock.
static void arrayCopySlow(Idris2i_1_Array *src, int64_t srcPos, Idris2i_1_Array *dst,
                          int64_t dstPos, int64_t len) {
  Idris2i_1_Value *small[16];
  Idris2i_1_Value **tmp = small;
  if (len > 16) {
    tmp = malloc(len * sizeof(Idris2i_1_Value *));
    IDRIS2I_1_REFC_VERIFY(tmp, "malloc failed");
  }
  int srcShared = idris2i_1_isShared((Idris2i_1_Value *)src);
  if (srcShared)
    idris2i_1_spinLock(&src->lock);
  for (int64_t i = 0; i < len; i++)
    tmp[i] = idris2i_1_newReference(src->arr[srcPos + i]);
  if (srcShared)
    idris2i_1_spinUnlock(&src->lock);
  int dstShared = idris2i_1_isShared((Idris2i_1_Value *)dst);
  if (dstShared) {
    for (int64_t i = 0; i < len; i++)
      idris2i_1_markShared(tmp[i]);
    idris2i_1_spinLock(&dst->lock);
  }
  for (int64_t i = 0; i < len; i++) {
    Idris2i_1_Value *old = dst->arr[dstPos + i];
    dst->arr[dstPos + i] = tmp[i];
    tmp[i] = old;
  }
  if (dstShared)
    idris2i_1_spinUnlock(&dst->lock);
  for (int64_t i = 0; i < len; i++)
    idris2i_1_removeReference(tmp[i]);
  if (tmp != small)
    free(tmp);
}

void idris2i_1_arrayCopy(Idris2i_1_Value *erased, Idris2i_1_Value *_src,
                      int64_t srcPos, Idris2i_1_Value *_dst, int64_t dstPos,
                      int64_t len) {
  Idris2i_1_Array *src = (Idris2i_1_Array *)_src;
  Idris2i_1_Array *dst = (Idris2i_1_Array *)_dst;
  if (len <= 0)
    return;
  if (src->layout != 0 || dst->layout != 0) {
    // Arrays with a layout: the slots are copied as bytes between arrays of
    // the same layout, through values otherwise (an array made by code that
    // is generic in the elements, copied to one that is not, say).
    if (src->layout == dst->layout && !idris2i_1_isShared(_src) &&
        !idris2i_1_isShared(_dst)) {
      size_t size = IDRIS2I_1_SLOT_SIZE(src->layout);
      memmove((unsigned char *)dst->arr + (size_t)dstPos * size,
              (unsigned char *)src->arr + (size_t)srcPos * size,
              (size_t)len * size);
      return;
    }
    // (in the order that copies an overlapping range right)
    int up = !(src == dst && srcPos < dstPos);
    for (int64_t k = 0; k < len; k++) {
      int64_t j = up ? k : len - 1 - k;
      Idris2i_1_Value *v = idris2i_1_slotGetGeneric(src, srcPos + j);
      idris2i_1_slotSetGeneric(dst, dstPos + j, v);
      idris2i_1_removeReference(v);
    }
    return;
  }
  if (__builtin_expect(idris2i_1_isShared(_src) || idris2i_1_isShared(_dst) ||
                           (src == dst && srcPos < dstPos + len &&
                            dstPos < srcPos + len),
                       0)) {
    arrayCopySlow(src, srcPos, dst, dstPos, len);
    return;
  }
  // Each slot of `dst` gets its new element before its old one is released:
  // releasing a value may run a finaliser, which sees the arrays in a
  // consistent state (the ranges are disjoint, so `src` is not changed).
  Idris2i_1_Value **from = src->arr + srcPos;
  Idris2i_1_Value **to = dst->arr + dstPos;
  for (int64_t i = 0; i < len; i++) {
    Idris2i_1_Value *old = to[i];
    to[i] = idris2i_1_newReference(from[i]);
    idris2i_1_removeReference(old);
  }
}

// The arrays of slots with a layout (see prim.h).

Idris2i_1_Value *idris2i_1_newSlots(uint64_t layout, int64_t length,
                              Idris2i_1_Value *v) {
  if (layout == 0)
    return idris2i_1_Data_IOArray_Prims_prim__newArray(
        NULL, idris2i_1_mkInt64(length), v, NULL);
  length = arrayLength(length);
  Idris2i_1_Array *a = IDRIS2I_1_NEW_VALUE(Idris2i_1_Array);
  a->header.tag = ARRAY_TAG;
  a->lock = 0;
  a->capacity = (int)length;
  a->layout = layout;
  size_t size = IDRIS2I_1_SLOT_SIZE(layout);
  a->arr = (Idris2i_1_Value **)calloc(length > 0 ? (size_t)length : 1, size);
  IDRIS2I_1_REFC_VERIFY(a->arr, "malloc failed");
  // (calloc made every slot empty)
  if (v != NULL)
    for (int64_t i = 0; i < length; i++)
      idris2i_1_storeSlot(layout, (unsigned char *)a->arr + (size_t)i * size, v);
  return (Idris2i_1_Value *)a;
}

// A slot of an array with a layout other than the one that the caller
// expected, or shared (its slots are read and written under its lock, as
// they are not words).
Idris2i_1_Value *idris2i_1_slotGetGeneric(Idris2i_1_Array *a, int64_t i) {
  if (a->layout == 0)
    return idris2i_1_arrayGet((Idris2i_1_Value *)a, i);
  unsigned char *slot =
      (unsigned char *)a->arr + (size_t)i * IDRIS2I_1_SLOT_SIZE(a->layout);
  if (!idris2i_1_isShared((Idris2i_1_Value *)a))
    return idris2i_1_loadSlot(a->layout, slot);
  size_t size = IDRIS2I_1_SLOT_SIZE(a->layout);
  unsigned char *copy = malloc(size);
  IDRIS2I_1_REFC_VERIFY(copy, "malloc failed");
  idris2i_1_spinLock(&a->lock);
  memcpy(copy, slot, size);
  idris2i_1_spinUnlock(&a->lock);
  Idris2i_1_Value *r = idris2i_1_loadSlot(a->layout, copy);
  free(copy);
  return r;
}

void idris2i_1_slotSetGeneric(Idris2i_1_Array *a, int64_t i, Idris2i_1_Value *v) {
  if (a->layout == 0) {
    idris2i_1_Data_IOArray_Prims_prim__arraySet(NULL, (Idris2i_1_Value *)a,
                                             idris2i_1_mkInt64(i), v, NULL);
    return;
  }
  size_t size = IDRIS2I_1_SLOT_SIZE(a->layout);
  unsigned char *slot = (unsigned char *)a->arr + (size_t)i * size;
  if (!idris2i_1_isShared((Idris2i_1_Value *)a)) {
    idris2i_1_storeSlot(a->layout, slot, v);
    return;
  }
  unsigned char *copy = malloc(size);
  IDRIS2I_1_REFC_VERIFY(copy, "malloc failed");
  idris2i_1_storeSlot(a->layout, copy, v);
  idris2i_1_spinLock(&a->lock);
  memcpy(slot, copy, size);
  idris2i_1_spinUnlock(&a->lock);
  free(copy);
}

// The accesses of prim.h through values.
static Idris2i_1_Value *slotValue(Idris2i_1_Value *array, int64_t i) {
  Idris2i_1_Array *a = (Idris2i_1_Array *)array;
  return a->layout == 0 ? idris2i_1_arrayGet(array, i) : idris2i_1_slotGetGeneric(a, i);
}

Idris2i_1_Value *idris2i_1_slotSnapGeneric(Idris2i_1_Value *array, int64_t i) {
  return slotValue(array, i);
}

// The word `j` of the element of a snapshot (the `Maybe` of a slot, see
// prim.h) of the layout `l` that the caller expects (the element is a record
// of raw fields, or a primitive).  (The snapshot is the caller's, released
// after its last use.)
uint64_t idris2i_1_slotWordOf(uint64_t l, Idris2i_1_Value *snap, int j) {
  if (!snap)
    return 0;
  Idris2i_1_Value *x = ((Idris2i_1_Constructor *)snap)->args[0];
  if (IDRIS2I_1_LAYOUT_KIND(l) == 2)
    return idris2i_1_rawField(x, 0, j, uint64_t);
  switch (IDRIS2I_1_LAYOUT_PRIM(l)) {
  case 1: return idris2i_1_doubleToWord(idris2i_1_vp_to_Double(x));
  case 3: return idris2i_1_vp_to_Bits64(x);
  default: return (uint64_t)idris2i_1_vp_to_Int64(x);
  }
}

// The element of the layout `l` (a record or a primitive) made from words.
static Idris2i_1_Value *elemOfWords(uint64_t l, const uint64_t *w) {
  if (IDRIS2I_1_LAYOUT_KIND(l) == 2) {
    size_t n = IDRIS2I_1_LAYOUT_FIELDS(l);
    Idris2i_1_Constructor *c =
        idris2i_1_newRawConstructor(0, (int)n, IDRIS2I_1_LAYOUT_TAG(l));
    memcpy((char *)c + IDRIS2I_1_RAW_OFFSET(0), w, 8 * n);
    return (Idris2i_1_Value *)c;
  }
  switch (IDRIS2I_1_LAYOUT_PRIM(l)) {
  case 1: return idris2i_1_mkDouble(idris2i_1_wordToDouble(w[0]));
  case 3: return idris2i_1_mkBits64(w[0]);
  default: return idris2i_1_mkInt64((int64_t)w[0]);
  }
}

static void storeJust(Idris2i_1_Value *array, int64_t i, Idris2i_1_Value *x) {
  Idris2i_1_Constructor *just = idris2i_1_newConstructor(1, 1);
  just->args[0] = x;
  idris2i_1_slotSetGeneric((Idris2i_1_Array *)array, i, (Idris2i_1_Value *)just);
  idris2i_1_removeReference((Idris2i_1_Value *)just);
}

void idris2i_1_slotStoreWordsGeneric(uint64_t l, Idris2i_1_Value *array, int64_t i,
                                  const uint64_t *w) {
  storeJust(array, i, elemOfWords(l, w));
}

void idris2i_1_slotStoreElemGeneric(uint64_t l, Idris2i_1_Value *array, int64_t i,
                                 Idris2i_1_Value *x) {
  (void)l;
  storeJust(array, i, idris2i_1_newReference(x));
}

Idris2i_1_Value *idris2i_1_sharedArrayGet(Idris2i_1_Array *a, int64_t i) {
  idris2i_1_spinLock(&a->lock);
  Idris2i_1_Value *v = idris2i_1_newReference(a->arr[i]);
  idris2i_1_spinUnlock(&a->lock);
  return v;
}

//
// -----------------------------------
//      Pointer operations
// -----------------------------------

Idris2i_1_Value *idris2i_1_Prelude_IO_prim__onCollect(Idris2i_1_Value *_erased,
                                                Idris2i_1_Value *_anyPtr,
                                                Idris2i_1_Value *_freeingFunction,
                                                Idris2i_1_Value *_world) {
  Idris2i_1_GCPointer *retVal = IDRIS2I_1_NEW_VALUE(Idris2i_1_GCPointer);
  retVal->header.tag = GC_POINTER_TAG;
  retVal->p = (Idris2i_1_Pointer *)idris2i_1_newReference(_anyPtr);
  retVal->onCollectFct =
      (Idris2i_1_Closure *)idris2i_1_newReference(_freeingFunction);
  return (Idris2i_1_Value *)retVal;
}

Idris2i_1_Value *
idris2i_1_Prelude_IO_prim__onCollectAny(Idris2i_1_Value *_anyPtr,
                                     Idris2i_1_Value *_freeingFunction,
                                     Idris2i_1_Value *_world) {
  Idris2i_1_GCPointer *retVal = IDRIS2I_1_NEW_VALUE(Idris2i_1_GCPointer);
  retVal->header.tag = GC_POINTER_TAG;
  retVal->p = (Idris2i_1_Pointer *)idris2i_1_newReference(_anyPtr);
  retVal->onCollectFct =
      (Idris2i_1_Closure *)idris2i_1_newReference(_freeingFunction);
  return (Idris2i_1_Value *)retVal;
}

char const idris2i_1_constr_Int[] = "Int";
char const idris2i_1_constr_Int8[] = "Int8";
char const idris2i_1_constr_Int16[] = "Int16";
char const idris2i_1_constr_Int32[] = "Int32";
char const idris2i_1_constr_Int64[] = "Int64";
char const idris2i_1_constr_Bits8[] = "Bits8";
char const idris2i_1_constr_Bits16[] = "Bits16";
char const idris2i_1_constr_Bits32[] = "Bits32";
char const idris2i_1_constr_Bits64[] = "Bits64";
char const idris2i_1_constr_Double[] = "Double";
char const idris2i_1_constr_Integer[] = "Integer";
char const idris2i_1_constr_Char[] = "Char";
char const idris2i_1_constr_String[] = "String";
char const idris2i_1_constr____gt[] = "->";
