#pragma once

#include "_datatypes.h"
#include "worker.h"

// Allocation of values: see the description in memoryManagement.c.  The
// common case is inlined.  The pages are those of the current worker (see
// worker.h).

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
    Idris2_Page *page = idris2_worker()->classes[cls].current;
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
    IDRIS2_STAT(allocs[cls]);
    return retVal;
  }
#endif
  return idris2_allocLarge(size);
}
// Give back the memory of a value (only: what it refers to is not released).
void idris2_freeValue(Idris2_Value *value);

// How many empty pages a worker keeps before it gives their memory back to
// the system: IDRIS2_REFC_KEEP_PAGES, 16 (1MB) by default (see threads.c).
extern int idris2_keepPages;

// The worker `w` goes idle: its empty pages go to the other workers (see
// park in threads.c).  Called on the OS thread of the worker.
void idris2_releaseWorkerPages(Idris2_Worker *w);

// The memory returned by idris2_newValue is not initialised.  Use this to
// create a value whose payload is zeroed, without disturbing its header.
Idris2_Value *idris2_newZeroedValue(size_t size);

void idris2_releaseValue(Idris2_Value *elem);

// ---------------------------------------------------------------------------
// Shared values
//
// A value that only one green thread can see is reference counted with
// plain increments and decrements.  Once a value may be seen by several
// green threads, which may run in parallel, it is "shared": its counter is
// updated atomically.  A value becomes shared, together with all the values
// that it refers to, when it is handed over to another thread (the action of
// `fork`, a value put in a shared channel, IORef or array, a constant of the
// program; see idris2_markShared).  A shared value only refers to shared
// values, and it is never updated in place while other threads may see it
// (see idris2_tryUnshare).
//
// Until a second worker starts, no value is shared.
// ---------------------------------------------------------------------------

// Make `v` and everything that it refers to shared.
void idris2_markShared(Idris2_Value *v);

// A shared value with a single reference: the thread that holds it is the
// only one that can see it, so it can stop being shared (what it refers to
// stays shared, which is allowed).  Returns 1 when `v` has a single
// reference, and is not shared any more.
static inline int idris2_tryUnshare(Idris2_Value *v) {
  // (acquire: the writes of the threads that dropped their references are
  // visible before we update the value in place)
  if (__atomic_load_n(&v->header.refCounter, __ATOMIC_ACQUIRE) != 1)
    return 0;
  v->header.reserved &= (uint8_t)~IDRIS2_SHARED_FLAG;
  return 1;
}

// The reference counting of shared, immortal and overflowed values (see
// IDRIS2_VP_REFCOUNTER_OVERFLOW), out of line.
void idris2_newReferenceSlow(Idris2_Value *v);
void idris2_removeReferenceSlow(Idris2_Value *v);

// Is the value neither shared nor immortal, and is its count below the
// overflow, i.e. is its reference count updated in place?  This is the common case, tested with one comparison
// where the layout of the header allows it.
#if defined(__BYTE_ORDER__) && __BYTE_ORDER__ == __ORDER_LITTLE_ENDIAN__
static inline uint32_t idris2_headerWord(Idris2_Value *v) {
  uint32_t word;
  memcpy(&word, &v->header, sizeof(word));
  return word;
}
// The reference count is in the low 16 bits, the shared flag in the top one.
#define idris2_isPlainCounted(word)                                           \
  (((word) & (0x80000000u | IDRIS2_VP_REFCOUNTER_MAX)) <                       \
   IDRIS2_VP_REFCOUNTER_OVERFLOW)
#define idris2_wordRefCounter(word) ((uint16_t)(word))
#else
static inline Idris2_header idris2_headerWord(Idris2_Value *v) {
  return v->header;
}
#define idris2_isPlainCounted(h)                                               \
  (!((h).reserved & IDRIS2_SHARED_FLAG) &&                                     \
   (h).refCounter < IDRIS2_VP_REFCOUNTER_OVERFLOW)
#define idris2_wordRefCounter(h) ((h).refCounter)
#endif

// Take a reference.  NULL (an erased value), unboxed values and immortal
// values (statically allocated values and constants) are left alone.
// (Forced inline: GCC otherwise calls an out of line copy in big functions,
// which costs much more than the few instructions of the common case.)
#if defined(__GNUC__)
#define IDRIS2_INLINE static inline __attribute__((always_inline))
#else
#define IDRIS2_INLINE static inline
#endif

