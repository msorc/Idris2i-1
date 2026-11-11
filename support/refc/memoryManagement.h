#pragma once

#include "cBackend.h"

// Allocation of values: see the description in memoryManagement.c.  The
// common case is inlined.
#define IDRIS2_ALLOC_UNIT 8
#define IDRIS2_ALLOC_CLASSES 32 /* values of up to 256 bytes */
#define IDRIS2_PAGE_SIZE ((size_t)64 * 1024)

typedef struct Idris2_FreeValue {
  struct Idris2_FreeValue *next;
} Idris2_FreeValue;

typedef struct Idris2_Page {
  Idris2_FreeValue *free; // freed values of this page
  char *bump;             // the values after this one were never allocated
  char *end;
  struct Idris2_Page *nextAvailable; // in the available list of the class
  int available;                     // in that list, or the current page
} Idris2_Page;

typedef struct {
  Idris2_Page *current;   // the page that the class allocates from
  Idris2_Page *available; // pages with free values, besides the current one
} Idris2_SizeClass;

extern Idris2_SizeClass idris2_classes[IDRIS2_ALLOC_CLASSES + 1];

// The current page of the class is full: move on to another one.
Idris2_Value *idris2_allocSlow(unsigned cls);
// A value that is too large for the pages, from malloc.
Idris2_Value *idris2_allocLarge(size_t size);

// A new value of `size` bytes, with a reference count of 1.  Its payload is
// not initialised.
static inline Idris2_Value *idris2_newValue(size_t size) {
#ifndef IDRIS2_REFC_NO_POOLS
  unsigned cls = (unsigned)((size + IDRIS2_ALLOC_UNIT - 1) / IDRIS2_ALLOC_UNIT);
  if (cls <= IDRIS2_ALLOC_CLASSES) {
    if (cls == 0)
      cls = 1;
    Idris2_Value *retVal;
    Idris2_Page *page = idris2_classes[cls].current;
    Idris2_FreeValue *v;
    if (page && (v = page->free) != NULL) {
      page->free = v->next;
      retVal = (Idris2_Value *)v;
    } else if (page && page->bump < page->end) {
      retVal = (Idris2_Value *)page->bump;
      page->bump += (size_t)cls * IDRIS2_ALLOC_UNIT;
    } else {
      // Sets the header (its class may be 0, see memoryManagement.c).
      return idris2_allocSlow(cls);
    }
    retVal->header.reserved = (uint8_t)cls;
    retVal->header.refCounter = 1;
    retVal->header.tag = NO_TAG;
    return retVal;
  }
#endif
  return idris2_allocLarge(size);
}
// Give back the memory of a value (only: what it refers to is not released).
void idris2_freeValue(Idris2_Value *value);

// The memory returned by idris2_newValue is not initialised.  Use this to
// create a value whose payload is zeroed, without disturbing its header.
Idris2_Value *idris2_newZeroedValue(size_t size);

void idris2_releaseValue(Idris2_Value *elem);

// Take a reference.  NULL (an erased value), unboxed values and immortal
// values (the reference count of which reached its maximum, or statically
// allocated values) are left alone.
static inline Idris2_Value *idris2_newReference(Idris2_Value *source) {
  if (source && !idris2_vp_is_unboxed(source) &&
      source->header.refCounter != IDRIS2_VP_REFCOUNTER_MAX)
    ++source->header.refCounter;
  return source;
}

// Make a value immortal (it is never released), and give it back.
static inline Idris2_Value *idris2_makeImmortal(Idris2_Value *v) {
  // (static values are immortal already, and may be read only)
  if (v && !idris2_vp_is_unboxed(v) &&
      v->header.refCounter != IDRIS2_VP_REFCOUNTER_MAX)
    v->header.refCounter = IDRIS2_VP_REFCOUNTER_MAX;
  return v;
}

// Drop a reference to a value that has other references (but may be
// immortal).
static inline void idris2_dropSharedReference(Idris2_Value *v) {
  if (v->header.refCounter != IDRIS2_VP_REFCOUNTER_MAX)
    --v->header.refCounter;
}

