#pragma once

// ---------------------------------------------------------------------------
// Workers
//
// The green threads of a RefC program (see threads.c) run on a pool of
// "workers": OS threads, one per processor by default.  The state that the
// generated code needs at every step lives in the worker that runs it: the
// allocator (see memoryManagement.c) and the pending tail call (see
// runtime.h).
//
// A green thread may move to another worker whenever it blocks, so a pointer
// to the current worker must not be kept across a call that may block.  This
// is why the worker is found with idris2_worker() every time: unlike a plain
// thread local variable, whose address the C compiler may keep in a register
// across a call, idris2_worker() reads the thread pointer again on every use.
// ---------------------------------------------------------------------------

#include "_datatypes.h"

#include <stddef.h>
#include <stdint.h>

#if defined(_WIN32) || defined(__wasi__) || defined(__EMSCRIPTEN__)
#define IDRIS2_GREEN_THREADS 0
#elif defined(__unix__) || defined(__APPLE__)
#define IDRIS2_GREEN_THREADS 1
#else
// Unknown platform: assume that it does not have the POSIX context switching
// API (nor POSIX threads).
#define IDRIS2_GREEN_THREADS 0
#endif

// Green threads on several OS threads.  Define IDRIS2_SINGLE_WORKER to run
// every green thread on the main OS thread.
#if IDRIS2_GREEN_THREADS && !defined(IDRIS2_SINGLE_WORKER)
#define IDRIS2_MULTICORE 1
#else
#define IDRIS2_MULTICORE 0
#endif

// ---------------------------------------------------------------------------
// The allocator (see memoryManagement.c)
// ---------------------------------------------------------------------------

#define IDRIS2_ALLOC_UNIT 8
#define IDRIS2_ALLOC_CLASSES 32 /* values of up to 256 bytes */
#define IDRIS2_PAGE_SIZE ((size_t)64 * 1024)

typedef struct Idris2_FreeValue {
  struct Idris2_FreeValue *next;
} Idris2_FreeValue;

struct Idris2_Worker;

typedef struct Idris2_Page {
  Idris2_FreeValue *free; // freed values of this page
  char *bump;             // the values after this one were never allocated
  char *end;
  // The values of the page that are allocated, freed values that another
  // worker has not handed back yet included.  Only right once the page is
  // not the current one of its class any more (see memoryManagement.c).
  uint32_t live;
  int available; // in the available list of the class, or the current page
  // In the available list of the class, or in a list of empty pages of the
  // worker (nextAvailable only).
  struct Idris2_Page *nextAvailable;
  struct Idris2_Page *prevAvailable;
  struct Idris2_Worker *owner; // the worker that allocates from it
  unsigned cls;                // the size class of its values (0: empty)
  int decommitted;             // its memory was given back to the system
  struct Idris2_Page *nextPage; // in the list of every page
} Idris2_Page;

typedef struct {
  Idris2_Page *current;   // the page that the class allocates from
  Idris2_Page *available; // pages with free values, besides the current one
} Idris2_SizeClass;

// ---------------------------------------------------------------------------
// Statistics
//
// Compiled with -DIDRIS2_REFC_STATS (both the support library and the
// generated code, see refc.rst), the runtime counts what the allocator and
// the reference counting do; IDRIS2_REFC_MEMSTATS=1 prints the counts at
// exit.  Without it, IDRIS2_STAT does nothing.  The counters are in the
// worker either way, so that the layout of the worker does not depend on
// the flag.  Only the worker that owns them writes them.
// ---------------------------------------------------------------------------

// The kinds of value that the counters tell apart.
#define IDRIS2_KIND_CONSTRUCTOR 0
#define IDRIS2_KIND_CLOSURE 1
#define IDRIS2_KIND_STRING 2
#define IDRIS2_KIND_NUMBER 3 // a boxed Int32, Int64, Bits32, Bits64, Integer, Double
#define IDRIS2_KIND_OTHER 4  // arrays, IORefs, pointers, buffers, ...
#define IDRIS2_KINDS 5

static inline unsigned idris2_kindOfTag(unsigned tag) {
  switch (tag) {
  case CONSTRUCTOR_TAG:
    return IDRIS2_KIND_CONSTRUCTOR;
  case CLOSURE_TAG:
    return IDRIS2_KIND_CLOSURE;
  case STRING_TAG:
    return IDRIS2_KIND_STRING;
  case BITS32_TAG:
  case BITS64_TAG:
  case INT32_TAG:
  case INT64_TAG:
  case INTEGER_TAG:
  case DOUBLE_TAG:
    return IDRIS2_KIND_NUMBER;
  default:
    return IDRIS2_KIND_OTHER;
  }
}

// What the operations on references (taking one, dropping one) found.  Every
// operation is in exactly one of `null` and `unboxed` (nothing to do),
// `immortal` (statically allocated values, and the constants of the program:
// nothing is written; `immortalStatic` of them are static), or `real` (the
// header is read and written; `shared` of them are atomic), the last two by
// kind of value.  An operation on a count that overflowed (see
// IDRIS2_VP_REFCOUNTER_OVERFLOW) is real.
typedef struct {
  uint64_t null, unboxed, immortalStatic;
  uint64_t immortal[IDRIS2_KINDS];
  uint64_t real[IDRIS2_KINDS];
  uint64_t shared;
} Idris2_RcCounts;

