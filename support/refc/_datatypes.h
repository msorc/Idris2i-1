#pragma once

#include <gmp.h>
#include <limits.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "buffer.h"

#define NO_TAG 0
#define BITS32_TAG 3
#define BITS64_TAG 4
#define INT32_TAG 7
#define INT64_TAG 8
#define INTEGER_TAG 9
#define DOUBLE_TAG 10
#define STRING_TAG 12

#define CLOSURE_TAG 15
#define CONSTRUCTOR_TAG 17

#define IOREF_TAG 20
#define ARRAY_TAG 21
#define POINTER_TAG 22
#define GC_POINTER_TAG 23
#define BUFFER_TAG 24

#define MUTEX_TAG 30
#define CONDITION_TAG 31
#define SEMAPHORE_TAG 32
#define BARRIER_TAG 33
#define CHANNEL_TAG 34
#define THREAD_ID_TAG 35

typedef struct {
  // The values with the maximum count are immortal: statically allocated
  // values, and the constants of the program.  A count that would go beyond
  // IDRIS2_VP_REFCOUNTER_OVERFLOW stays there, the other references being
  // counted in a side table (see memoryManagement.c).
#define IDRIS2_VP_REFCOUNTER_MAX UINT16_MAX
#define IDRIS2_VP_REFCOUNTER_OVERFLOW (UINT16_MAX - 1)
  uint16_t refCounter;
  uint8_t tag;
  // The size class of the value (see memoryManagement.c), and two flags.
  uint8_t reserved;
} Idris2_header;

#define IDRIS2_CLASS_MASK 0x3F
// A statically allocated value, which may be in read only memory.
#define IDRIS2_STATIC_FLAG 0x40
// A value that more than one green thread may see (see memoryManagement.h):
// its reference count is updated atomically.  The values that it refers to
// are shared too.
#define IDRIS2_SHARED_FLAG 0x80

#define IDRIS2_STOCKVAL(t)                                                     \
  { IDRIS2_VP_REFCOUNTER_MAX, t, IDRIS2_STATIC_FLAG }

#define idris2_isShared(v) ((v)->header.reserved & IDRIS2_SHARED_FLAG)

// A spin lock (see worker.h); 0 when it is free.
typedef uint32_t Idris2_SpinLock;

typedef struct {
  Idris2_header header;
  // `Idris2_Value` is an "abstract" struct,
  // `Value_Xxx` structs have the same header
  // followed by type-specific payload.
} Idris2_Value;

/*
We expect at least 4 bytes for `Idris2_header` alignment, to use bit0 and bit1
of pointer as flags.

RefC does not have complete static tracking of type information, so types are
identified at runtime using Idris2_header's tag field. However, Int that are
pretending to be pointers cannot have that tag, so use that flag to identify
them first. Of course, this flag is not used if it is clear that Idris2_Value*
is actually an Int. But places like newReference/removeReference require this
flag.
 */
#define idris2_vp_is_unboxed(p) ((uintptr_t)(p)&3)

// How far an unboxed value is shifted into the pointer.  With 32 bit
// pointers, 8 bits leave 24 for the value: enough for the 16 bit integers
// and for a Char (21 bits; with a shift of 16 the characters above U+FFFF
// lost their upper bits).
#define idris2_vp_int_shift                                                    \
  ((sizeof(uintptr_t) >= 8 && sizeof(Idris2_Value *) >= 8) ? 32 : 8)

// The bits of a pointer as 64 bits, for the code of the 64 bit platforms that
// takes the upper half of an unboxed value: on a 32 bit platform that code is
// never run (it is under a test of idris2_vp_int_shift), but it is compiled,
// and a shift of a 32 bit pointer by 32 would be an error under -Werror.
#define idris2_vp_bits64(p) ((uint64_t)(uintptr_t)(p))

// On 64 bit platforms, Int64 and Bits64 values that fit in 32 bits are
// unboxed (see idris2_mkInt64): see idris2_unboxInt64 and idris2_unboxBits64.
#define idris2_vp_to_Bits64(p) (idris2_unboxBits64((Idris2_Value *)(p)))

#if !defined(UINTPTR_WIDTH)
#define idris2_vp_to_Bits32(p)                                                 \
  ((idris2_vp_int_shift != 32)                                                 \
       ? (((Idris2_Bits32 *)(p))->ui32)                                        \
       : ((uint32_t)((uintptr_t)(p) >> idris2_vp_int_shift)))
#define idris2_vp_to_Int32(p)                                                  \
  ((idris2_vp_int_shift != 32)                                                 \
       ? (((Idris2_Int32 *)(p))->i32)                                          \
       : ((int32_t)((uintptr_t)(p) >> idris2_vp_int_shift)))

