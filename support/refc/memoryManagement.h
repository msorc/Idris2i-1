#pragma once

#include "_datatypes.h"
#include "worker.h"

// Allocation of values: see the description in memoryManagement.c.  The
// common case is inlined.  The pages are those of the current worker (see
// worker.h).

// The current page of the class is full: move on to another one.
Idris2i_1_Value *idris2i_1_allocSlow(unsigned cls);
// A value that is too large for the pages, from malloc.
Idris2i_1_Value *idris2i_1_allocLarge(size_t size);

// A new value of `size` bytes, with a reference count of 1.  Its payload is
// not initialised.
static inline Idris2i_1_Value *idris2i_1_newValue(size_t size) {
#ifndef IDRIS2I_1_REFC_NO_POOLS
  unsigned cls = (unsigned)((size + IDRIS2I_1_ALLOC_UNIT - 1) / IDRIS2I_1_ALLOC_UNIT);
  if (cls <= IDRIS2I_1_ALLOC_CLASSES) {
    if (cls == 0)
      cls = 1;
    Idris2i_1_Value *retVal;
    Idris2i_1_Page *page = idris2i_1_worker()->classes[cls].current;
    Idris2i_1_FreeValue *v;
    if (page && (v = page->free) != NULL) {
      page->free = v->next;
      retVal = (Idris2i_1_Value *)v;
    } else if (page && page->bump < page->end) {
      retVal = (Idris2i_1_Value *)page->bump;
      page->bump += (size_t)cls * IDRIS2I_1_ALLOC_UNIT;
    } else {
      // Sets the header (its class may be 0, see memoryManagement.c).
      return idris2i_1_allocSlow(cls);
    }
    retVal->header.reserved = (uint8_t)cls;
    retVal->header.refCounter = 1;
    retVal->header.tag = NO_TAG;
    IDRIS2I_1_STAT(allocs[cls]);
    return retVal;
  }
#endif
  return idris2i_1_allocLarge(size);
}
// Give back the memory of a value (only: what it refers to is not released).
void idris2i_1_freeValue(Idris2i_1_Value *value);

// How many empty pages a worker keeps before it gives their memory back to
// the system: IDRIS2I_1_REFC_KEEP_PAGES, 16 (1MB) by default (see threads.c).
extern int idris2i_1_keepPages;

// The worker `w` goes idle: its empty pages go to the other workers (see
// park in threads.c).  Called on the OS thread of the worker.
void idris2i_1_releaseWorkerPages(Idris2i_1_Worker *w);

// The memory returned by idris2i_1_newValue is not initialised.  Use this to
// create a value whose payload is zeroed, without disturbing its header.
Idris2i_1_Value *idris2i_1_newZeroedValue(size_t size);

void idris2i_1_releaseValue(Idris2i_1_Value *elem);

// ---------------------------------------------------------------------------
// Shared values
//
// A value that only one green thread can see is reference counted with
// plain increments and decrements.  Once a value may be seen by several
// green threads, which may run in parallel, it is "shared": its counter is
// updated atomically.  A value becomes shared, together with all the values
// that it refers to, when it is handed over to another thread (the action of
// `fork`, a value put in a shared channel, IORef or array, a constant of the
// program; see idris2i_1_markShared).  A shared value only refers to shared
// values, and it is never updated in place while other threads may see it
// (see idris2i_1_tryUnshare).
//
// Until a second worker starts, no value is shared.
// ---------------------------------------------------------------------------

// Make `v` and everything that it refers to shared.
void idris2i_1_markShared(Idris2i_1_Value *v);

// A shared value with a single reference: the thread that holds it is the
// only one that can see it, so it can stop being shared (what it refers to
// stays shared, which is allowed).  Returns 1 when `v` has a single
// reference, and is not shared any more.
static inline int idris2i_1_tryUnshare(Idris2i_1_Value *v) {
  // (acquire: the writes of the threads that dropped their references are
  // visible before we update the value in place)
  if (__atomic_load_n(&v->header.refCounter, __ATOMIC_ACQUIRE) != 1)
    return 0;
  v->header.reserved &= (uint8_t)~IDRIS2I_1_SHARED_FLAG;
  return 1;
}