// Drop a reference, releasing the value when it was the last one.
static inline void idris2_removeReference(Idris2_Value *elem) {
  if (!elem || idris2_vp_is_unboxed(elem) ||
      elem->header.refCounter == IDRIS2_VP_REFCOUNTER_MAX)
    return;
  if (elem->header.refCounter != 1)
    --elem->header.refCounter;
  else
    idris2_releaseValue(elem);
}

#define IDRIS2_NEW_VALUE(t) ((t *)idris2_newValue(sizeof(t)))

static inline Idris2_Constructor *idris2_newConstructor(int total, int tag) {
  Idris2_Constructor *retVal = (Idris2_Constructor *)idris2_newValue(
      sizeof(Idris2_Constructor) + sizeof(Idris2_Value *) * total);
  retVal->header.tag = CONSTRUCTOR_TAG;
  retVal->total = (uint16_t)total;
  retVal->tag = (int16_t)tag;
  return retVal;
}

// A constructor that is told apart by its name instead of a tag.
static inline Idris2_Constructor *
idris2_newNamedConstructor(int total, char const *name) {
  Idris2_Constructor *retVal = (Idris2_Constructor *)idris2_newValue(
      sizeof(Idris2_Constructor) + sizeof(Idris2_Value *) * (total + 1));
  retVal->header.tag = CONSTRUCTOR_TAG;
  retVal->total = (uint16_t)total;
  retVal->tag = -1;
  retVal->args[total] = (Idris2_Value *)name;
  return retVal;
}

// The caller must initialise args[0 .. filled-1].  There is room for every
// argument, so that applying a closure that nobody else refers to can store
// the argument in place (see idris2_tailcall_apply_closure).
static inline Idris2_Closure *idris2_mkClosure(Idris2_Value *(*f)(),
                                               uint8_t arity, uint8_t filled) {
  uint8_t room = arity > filled ? arity : filled;
  Idris2_Closure *retVal = (Idris2_Closure *)idris2_newValue(
      sizeof(Idris2_Closure) + sizeof(Idris2_Value *) * room);
  retVal->header.tag = CLOSURE_TAG;
  retVal->f = f;
  retVal->arity = arity;
  retVal->filled = filled;
  return retVal;
}

#define idris2_mkChar(x)                                                       \
  ((Idris2_Value *)(((uintptr_t)(x) << idris2_vp_int_shift) + 1))
#define idris2_mkBits8(x)                                                      \
  ((Idris2_Value *)(((uintptr_t)(x) << idris2_vp_int_shift) + 1))
#define idris2_mkBits16(x)                                                     \
  ((Idris2_Value *)(((uintptr_t)(x) << idris2_vp_int_shift) + 1))

#if !defined(UINTPTR_WIDTH)
#define idris2_mkBits32(x)                                                     \
  ((idris2_vp_int_shift == 16)                                                 \
       ? (idris2_mkBits32_Boxed(x))                                            \
       : ((Idris2_Value *)(((uintptr_t)(x) << idris2_vp_int_shift) + 1)))
#define idris2_mkInt32(x)                                                      \
  ((idris2_vp_int_shift == 16)                                                 \
       ? (idris2_mkInt32_Boxed(x))                                             \
       : ((Idris2_Value *)(((uintptr_t)(x) << idris2_vp_int_shift) + 1)))

#elif UINTPTR_WIDTH >= 64
#define idris2_mkBits32(x)                                                     \
  ((Idris2_Value *)(((uintptr_t)(x) << idris2_vp_int_shift) + 1))
#define idris2_mkInt32(x)                                                      \
  ((Idris2_Value *)(((uintptr_t)(x) << idris2_vp_int_shift) + 1))

#elif UINTPTR_WIDTH >= 32
#define idris2_mkBits32(x) (idris2_mkBits32_Boxed(x))
#define idris2_mkInt32(x) (idris2_mkInt32_Boxed(x)))

#else
#error "unsupported uintptr_t width"
#endif