#elif UINTPTR_WIDTH >= 64
// The Bits32 and Int32 values are always unboxed, in the upper half of the
// pointer.
#define idris2_vp_to_Bits32(p)                                                 \
  ((uint32_t)((uintptr_t)(p) >> idris2_vp_int_shift))
#define idris2_vp_to_Int32(p) ((int32_t)((uintptr_t)(p) >> idris2_vp_int_shift))

#elif UINTPTR_WIDTH >= 32
#define idris2_vp_to_Bits32(p) (((Idris2_Bits32 *)(p))->ui32)
#define idris2_vp_to_Int32(p) (((Idris2_Int32 *)(p))->i32)

#else
#error "unsupported uintptr_t width"
#endif

#define idris2_vp_to_Bits16(p)                                                 \
  ((uint16_t)((uintptr_t)(p) >> idris2_vp_int_shift))
#define idris2_vp_to_Bits8(p) ((uint8_t)((uintptr_t)(p) >> idris2_vp_int_shift))
#define idris2_vp_to_Int64(p) (idris2_unboxInt64((Idris2_Value *)(p)))
#define idris2_vp_to_Int16(p) ((int16_t)((uintptr_t)(p) >> idris2_vp_int_shift))
#define idris2_vp_to_Int8(p) ((int8_t)((uintptr_t)(p) >> idris2_vp_int_shift))
#define idris2_vp_to_Char(p) ((uint32_t)((uintptr_t)(p) >> idris2_vp_int_shift))
#define idris2_vp_to_Double(p) (((Idris2_Double *)(p))->d)
#define idris2_vp_to_Bool(p) (idris2_vp_to_Int8(p))

typedef struct {
  Idris2_header header;
  uint32_t ui32;
} Idris2_Bits32;

typedef struct {
  Idris2_header header;
  uint64_t ui64;
} Idris2_Bits64;

static inline uint64_t idris2_unboxBits64(Idris2_Value *p) {
  if (idris2_vp_int_shift == 32 && idris2_vp_is_unboxed(p))
    return (uint32_t)(idris2_vp_bits64(p) >> 32);
  return ((Idris2_Bits64 *)(p))->ui64;
}


typedef struct {
  Idris2_header header;
  int32_t i32;
} Idris2_Int32;

typedef struct {
  Idris2_header header;
  int64_t i64;
} Idris2_Int64;

static inline int64_t idris2_unboxInt64(Idris2_Value *p) {
  if (idris2_vp_int_shift == 32 && idris2_vp_is_unboxed(p))
    return (int32_t)(idris2_vp_bits64(p) >> 32);
  return ((Idris2_Int64 *)(p))->i64;
}


typedef struct {
  Idris2_header header;
  mpz_t i;
} Idris2_Integer;

// Integers from INT32_MIN to INT32_MAX may be unboxed on 64 bit platforms,
// like the small Int64: the functions on Integers accept both kinds (see
// idris2_integerMpz), and they give small results unboxed.
#define idris2_isSmallInteger(v)                                               \
  (idris2_vp_int_shift == 32 && idris2_vp_is_unboxed(v))
#define idris2_smallInteger(v) ((int64_t)(int32_t)(idris2_vp_bits64(v) >> 32))
#define idris2_mkSmallInteger(n)                                               \
  ((Idris2_Value *)(uintptr_t)(((uint64_t)(int64_t)(n) << 32) + 1))
static inline int idris2_fitsSmallInteger(int64_t n) {
  return idris2_vp_int_shift == 32 && n >= INT32_MIN && n <= INT32_MAX;
}

Idris2_Value *idris2_mkIntegerFromInt64Boxed(int64_t n);
static inline Idris2_Value *idris2_mkIntegerFromInt64(int64_t n) {
  return idris2_fitsSmallInteger(n) ? idris2_mkSmallInteger(n)
                                    : idris2_mkIntegerFromInt64Boxed(n);
}
Idris2_Value *idris2_mkIntegerFromUInt64(uint64_t n);
// The value of a new Integer, unboxed if it is small enough (then `i` is
// given back).
Idris2_Value *idris2_normaliseInteger(Idris2_Integer *i);