// The reference counting of shared, immortal and overflowed values (see
// IDRIS2I_1_VP_REFCOUNTER_OVERFLOW), out of line.
void idris2i_1_newReferenceSlow(Idris2i_1_Value *v);
void idris2i_1_removeReferenceSlow(Idris2i_1_Value *v);

// Is the value neither shared nor immortal, and is its count below the
// overflow, i.e. is its reference count updated in place?  This is the common case, tested with one comparison
// where the layout of the header allows it.
#if defined(__BYTE_ORDER__) && __BYTE_ORDER__ == __ORDER_LITTLE_ENDIAN__
static inline uint32_t idris2i_1_headerWord(Idris2i_1_Value *v) {
  uint32_t word;
  memcpy(&word, &v->header, sizeof(word));
  return word;
}
// The reference count is in the low 16 bits, the shared flag in the top one.
#define idris2i_1_isPlainCounted(word)                                           \
  (((word) & (0x80000000u | IDRIS2I_1_VP_REFCOUNTER_MAX)) <                       \
   IDRIS2I_1_VP_REFCOUNTER_OVERFLOW)
#define idris2i_1_wordRefCounter(word) ((uint16_t)(word))
#else
static inline Idris2i_1_header idris2i_1_headerWord(Idris2i_1_Value *v) {
  return v->header;
}
#define idris2i_1_isPlainCounted(h)                                               \
  (!((h).reserved & IDRIS2I_1_SHARED_FLAG) &&                                     \
   (h).refCounter < IDRIS2I_1_VP_REFCOUNTER_OVERFLOW)
#define idris2i_1_wordRefCounter(h) ((h).refCounter)
#endif

// Is the value immortal, as far as the code in line tests it?  Static values
// and the constants of a program are: nothing is counted for them, and the
// test saves a call of the runtime, which finds the same (the compiler built
// with RefC runs 1.5% faster for it, a tree sort 7%).  It makes the code 10%
// bigger and the C compiler as much slower: -DIDRIS2I_1_REFC_SMALL_CODE leaves
// the test to the runtime.
#ifdef IDRIS2I_1_REFC_SMALL_CODE
#define idris2i_1_isImmortalInline(v) 0
#else
#define idris2i_1_isImmortalInline(v)                                             \
  (idris2i_1_wordRefCounter(idris2i_1_headerWord(v)) == IDRIS2I_1_VP_REFCOUNTER_MAX)
#endif

// Take a reference.  NULL (an erased value), unboxed values and immortal
// values (statically allocated values and constants) are left alone.
// (Forced inline: GCC otherwise calls an out of line copy in big functions,
// which costs much more than the few instructions of the common case.)
#if defined(__GNUC__)
#define IDRIS2I_1_INLINE static inline __attribute__((always_inline))
#else
#define IDRIS2I_1_INLINE static inline
#endif

IDRIS2I_1_INLINE Idris2i_1_Value *idris2i_1_newReference(Idris2i_1_Value *source) {
  if (source && !idris2i_1_vp_is_unboxed(source)) {
    if (__builtin_expect(idris2i_1_isPlainCounted(idris2i_1_headerWord(source)), 1)) {
      ++source->header.refCounter;
      IDRIS2I_1_STAT_REAL(dups, source);
    } else if (!idris2i_1_isImmortalInline(source)) {
      idris2i_1_newReferenceSlow(source);
    } else {
      IDRIS2I_1_STAT_IMMORTAL(dups, source);
    }
  } else {
    IDRIS2I_1_STAT_NULL_OR_UNBOXED(dups, source);
  }
  return source;
}