IDRIS2_INLINE Idris2_Value *idris2_newReference(Idris2_Value *source) {
  if (source && !idris2_vp_is_unboxed(source)) {
    if (__builtin_expect(idris2_isPlainCounted(idris2_headerWord(source)), 1)) {
      ++source->header.refCounter;
#ifdef IDRIS2_REFC_STATS
      IDRIS2_STAT(dup[IDRIS2_RC_PLAIN]);
#endif
    } else if (idris2_wordRefCounter(idris2_headerWord(source)) !=
               IDRIS2_VP_REFCOUNTER_MAX) {
      // (not immortal, which static values and constants are: for those the
      // test is all there is to do, and the C compiler removes it for a
      // static value that it sees)
      idris2_newReferenceSlow(source);
    }
  } else {
    IDRIS2_STAT(dup[IDRIS2_RC_IMMEDIATE]);
  }
  return source;
}

// Forget the references of an overflowed value that the side table counts.
void idris2_forgetOverflow(Idris2_Value *v);

// Make a value immortal (it is never released), and give it back.
static inline Idris2_Value *idris2_makeImmortal(Idris2_Value *v) {
  // (static values are immortal already, and may be read only)
  if (v && !idris2_vp_is_unboxed(v) &&
      v->header.refCounter != IDRIS2_VP_REFCOUNTER_MAX) {
    if (v->header.refCounter == IDRIS2_VP_REFCOUNTER_OVERFLOW)
      idris2_forgetOverflow(v);
    __atomic_store_n(&v->header.refCounter, IDRIS2_VP_REFCOUNTER_MAX,
                     __ATOMIC_RELAXED);
  }
  return v;
}

// Drop a reference, releasing the value when it was the last one.
IDRIS2_INLINE void idris2_removeReference(Idris2_Value *elem) {
  if (!elem || idris2_vp_is_unboxed(elem)) {
    IDRIS2_STAT(drop[IDRIS2_RC_IMMEDIATE]);
    return;
  }
  if (__builtin_expect(idris2_isPlainCounted(idris2_headerWord(elem)), 1)) {
    IDRIS2_STAT(drop[IDRIS2_RC_PLAIN]);
    uint16_t count = idris2_wordRefCounter(idris2_headerWord(elem));
    if (count != 1)
      elem->header.refCounter = count - 1;
    else
      idris2_releaseValue(elem);
  } else if (idris2_wordRefCounter(idris2_headerWord(elem)) !=
             IDRIS2_VP_REFCOUNTER_MAX) {
    idris2_removeReferenceSlow(elem);
  }
}

// Drop a reference to a value that has other references (but may be
// immortal, or overflowed).  Another thread may drop the other references of a shared
// value at the same time, so that one is released if need be.
IDRIS2_INLINE void idris2_dropSharedReference(Idris2_Value *v) {
  if (__builtin_expect(idris2_isPlainCounted(idris2_headerWord(v)), 1)) {
    IDRIS2_STAT(drop[IDRIS2_RC_PLAIN]);
    --v->header.refCounter;
  } else if (idris2_wordRefCounter(idris2_headerWord(v)) !=
             IDRIS2_VP_REFCOUNTER_MAX)
    idris2_removeReferenceSlow(v);
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
  Idris2_Value *v = __atomic_load_n(slot, __ATOMIC_ACQUIRE);
  return v ? v : idris2_makeIntegerConstant(slot, digits);
}
extern Idris2_ShortString const idris2_predefined_nullstring;

// Immortal nullary constructors with the tags 0 .. IDRIS2_PREDEFINED_NULLARY-1,
// which the generated code uses instead of allocating them.
#define IDRIS2_PREDEFINED_NULLARY 256
extern Idris2_NullaryConstructor const
    idris2_predefined_nullary[IDRIS2_PREDEFINED_NULLARY];
#define idris2_nullaryConstructor(tag)                                         \
  ((Idris2_Value *)&idris2_predefined_nullary[tag])


// The reports at exit (see refc.rst): with IDRIS2_REFC_MEMSTATS=1 the pages
// and, in a build with IDRIS2_REFC_STATS, the counters (see worker.h); with
// IDRIS2_REFC_LEAKCHECK=1 (or 2, with examples) the values that are still
// alive.  `finished` says that the main expression is done (otherwise the
// program is exiting from somewhere else, and only the statistics make
// sense); `threadsLeft` is the number of other threads that still run (the
// leak check is skipped then).
void idris2_reportAtExit(int finished, long long threadsLeft);
// The statistics, now (to stderr).
void idris2_dumpMemoryStats(void);