// The GMP integer of an Integer value.  For an unboxed one, it is made in
// `view`, read only, without allocating.
typedef struct {
  mpz_t z;
  mp_limb_t limb;
} Idris2_IntegerView;
static inline mpz_srcptr idris2_integerMpz(Idris2_Value *v,
                                           Idris2_IntegerView *view) {
  if (idris2_isSmallInteger(v)) {
    int64_t n = idris2_smallInteger(v);
    view->limb = (mp_limb_t)(n < 0 ? -n : n);
    return mpz_roinit_n(view->z, &view->limb, n < 0 ? -1 : (n > 0 ? 1 : 0));
  }
  return ((Idris2_Integer *)v)->i;
}
#define IDRIS2_INTEGER_MPZ(name, v)                                            \
  Idris2_IntegerView name##_view;                                              \
  mpz_srcptr name = idris2_integerMpz((v), &name##_view)

// The low 64 bits of the absolute value of `z`.  This is mpz_get_ui where an
// `unsigned long` has 64 bits; it has 32 on the 32 bit platforms (and on 64
// bit Windows), where the limbs of `z` are put together instead.
static inline uint64_t idris2_mpzLow64(mpz_srcptr z) {
#if ULONG_MAX >= UINT64_MAX
  return mpz_get_ui(z);
#else
  uint64_t n = 0;
  size_t limbs = mpz_size(z);
  for (size_t k = 0; k < limbs && k * GMP_NUMB_BITS < 64; ++k)
    n |= (uint64_t)mpz_getlimbn(z, k) << (k * GMP_NUMB_BITS);
  return n;
#endif
}


typedef struct {
  Idris2_header header;
  double d;
} Idris2_Double;

// A string: `len` bytes of UTF-8 (which may include NUL characters), stored
// after the header and followed by a NUL, so that `str` is also a C string
// (cut at the first NUL character, if any).
//
// `codePoints` is the number of code points (characters) of the string plus
// one, or 0 when it is not known (yet): see idris2_stringCodePoints.  When it
// is `len + 1`, each character is one byte (the string is ASCII, but for
// invalid bytes), and the characters can be indexed directly.  On 64 bit
// platforms, it fills the padding before `len`.
typedef struct {
  Idris2_header header;
  uint32_t codePoints;
  size_t len;
  char str[];
} Idris2_String;

// A string constant of up to 15 bytes, with the layout of Idris2_String.
typedef struct {
  Idris2_header header;
  uint32_t codePoints;
  size_t len;
  char str[16];
} Idris2_ShortString;

// The constants of a program are defined in a header that goes into every
// part of a split C file, most of which do not use most of them.
#define IDRIS2_UNUSED __attribute__((unused))

// A string constant `name` of the generated code, for the C string literal
// `lit` (which may contain NUL characters).  The ASCII version is for a
// literal of ASCII characters only: then the number of characters is known.
#define IDRIS2_STRING_CONSTANT_CP(name, lit, cp)                               \
  IDRIS2_UNUSED static const struct {                                          \
    Idris2_header header;                                                      \
    uint32_t codePoints;                                                       \
    size_t len;                                                                \
    char str[sizeof(lit)];                                                     \
  } name = {IDRIS2_STOCKVAL(STRING_TAG), cp, sizeof(lit) - 1, lit}
#define IDRIS2_STRING_CONSTANT(name, lit) IDRIS2_STRING_CONSTANT_CP(name, lit, 0)
#define IDRIS2_ASCII_STRING_CONSTANT(name, lit)                                \
  IDRIS2_STRING_CONSTANT_CP(name, lit, sizeof(lit))

// Is the string `v` the C string literal `lit`?
#define idris2_eqStringLiteral(v, lit)                                         \
  (((Idris2_String *)(v))->len == sizeof(lit) - 1 &&                           \
   memcmp(((Idris2_String *)(v))->str, lit, sizeof(lit) - 1) == 0)

// A constructor has a tag, or (when it has none, tag is -1) its name in a
// slot after its arguments (see idris2_newNamedConstructor).
typedef struct {
  Idris2_header header;
  uint16_t total;
  int16_t tag;
  Idris2_Value *args[];
} Idris2_Constructor;
#define idris2_constructorName(c)                                              \
  ((char const *)((Idris2_Constructor *)(c))->args[((Idris2_Constructor *)(c))->total])

// A constructor without arguments, with the layout of Idris2_Constructor.
typedef struct {
  Idris2_header header;
  uint16_t total;
  int16_t tag;
} Idris2_NullaryConstructor;

typedef struct {
  Idris2_header header;
  // function type depends on arity, see idris2_dispatch
  void *f;
  // (16 bits each, as many arguments as Idris2_Constructor has fields: they
  // fit in the room that the alignment of args leaves, the closure is not
  // bigger than with 8 bits.)
  uint16_t arity;
  uint16_t filled; // length of args.
  Idris2_Value *args[];
} Idris2_Closure;

// Static values of the generated code (see `StaticVal` in RefC.idr): data of
// the program, in read only memory, that is never allocated nor freed.  Like
// the other statically allocated values, they are immortal.
//
// A closure of the function `fn`, which takes `ar` arguments, without any
// argument yet.  It has no room for arguments: applying it makes a call, or
// another closure (see runtime.c).
#define IDRIS2_STATIC_CLOSURE(name, fn, ar)                                    \
  IDRIS2_UNUSED static const Idris2_Closure name = {                           \
      IDRIS2_STOCKVAL(CLOSURE_TAG), (void *)(fn), ar, 0}

// A constructor with the tag `t` and `n` fields, which are static values too.
#define IDRIS2_STATIC_CONSTRUCTOR(name, n, t, ...)                             \
  IDRIS2_UNUSED static const struct {                                          \
    Idris2_header header;                                                      \
    uint16_t total;                                                            \
    int16_t tag;                                                               \
    Idris2_Value *args[n];                                                     \
  } name = {IDRIS2_STOCKVAL(CONSTRUCTOR_TAG), n, t, {__VA_ARGS__}}

typedef struct {
  Idris2_header header;
  // Guards `v` when the IORef is shared (see prim.h).
  Idris2_SpinLock lock;
  Idris2_Value *v;
} Idris2_IORef;

typedef struct {
  Idris2_header header;
  void *p;
} Idris2_Pointer;

typedef struct {
  Idris2_header header;
  Idris2_Pointer *p;
  Idris2_Closure *onCollectFct;
} Idris2_GCPointer;

typedef struct {
  Idris2_header header;
  // Guards the elements when the array is shared (see prim.h).
  Idris2_SpinLock lock;
  int capacity;
  // The layout of the elements (see Data.IOArray.Flat): 0 for values, one
  // per slot of `arr`; otherwise the slots of an `IOArray` (`Maybe` of the
  // elements) inline, IDRIS2_SLOT_SIZE(layout) bytes each, from `arr`, which
  // then holds no value (see prim.h).
  uint64_t layout;
  Idris2_Value **arr;
} Idris2_Array;

typedef struct {
  Idris2_header header;
  Buffer *buffer;
} Idris2_Buffer;

// ---------------------------------------------------------------------------
// Concurrency
//
// The RefC backend implements its own "green threads": user level threads
// that the scheduler in threads.c runs on a pool of OS threads.  The
// synchronisation objects below are therefore implemented in terms of green
// threads rather than in terms of OS threads.  Each one has a spin lock,
// which guards its state.
// ---------------------------------------------------------------------------

// A green thread.  Its definition is private to threads.c.
typedef struct Idris2_Thread Idris2_Thread;

// A queue of green threads waiting for an event.  The links are kept in the
// waiting threads themselves (a thread can only wait on one thing at a time).
typedef struct {
  Idris2_Thread *head;
  Idris2_Thread *tail;
} Idris2_WaitQueue;

// The handle returned by `fork` and accepted by `threadWait`.  It outlives
// the thread: the threads waiting for the thread to finish wait in the
// handle, and `finished` tells that it is done.
typedef struct {
  Idris2_header header;
  Idris2_SpinLock lock;
  int finished;
  Idris2_WaitQueue joiners;
  int64_t id;
} Idris2_ThreadID;

// Mutexes are recursive, like the ones of the Scheme backends.  `state` is
// 0 when the mutex is free, 1 when it is held, and 2 when it is held and
// threads may be waiting for it (see concurrency.c); the owner is the thread
// `owner`, which holds it `depth` times.  `lock` guards the waiting threads.
typedef struct {
  Idris2_header header;
  Idris2_SpinLock lock;
  int state;
  // A thread waited too long for it: the next release hands it over to the
  // first waiting thread (see refc_mutexRelease).
  int starving;
  int owner_worker; // the worker that the owner ran on when it got it
  int64_t owner;    // -1 when nobody holds it
  int64_t depth;
  Idris2_WaitQueue waiters;
} Idris2_Mutex;

typedef struct {
  Idris2_header header;
  Idris2_SpinLock lock;
  Idris2_WaitQueue waiters;
} Idris2_Condition;

typedef struct {
  Idris2_header header;
  Idris2_SpinLock lock;
  int64_t count;
  Idris2_WaitQueue waiters;
} Idris2_Semaphore;

typedef struct {
  Idris2_header header;
  Idris2_SpinLock lock;
  int64_t count;
  int64_t num_threads;
  Idris2_WaitQueue waiters;
} Idris2_Barrier;

// A channel holds at most one value, like the channels of the Chez backend:
// `channelPut` waits for the slot to be empty, `channelGet` waits for it to
// be full.  `full` is needed because some values (such as the unit value)
// are represented by NULL at runtime.
typedef struct {
  Idris2_header header;
  Idris2_SpinLock lock;
  int full;
  Idris2_Value *value;
  Idris2_WaitQueue readers;
  Idris2_WaitQueue writers;
} Idris2_Channel;