#define idris2_mkInt8(x)                                                       \
  ((Idris2_Value *)(((uintptr_t)(x) << idris2_vp_int_shift) + 1))
#define idris2_mkInt16(x)                                                      \
  ((Idris2_Value *)(((uintptr_t)(x) << idris2_vp_int_shift) + 1))
#define idris2_mkBool(x) (idris2_mkInt8(x))

Idris2_Value *idris2_mkBits32_Boxed(uint32_t i);
Idris2_Value *idris2_mkInt32_Boxed(int32_t i);

Idris2_Integer *idris2_mkInteger();
Idris2_Value *idris2_mkIntegerLiteral(char *i);
Idris2_String *idris2_mkEmptyString(size_t l);
Idris2_String *idris2_mkString(char *);
// The l bytes at s (which may include NUL characters).
Idris2_String *idris2_mkStringN(char const *s, size_t l);
// Takes ownership of a string from malloc instead of copying it.
Idris2_String *idris2_mkStringOwned(char *);

Idris2_Pointer *idris2_makePointer(void *);
Idris2_GCPointer *idris2_makeGCPointer(void *ptr_Raw,
                                       Idris2_Closure *onCollectFct);
Idris2_Buffer *idris2_makeBuffer(void *buf);
Idris2_Array *idris2_makeArray(int length);

extern Idris2_Int64 const idris2_predefined_Int64[100];
extern Idris2_Bits64 const idris2_predefined_Bits64[100];

static inline Idris2_Value *idris2_mkDouble(double d) {
  Idris2_Double *retVal = IDRIS2_NEW_VALUE(Idris2_Double);
  retVal->header.tag = DOUBLE_TAG;
  retVal->d = d;
  return (Idris2_Value *)retVal;
}

static inline Idris2_Value *idris2_mkBits64(uint64_t i) {
  if (idris2_vp_int_shift == 32 && i <= UINT32_MAX)
    return (Idris2_Value *)(((uintptr_t)(i) << 32) + 1);
  if (i < 100)
    return (Idris2_Value *)&idris2_predefined_Bits64[i];
  Idris2_Bits64 *retVal = IDRIS2_NEW_VALUE(Idris2_Bits64);
  retVal->header.tag = BITS64_TAG;
  retVal->ui64 = i;
  return (Idris2_Value *)retVal;
}

static inline Idris2_Value *idris2_mkInt64(int64_t i) {
  if (idris2_vp_int_shift == 32 && i >= INT32_MIN && i <= INT32_MAX)
    return (Idris2_Value *)(((uintptr_t)(i) << 32) + 1);
  if (i >= 0 && i < 100)
    return (Idris2_Value *)&idris2_predefined_Int64[i];
  Idris2_Int64 *retVal = IDRIS2_NEW_VALUE(Idris2_Int64);
  retVal->header.tag = INT64_TAG;
  retVal->i64 = i;
  return (Idris2_Value *)retVal;
}
extern Idris2_Integer idris2_predefined_Integer[100];
Idris2_Value *idris2_getPredefinedInteger(int n);


// An Integer literal of the generated code, made from its digits the first
// time that it is needed, and kept in *slot for good (it is immortal).
Idris2_Value *idris2_makeIntegerConstant(Idris2_Value **slot,
                                         char const *digits);
static inline Idris2_Value *idris2_integerConstant(Idris2_Value **slot,
                                                   char const *digits) {
  return *slot ? *slot : idris2_makeIntegerConstant(slot, digits);
}
extern Idris2_ShortString const idris2_predefined_nullstring;

// Immortal nullary constructors with the tags 0 .. IDRIS2_PREDEFINED_NULLARY-1,
// which the generated code uses instead of allocating them.
#define IDRIS2_PREDEFINED_NULLARY 256
extern Idris2_NullaryConstructor const
    idris2_predefined_nullary[IDRIS2_PREDEFINED_NULLARY];
#define idris2_nullaryConstructor(tag)                                         \
  ((Idris2_Value *)&idris2_predefined_nullary[tag])


// You need uncomment a debugging code in memoryManagement.c to use this.
void idris2_dumpMemoryStats(void);