// Forget the references of an overflowed value that the side table counts.
void idris2i_1_forgetOverflow(Idris2i_1_Value *v);

// Make a value immortal (it is never released), and give it back.
static inline Idris2i_1_Value *idris2i_1_makeImmortal(Idris2i_1_Value *v) {
  // (static values are immortal already, and may be read only)
  if (v && !idris2i_1_vp_is_unboxed(v) &&
      v->header.refCounter != IDRIS2I_1_VP_REFCOUNTER_MAX) {
    if (v->header.refCounter == IDRIS2I_1_VP_REFCOUNTER_OVERFLOW)
      idris2i_1_forgetOverflow(v);
    __atomic_store_n(&v->header.refCounter, IDRIS2I_1_VP_REFCOUNTER_MAX,
                     __ATOMIC_RELAXED);
  }
  return v;
}

// Drop a reference, releasing the value when it was the last one.
IDRIS2I_1_INLINE void idris2i_1_removeReference(Idris2i_1_Value *elem) {
  if (!elem || idris2i_1_vp_is_unboxed(elem)) {
    IDRIS2I_1_STAT_NULL_OR_UNBOXED(drops, elem);
    return;
  }
  if (__builtin_expect(idris2i_1_isPlainCounted(idris2i_1_headerWord(elem)), 1)) {
    IDRIS2I_1_STAT_REAL(drops, elem);
    uint16_t count = idris2i_1_wordRefCounter(idris2i_1_headerWord(elem));
    if (count != 1)
      elem->header.refCounter = count - 1;
    else
      idris2i_1_releaseValue(elem);
  } else if (!idris2i_1_isImmortalInline(elem)) {
    idris2i_1_removeReferenceSlow(elem);
  } else {
    IDRIS2I_1_STAT_IMMORTAL(drops, elem);
  }
}

// Drop a reference to a value that has other references (but may be
// immortal, or overflowed).  Another thread may drop the other references of a shared
// value at the same time, so that one is released if need be.
IDRIS2I_1_INLINE void idris2i_1_dropSharedReference(Idris2i_1_Value *v) {
  if (__builtin_expect(idris2i_1_isPlainCounted(idris2i_1_headerWord(v)), 1)) {
    IDRIS2I_1_STAT_REAL(drops, v);
    --v->header.refCounter;
  } else if (!idris2i_1_isImmortalInline(v))
    idris2i_1_removeReferenceSlow(v);
  else
    IDRIS2I_1_STAT_IMMORTAL(drops, v);
}

#define IDRIS2I_1_NEW_VALUE(t) ((t *)idris2i_1_newValue(sizeof(t)))

static inline Idris2i_1_Constructor *idris2i_1_newConstructor(int total, int tag) {
  Idris2i_1_Constructor *retVal = (Idris2i_1_Constructor *)idris2i_1_newValue(
      sizeof(Idris2i_1_Constructor) + sizeof(Idris2i_1_Value *) * total);
  retVal->header.tag = CONSTRUCTOR_TAG;
  retVal->total = (uint16_t)total;
  retVal->tag = (int16_t)tag;
  IDRIS2I_1_STAT_KIND(allocKind, IDRIS2I_1_KIND_CONSTRUCTOR);
  return retVal;
}

// A constructor with raw fields (see docs/source/backends/refc-flat-layout.rst):
// its `np` pointer fields, which `total` counts (so that the release, the
// marking of shared values and the leak check never look further), then `nr`
// raw fields of 8 bytes each (a double, an int64_t or a uint64_t), from the
// first offset after the pointer fields that is a multiple of 8.  The raw
// field `j` (from 0) of the C type `T` is `idris2i_1_rawField(c, np, j, T)`.
#define IDRIS2I_1_RAW_OFFSET(np)                                                  \
  ((sizeof(Idris2i_1_Constructor) + (size_t)(np) * sizeof(Idris2i_1_Value *) + 7) &  \
   ~(size_t)7)