// How a closure was applied (see runtime.c).
#define IDRIS2_APPLY_IN_PLACE 0     // argument stored in the closure
#define IDRIS2_APPLY_SATURATED 1    // a unique closure called
#define IDRIS2_APPLY_COPIED 2       // a closure with other references called
#define IDRIS2_APPLY_UNDER_COPY 3   // partial application of a closure copy
#define IDRIS2_APPLY_SHARED 4       // a shared closure called
#define IDRIS2_APPLY_KINDS 5

typedef struct {
  uint64_t allocs[IDRIS2_ALLOC_CLASSES + 1];
  uint64_t frees[IDRIS2_ALLOC_CLASSES + 1];
  uint64_t largeAllocs, largeFrees;
  uint64_t pagesCreated;
  uint64_t pagesEmptied;     // pages that had no value left
  uint64_t pagesReused;      // empty pages taken again (for any class)
  uint64_t pagesDecommitted; // empty pages that gave their memory back
  uint64_t pagesToPool;      // times an idle worker gave its pages to others
  uint64_t remoteFreesReceived;
  uint64_t overflows; // counts that went into the side table (see
                      // IDRIS2_VP_REFCOUNTER_OVERFLOW)
  // Taking a reference (idris2_newReference), dropping one where the code
  // asks (idris2_removeReference, idris2_dropSharedReference, ...), and
  // dropping the one that a value being released holds on a field (see
  // releaseOne).
  Idris2_RcCounts dups, drops, fieldDrops;
  // Values released because their last reference was dropped (and freed
  // with their fields released), by kind.
  uint64_t released[IDRIS2_KINDS];
  // Every value freed (idris2_freeValue: also the cells that the code frees
  // when its uniqueness test succeeds), by kind and by size class (0: large).
  uint64_t freedKind[IDRIS2_KINDS][IDRIS2_ALLOC_CLASSES + 1];
  // Values made, by kind (the others are counted by size only), and the
  // bytes of the large ones (those of the others: the size of their class).
  uint64_t allocKind[IDRIS2_KINDS];
  uint64_t largeBytes;
  // Uniqueness tests (idris2_isUnique and the tests of closures that the
  // runtime makes) by kind of value: [kind][0] failed, [kind][1] succeeded.
  uint64_t unique[IDRIS2_KINDS][2];
  uint64_t reuseHit, reuseMiss;   // a cell kept for a constructor, or not
  uint64_t apply[IDRIS2_APPLY_KINDS];
  uint32_t releaseDepth, maxReleaseDepth; // nesting of idris2_releaseValue
} Idris2_Stats;

// ---------------------------------------------------------------------------
// Tail calls (see runtime.h)
// ---------------------------------------------------------------------------

#define IDRIS2_MAX_TAILCALL_ARGS 16
typedef struct {
  void *f;
  uint8_t arity;
  Idris2_Value *args[IDRIS2_MAX_TAILCALL_ARGS];
} Idris2_PendingTailCall;

// ---------------------------------------------------------------------------
// The worker
// ---------------------------------------------------------------------------

typedef struct Idris2_Worker {
  Idris2_SizeClass classes[IDRIS2_ALLOC_CLASSES + 1];
  // The pages of the worker that hold no value, for any class (at most
  // idris2_keepPages; the others go to a pool of the workers, see
  // memoryManagement.c).
  Idris2_Page *emptyPages;
  int nEmpty;
  Idris2_PendingTailCall tailcall;
  // Set when the thread that runs has run for long while others wait for
  // the worker: it yields at its next safepoint (see IDRIS2_SAFEPOINT).
  int preempt;
  // The scheduler of the worker (see threads.c).
  void *sched;
  Idris2_Stats stats;
  // The values of the pages of this worker that other workers freed: they
  // go back to their pages the next time this worker needs a page.  (On a
  // cache line of its own, as other workers write it.)
  Idris2_FreeValue *remoteFree __attribute__((aligned(64)));
  char padding[64 - sizeof(void *)];
} Idris2_Worker;

// The worker of the main OS thread.  It is the only one until the first
// `fork`.
extern Idris2_Worker idris2_mainWorker;

#if IDRIS2_MULTICORE
extern __thread Idris2_Worker *idris2_tlsWorker;
// An out of line idris2_worker(), for the platforms without the inline
// version below.
Idris2_Worker *idris2_workerSlow(void);