#define IDRIS2I_1_RAW_SIZE(np, nr) (IDRIS2I_1_RAW_OFFSET(np) + 8 * (size_t)(nr))
#define idris2i_1_rawField(c, np, j, T)                                           \
  (*(T *)((char *)(c) + IDRIS2I_1_RAW_OFFSET(np) + 8 * (size_t)(j)))

static inline Idris2i_1_Constructor *idris2i_1_newRawConstructor(int np, int nr,
                                                            int tag) {
  Idris2i_1_Constructor *retVal =
      (Idris2i_1_Constructor *)idris2i_1_newValue(IDRIS2I_1_RAW_SIZE(np, nr));
  retVal->header.tag = CONSTRUCTOR_TAG;
  retVal->total = (uint16_t)np;
  retVal->tag = (int16_t)tag;
  return retVal;
}

// Copy the raw fields of a cell to another cell of the same constructor.
#define idris2i_1_copyRawFields(dst, src, np, nr)                                 \
  memcpy((char *)(dst) + IDRIS2I_1_RAW_OFFSET(np),                                \
         (char *)(src) + IDRIS2I_1_RAW_OFFSET(np), 8 * (size_t)(nr))

// `--directive refc-check-layout`: a cell matched as the constructor `name`
// (a C string literal) has the number of pointer fields of that constructor.
// After a `believe_me` between data types laid out differently, it may not.
#define IDRIS2I_1_CHECK_LAYOUT(c, np, name)                                       \
  do {                                                                         \
    if (((Idris2i_1_Constructor *)(c))->total != (np))                            \
      idris2i_1_crashCheck("refc-check-layout: a value matched as " name            \
                      " is not laid out as one");                               \
  } while (0)

// A constructor that is told apart by its name instead of a tag.
static inline Idris2i_1_Constructor *
idris2i_1_newNamedConstructor(int total, char const *name) {
  Idris2i_1_Constructor *retVal = (Idris2i_1_Constructor *)idris2i_1_newValue(
      sizeof(Idris2i_1_Constructor) + sizeof(Idris2i_1_Value *) * (total + 1));
  retVal->header.tag = CONSTRUCTOR_TAG;
  retVal->total = (uint16_t)total;
  retVal->tag = -1;
  retVal->args[total] = (Idris2i_1_Value *)name;
  IDRIS2I_1_STAT_KIND(allocKind, IDRIS2I_1_KIND_CONSTRUCTOR);
  return retVal;
}

// The caller must initialise args[0 .. filled-1].  There is room for every
// argument, so that applying a closure that nobody else refers to can store
// the argument in place (see idris2i_1_tailcall_apply_closure).
static inline Idris2i_1_Closure *idris2i_1_mkClosure(Idris2i_1_Value *(*f)(),
                                               uint16_t arity, uint16_t filled) {
  int room = arity > filled ? arity : filled;
  Idris2i_1_Closure *retVal = (Idris2i_1_Closure *)idris2i_1_newValue(
      sizeof(Idris2i_1_Closure) + sizeof(Idris2i_1_Value *) * room);
  retVal->header.tag = CLOSURE_TAG;
  retVal->f = f;
  retVal->arity = arity;
  retVal->filled = filled;
  IDRIS2I_1_STAT_KIND(allocKind, IDRIS2I_1_KIND_CLOSURE);
  return retVal;
}

// The unboxed values: the integer is shifted into the bits of the pointer
// above the tag.  It is first converted to its type (truncated, and sign
// extended for the signed types), so that every value has a single
// representation, whatever the C expression that computed it (C promotes
// `uint8_t` to `int` in `x + y`, for example): the casts between types that
// have the same representation, and the `case`s, rely on it.
#define idris2i_1_mkUnboxed(ty, x)                                                \
  ((Idris2i_1_Value *)(((uintptr_t)(ty)(x) << idris2i_1_vp_int_shift) + 1))
#define idris2i_1_mkChar(x) idris2i_1_mkUnboxed(uint32_t, x)
#define idris2i_1_mkBits8(x) idris2i_1_mkUnboxed(uint8_t, x)
#define idris2i_1_mkBits16(x) idris2i_1_mkUnboxed(uint16_t, x)

#if !defined(UINTPTR_WIDTH)
#define idris2i_1_mkBits32(x)                                                     \
  ((idris2i_1_vp_int_shift != 32) ? (idris2i_1_mkBits32_Boxed(x))                    \
                               : idris2i_1_mkUnboxed(uint32_t, x))
#define idris2i_1_mkInt32(x)                                                      \
  ((idris2i_1_vp_int_shift != 32) ? (idris2i_1_mkInt32_Boxed(x))                     \
                               : idris2i_1_mkUnboxed(int32_t, x))

#elif UINTPTR_WIDTH >= 64
#define idris2i_1_mkBits32(x) idris2i_1_mkUnboxed(uint32_t, x)
#define idris2i_1_mkInt32(x) idris2i_1_mkUnboxed(int32_t, x)

#elif UINTPTR_WIDTH >= 32
#define idris2i_1_mkBits32(x) (idris2i_1_mkBits32_Boxed(x))
#define idris2i_1_mkInt32(x) (idris2i_1_mkInt32_Boxed(x))

#else
#error "unsupported uintptr_t width"
#endif

#define idris2i_1_mkInt8(x) idris2i_1_mkUnboxed(int8_t, x)
#define idris2i_1_mkInt16(x) idris2i_1_mkUnboxed(int16_t, x)
#define idris2i_1_mkBool(x) (idris2i_1_mkInt8(x))

Idris2i_1_Value *idris2i_1_mkBits32_Boxed(uint32_t i);
Idris2i_1_Value *idris2i_1_mkInt32_Boxed(int32_t i);

Idris2i_1_Integer *idris2i_1_mkInteger();
Idris2i_1_Value *idris2i_1_mkIntegerLiteral(char *i);
Idris2i_1_String *idris2i_1_mkEmptyString(size_t l);
// Copies s; s stays with the caller.
Idris2i_1_String *idris2i_1_mkString(const char *);
// The l bytes at s (which may include NUL characters).
Idris2i_1_String *idris2i_1_mkStringN(char const *s, size_t l);
// Takes ownership of a string from malloc instead of copying it.
Idris2i_1_String *idris2i_1_mkStringOwned(char *);

// Record that the string s, just made (no other thread sees it yet), has n
// code points.  The empty string is a static value, which is left alone.
static inline void idris2i_1_setCodePoints(Idris2i_1_String *s, int64_t n) {
  if (n >= 0 && n < (int64_t)UINT32_MAX &&
      !(s->header.reserved & IDRIS2I_1_STATIC_FLAG))
    s->codePoints = (uint32_t)(n + 1);
}
// The same for a string of ASCII characters only (or more generally, one byte
// per character).
#define idris2i_1_setAscii(s) idris2i_1_setCodePoints((s), (int64_t)(s)->len)

Idris2i_1_Pointer *idris2i_1_makePointer(void *);
Idris2i_1_GCPointer *idris2i_1_makeGCPointer(void *ptr_Raw,
                                       Idris2i_1_Closure *onCollectFct);
Idris2i_1_Buffer *idris2i_1_makeBuffer(void *buf);
Idris2i_1_Array *idris2i_1_makeArray(int length);

extern Idris2i_1_Int64 const idris2i_1_predefined_Int64[100];
extern Idris2i_1_Bits64 const idris2i_1_predefined_Bits64[100];