static inline Idris2_Worker *idris2_worker(void) {
  Idris2_Worker *w;
#if defined(__x86_64__) && defined(__ELF__) && defined(__GNUC__)
  // The initial exec TLS model, which works in executables and shared
  // libraries alike.  `volatile` keeps the compiler from reusing the result
  // across a context switch.
  __asm__ volatile("movq idris2_tlsWorker@gottpoff(%%rip), %0\n\t"
                   "movq %%fs:(%0), %0"
                   : "=r"(w));
#elif defined(__aarch64__) && defined(__ELF__) && defined(__GNUC__)
  void *offset;
  __asm__ volatile("mrs %0, tpidr_el0\n\t"
                   "adrp %1, :gottprel:idris2_tlsWorker\n\t"
                   "ldr %1, [%1, #:gottprel_lo12:idris2_tlsWorker]\n\t"
                   "ldr %0, [%0, %1]"
                   : "=r"(w), "=&r"(offset));
#else
  w = idris2_workerSlow();
#endif
  return w;
}
#else
#define idris2_worker() (&idris2_mainWorker)
#endif

// The workers, for the reports at exit (see memoryManagement.c).
int idris2_workerCount(void);
Idris2_Worker *idris2_workerAt(int i);

#ifdef IDRIS2_REFC_STATS
#define IDRIS2_STAT(field) ((void)(++idris2_worker()->stats.field))
// An operation on the reference of the value `v`, which `set` (dups, drops or
// fieldDrops) counts: the value is a real one (non NULL and not unboxed).
#define IDRIS2_STAT_REAL(set, v)                                               \
  ((void)(++idris2_worker()                                                    \
              ->stats.set.real[idris2_kindOfTag(((Idris2_Value *)(v))->header.tag)]))
#define IDRIS2_STAT_SHARED(set) ((void)(++idris2_worker()->stats.set.shared))
#define IDRIS2_STAT_NULL_OR_UNBOXED(set, v)                                    \
  ((void)((v) ? ++idris2_worker()->stats.set.unboxed                           \
              : ++idris2_worker()->stats.set.null))
#define IDRIS2_STAT_IMMORTAL(set, v)                                           \
  ((void)(++idris2_worker()                                                    \
              ->stats.set.immortal[idris2_kindOfTag(                           \
                  ((Idris2_Value *)(v))->header.tag)],                         \
          (((v)->header.reserved & IDRIS2_STATIC_FLAG)                         \
               ? ++idris2_worker()->stats.set.immortalStatic                   \
               : 0)))
// A uniqueness test of the value `v`, which gave `u`.
#define IDRIS2_STAT_UNIQUE(v, u)                                               \
  ((void)(++idris2_worker()                                                    \
              ->stats.unique[idris2_kindOfTag(                                 \
                  ((Idris2_Value *)(v))->header.tag)][(u) != 0]))
#define IDRIS2_STAT_KIND(field, kind) ((void)(++idris2_worker()->stats.field[kind]))
#else
#define IDRIS2_STAT(field) ((void)0)
#define IDRIS2_STAT_REAL(set, v) ((void)0)
#define IDRIS2_STAT_SHARED(set) ((void)0)
#define IDRIS2_STAT_NULL_OR_UNBOXED(set, v) ((void)0)
#define IDRIS2_STAT_IMMORTAL(set, v) ((void)0)
#define IDRIS2_STAT_UNIQUE(v, u) ((void)0)
#define IDRIS2_STAT_KIND(field, kind) ((void)0)
#endif

// Is a second worker running?  Until then, the values never need atomic
// reference counting.
extern int idris2_multicoreStarted;

// ---------------------------------------------------------------------------
// Spin locks, for the short critical sections of the runtime
// ---------------------------------------------------------------------------

static inline void idris2_cpuRelax(void) {
#if defined(__x86_64__) || defined(__i386__)
  __asm__ volatile("pause");
#elif defined(__aarch64__)
  __asm__ volatile("yield");
#endif
}

void idris2_spinLockSlow(Idris2_SpinLock *lock);

static inline void idris2_spinLock(Idris2_SpinLock *lock) {
#if IDRIS2_MULTICORE
  if (__atomic_exchange_n(lock, 1, __ATOMIC_ACQUIRE))
    idris2_spinLockSlow(lock);
#else
  (void)lock;
#endif
}

static inline void idris2_spinUnlock(Idris2_SpinLock *lock) {
#if IDRIS2_MULTICORE
  __atomic_store_n(lock, 0, __ATOMIC_RELEASE);
#else
  (void)lock;
#endif
}

// ---------------------------------------------------------------------------
// Preemption
//
// Within a worker, threads run until they block.  So that a thread that
// computes for long does not keep the other threads of its worker waiting,
// the generated code has safepoints (at the back edges of its loops), where
// a thread yields when the scheduler asks it to (see threads.c).
// ---------------------------------------------------------------------------

// Set while some worker has `preempt` set: the safepoints test this global
// (one load) rather than their worker.
extern int idris2_preemptPending;
#if defined(__GNUC__)
__attribute__((cold))
#endif
void idris2_preemptYield(void);

#if IDRIS2_MULTICORE
#define IDRIS2_SAFEPOINT()                                                     \
  do {                                                                         \
    if (__builtin_expect(                                                      \
            __atomic_load_n(&idris2_preemptPending, __ATOMIC_RELAXED), 0))     \
      idris2_preemptYield();                                                   \
  } while (0)
#else
#define IDRIS2_SAFEPOINT()                                                     \
  do {                                                                         \
  } while (0)
#endif