static inline Idris2i_1_Value *idris2i_1_mkDouble(double d) {
  Idris2i_1_Double *retVal = IDRIS2I_1_NEW_VALUE(Idris2i_1_Double);
  retVal->header.tag = DOUBLE_TAG;
  retVal->d = d;
  IDRIS2I_1_STAT_KIND(allocKind, IDRIS2I_1_KIND_NUMBER);
  return (Idris2i_1_Value *)retVal;
}

static inline Idris2i_1_Value *idris2i_1_mkBits64(uint64_t i) {
  if (idris2i_1_vp_int_shift == 32 && i <= UINT32_MAX)
    return (Idris2i_1_Value *)(uintptr_t)(((uint64_t)(i) << 32) + 1);
  if (i < 100)
    return (Idris2i_1_Value *)&idris2i_1_predefined_Bits64[i];
  Idris2i_1_Bits64 *retVal = IDRIS2I_1_NEW_VALUE(Idris2i_1_Bits64);
  retVal->header.tag = BITS64_TAG;
  retVal->ui64 = i;
  IDRIS2I_1_STAT_KIND(allocKind, IDRIS2I_1_KIND_NUMBER);
  return (Idris2i_1_Value *)retVal;
}

static inline Idris2i_1_Value *idris2i_1_mkInt64(int64_t i) {
  if (idris2i_1_vp_int_shift == 32 && i >= INT32_MIN && i <= INT32_MAX)
    return (Idris2i_1_Value *)(uintptr_t)(((uint64_t)(i) << 32) + 1);
  if (i >= 0 && i < 100)
    return (Idris2i_1_Value *)&idris2i_1_predefined_Int64[i];
  Idris2i_1_Int64 *retVal = IDRIS2I_1_NEW_VALUE(Idris2i_1_Int64);
  retVal->header.tag = INT64_TAG;
  retVal->i64 = i;
  IDRIS2I_1_STAT_KIND(allocKind, IDRIS2I_1_KIND_NUMBER);
  return (Idris2i_1_Value *)retVal;
}
extern Idris2i_1_Integer idris2i_1_predefined_Integer[100];
Idris2i_1_Value *idris2i_1_getPredefinedInteger(int n);


// An Integer literal of the generated code, made from its digits the first
// time that it is needed, and kept in *slot for good (it is immortal).
Idris2i_1_Value *idris2i_1_makeIntegerConstant(Idris2i_1_Value **slot,
                                         char const *digits);
static inline Idris2i_1_Value *idris2i_1_integerConstant(Idris2i_1_Value **slot,
                                                   char const *digits) {
  Idris2i_1_Value *v = __atomic_load_n(slot, __ATOMIC_ACQUIRE);
  return v ? v : idris2i_1_makeIntegerConstant(slot, digits);
}
extern Idris2i_1_ShortString const idris2i_1_predefined_nullstring;

// Immortal nullary constructors with the tags 0 .. IDRIS2I_1_PREDEFINED_NULLARY-1,
// which the generated code uses instead of allocating them.
#define IDRIS2I_1_PREDEFINED_NULLARY 256
extern Idris2i_1_NullaryConstructor const
    idris2i_1_predefined_nullary[IDRIS2I_1_PREDEFINED_NULLARY];
#define idris2i_1_nullaryConstructor(tag)                                         \
  ((Idris2i_1_Value *)&idris2i_1_predefined_nullary[tag])


// The reports at exit (see refc.rst): with IDRIS2I_1_REFC_MEMSTATS=1 the pages
// and, in a build with IDRIS2I_1_REFC_STATS, the counters (see worker.h); with
// IDRIS2I_1_REFC_LEAKCHECK=1 (or 2, with examples) the values that are still
// alive.  `finished` says that the main expression is done (otherwise the
// program is exiting from somewhere else, and only the statistics make
// sense); `threadsLeft` is the number of other threads that still run (the
// leak check is skipped then).
void idris2i_1_reportAtExit(int finished, long long threadsLeft);
// The statistics, now (to stderr).
void idris2i_1_dumpMemoryStats(void);
