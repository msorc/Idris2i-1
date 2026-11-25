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
// is why the worker is found with idris2i_1_worker() every time: unlike a plain
// thread local variable, whose address the C compiler may keep in a register
// across a call, idris2i_1_worker() reads the thread pointer again on every use.
// ---------------------------------------------------------------------------

#include "_datatypes.h"

#include <stddef.h>
#include <stdint.h>

#if defined(_WIN32) || defined(__wasi__) || defined(__EMSCRIPTEN__)
#define IDRIS2I_1_GREEN_THREADS 0
#elif defined(__unix__) || defined(__APPLE__)
#define IDRIS2I_1_GREEN_THREADS 1
#else
// Unknown platform: assume that it does not have the POSIX context switching
// API (nor POSIX threads).
#define IDRIS2I_1_GREEN_THREADS 0
#endif

// Green threads on several OS threads.  Define IDRIS2I_1_SINGLE_WORKER to run
// every green thread on the main OS thread.
#if IDRIS2I_1_GREEN_THREADS && !defined(IDRIS2I_1_SINGLE_WORKER)
#define IDRIS2I_1_MULTICORE 1
#else
#define IDRIS2I_1_MULTICORE 0
#endif

// ---------------------------------------------------------------------------
// The allocator (see memoryManagement.c)
// ---------------------------------------------------------------------------

#define IDRIS2I_1_ALLOC_UNIT 8
#define IDRIS2I_1_ALLOC_CLASSES 32 /* values of up to 256 bytes */
#define IDRIS2I_1_PAGE_SIZE ((size_t)64 * 1024)

typedef struct Idris2i_1_FreeValue {
  struct Idris2i_1_FreeValue *next;
} Idris2i_1_FreeValue;

struct Idris2i_1_Worker;

typedef struct Idris2i_1_Page {
  Idris2i_1_FreeValue *free; // freed values of this page
  char *bump;             // the values after this one were never allocated
  char *end;
  // The values of the page that are allocated, freed values that another
  // worker has not handed back yet included.  Only right once the page is
  // not the current one of its class any more (see memoryManagement.c).
  uint32_t live;
  int available; // in the available list of the class, or the current page
  // In the available list of the class, or in a list of empty pages of the
  // worker (nextAvailable only).
  struct Idris2i_1_Page *nextAvailable;
  struct Idris2i_1_Page *prevAvailable;
  struct Idris2i_1_Worker *owner; // the worker that allocates from it
  unsigned cls;                // the size class of its values (0: empty)
  int decommitted;             // its memory was given back to the system
  struct Idris2i_1_Page *nextPage; // in the list of every page
} Idris2i_1_Page;

typedef struct {
  Idris2i_1_Page *current;   // the page that the class allocates from
  Idris2i_1_Page *available; // pages with free values, besides the current one
} Idris2i_1_SizeClass;

// ---------------------------------------------------------------------------
// Statistics
//
// Compiled with -DIDRIS2I_1_REFC_STATS (both the support library and the
// generated code, see refc.rst), the runtime counts what the allocator and
// the reference counting do; IDRIS2I_1_REFC_MEMSTATS=1 prints the counts at
// exit.  Without it, IDRIS2I_1_STAT does nothing.  The counters are in the
// worker either way, so that the layout of the worker does not depend on
// the flag.  Only the worker that owns them writes them.
// ---------------------------------------------------------------------------

// The kinds of value that the counters tell apart.
#define IDRIS2I_1_KIND_CONSTRUCTOR 0
#define IDRIS2I_1_KIND_CLOSURE 1
#define IDRIS2I_1_KIND_STRING 2
#define IDRIS2I_1_KIND_NUMBER 3 // a boxed Int32, Int64, Bits32, Bits64, Integer, Double
#define IDRIS2I_1_KIND_OTHER 4  // arrays, IORefs, pointers, buffers, ...
#define IDRIS2I_1_KINDS 5

static inline unsigned idris2i_1_kindOfTag(unsigned tag) {
  switch (tag) {
  case CONSTRUCTOR_TAG:
    return IDRIS2I_1_KIND_CONSTRUCTOR;
  case CLOSURE_TAG:
    return IDRIS2I_1_KIND_CLOSURE;
  case STRING_TAG:
    return IDRIS2I_1_KIND_STRING;
  case BITS32_TAG:
  case BITS64_TAG:
  case INT32_TAG:
  case INT64_TAG:
  case INTEGER_TAG:
  case DOUBLE_TAG:
    return IDRIS2I_1_KIND_NUMBER;
  default:
    return IDRIS2I_1_KIND_OTHER;
  }
}

// What the operations on references (taking one, dropping one) found.  Every
// operation is in exactly one of `null` and `unboxed` (nothing to do),
// `immortal` (statically allocated values, and the constants of the program:
// nothing is written; `immortalStatic` of them are static), or `real` (the
// header is read and written; `shared` of them are atomic), the last two by
// kind of value.  An operation on a count that overflowed (see
// IDRIS2I_1_VP_REFCOUNTER_OVERFLOW) is real.
typedef struct {
  uint64_t null, unboxed, immortalStatic;
  uint64_t immortal[IDRIS2I_1_KINDS];
  uint64_t real[IDRIS2I_1_KINDS];
  uint64_t shared;
} Idris2i_1_RcCounts;

// How a closure was applied (see runtime.c).
#define IDRIS2I_1_APPLY_IN_PLACE 0     // argument stored in the closure
#define IDRIS2I_1_APPLY_SATURATED 1    // a unique closure called
#define IDRIS2I_1_APPLY_COPIED 2       // a closure with other references called
#define IDRIS2I_1_APPLY_UNDER_COPY 3   // partial application of a closure copy
#define IDRIS2I_1_APPLY_SHARED 4       // a shared closure called
#define IDRIS2I_1_APPLY_KINDS 5

typedef struct {
  uint64_t allocs[IDRIS2I_1_ALLOC_CLASSES + 1];
  uint64_t frees[IDRIS2I_1_ALLOC_CLASSES + 1];
  uint64_t largeAllocs, largeFrees;
  uint64_t pagesCreated;
  uint64_t pagesEmptied;     // pages that had no value left
  uint64_t pagesReused;      // empty pages taken again (for any class)
  uint64_t pagesDecommitted; // empty pages that gave their memory back
  uint64_t pagesToPool;      // times an idle worker gave its pages to others
  uint64_t remoteFreesReceived;
  uint64_t overflows; // counts that went into the side table (see
                      // IDRIS2I_1_VP_REFCOUNTER_OVERFLOW)
  // Taking a reference (idris2i_1_newReference), dropping one where the code
  // asks (idris2i_1_removeReference, idris2i_1_dropSharedReference, ...), and
  // dropping the one that a value being released holds on a field (see
  // releaseOne).
  Idris2i_1_RcCounts dups, drops, fieldDrops;
  // Values released because their last reference was dropped (and freed
  // with their fields released), by kind.
  uint64_t released[IDRIS2I_1_KINDS];
  // Every value freed (idris2i_1_freeValue: also the cells that the code frees
  // when its uniqueness test succeeds), by kind and by size class (0: large).
  uint64_t freedKind[IDRIS2I_1_KINDS][IDRIS2I_1_ALLOC_CLASSES + 1];
  // Values made, by kind (the others are counted by size only), and the
  // bytes of the large ones (those of the others: the size of their class).
  uint64_t allocKind[IDRIS2I_1_KINDS];
  uint64_t largeBytes;
  // Uniqueness tests (idris2i_1_isUnique and the tests of closures that the
  // runtime makes) by kind of value: [kind][0] failed, [kind][1] succeeded.
  uint64_t unique[IDRIS2I_1_KINDS][2];
  uint64_t reuseHit, reuseMiss;   // a cell kept for a constructor, or not
  uint64_t apply[IDRIS2I_1_APPLY_KINDS];
  uint32_t releaseDepth, maxReleaseDepth; // nesting of idris2i_1_releaseValue
} Idris2i_1_Stats;

// ---------------------------------------------------------------------------
// Tail calls (see runtime.h)
// ---------------------------------------------------------------------------

#define IDRIS2I_1_MAX_TAILCALL_ARGS 16
typedef struct {
  void *f;
  uint8_t arity;
  Idris2i_1_Value *args[IDRIS2I_1_MAX_TAILCALL_ARGS];
} Idris2i_1_PendingTailCall;

// ---------------------------------------------------------------------------
// The worker
// ---------------------------------------------------------------------------

typedef struct Idris2i_1_Worker {
  Idris2i_1_SizeClass classes[IDRIS2I_1_ALLOC_CLASSES + 1];
  // The pages of the worker that hold no value, for any class (at most
  // idris2i_1_keepPages; the others go to a pool of the workers, see
  // memoryManagement.c).
  Idris2i_1_Page *emptyPages;
  int nEmpty;
  Idris2i_1_PendingTailCall tailcall;
  // Set when the thread that runs has run for long while others wait for
  // the worker: it yields at its next safepoint (see IDRIS2I_1_SAFEPOINT).
  int preempt;
  // The scheduler of the worker (see threads.c).
  void *sched;
  Idris2i_1_Stats stats;
  // The values of the pages of this worker that other workers freed: they
  // go back to their pages the next time this worker needs a page.  (On a
  // cache line of its own, as other workers write it.)
  Idris2i_1_FreeValue *remoteFree __attribute__((aligned(64)));
  char padding[64 - sizeof(void *)];
} Idris2i_1_Worker;

// The worker of the main OS thread.  It is the only one until the first
// `fork`.
extern Idris2i_1_Worker idris2i_1_mainWorker;

#if IDRIS2I_1_MULTICORE
extern __thread Idris2i_1_Worker *idris2i_1_tlsWorker;
// An out of line idris2i_1_worker(), for the platforms without the inline
// version below.
Idris2i_1_Worker *idris2i_1_workerSlow(void);

static inline Idris2i_1_Worker *idris2i_1_worker(void) {
  Idris2i_1_Worker *w;
#if defined(__x86_64__) && defined(__ELF__) && defined(__GNUC__)
  // `volatile` keeps the compiler from reusing the result across a context
  // switch.
#if defined(__PIC__) && !defined(__PIE__)
  // Code that may go into a shared library (the runtime itself, and a
  // program built as a library, which is compiled with -fpic): the initial
  // exec TLS model, which works in executables and shared libraries alike.
  __asm__ volatile("movq idris2i_1_tlsWorker@gottpoff(%%rip), %0\n\t"
                   "movq %%fs:(%0), %0"
                   : "=r"(w));
#else
  // Code for an executable, which has the variable (the runtime is linked
  // into it statically): the local exec model, one instruction.
  __asm__ volatile("movq %%fs:idris2i_1_tlsWorker@tpoff, %0" : "=r"(w));
#endif
#elif defined(__aarch64__) && defined(__ELF__) && defined(__GNUC__)
  void *offset;
  __asm__ volatile("mrs %0, tpidr_el0\n\t"
                   "adrp %1, :gottprel:idris2i_1_tlsWorker\n\t"
                   "ldr %1, [%1, #:gottprel_lo12:idris2i_1_tlsWorker]\n\t"
                   "ldr %0, [%0, %1]"
                   : "=r"(w), "=&r"(offset));
#else
  w = idris2i_1_workerSlow();
#endif
  return w;
}
#else
#define idris2i_1_worker() (&idris2i_1_mainWorker)
#endif

// The workers, for the reports at exit (see memoryManagement.c).
int idris2i_1_workerCount(void);
Idris2i_1_Worker *idris2i_1_workerAt(int i);

#ifdef IDRIS2I_1_REFC_STATS
#define IDRIS2I_1_STAT(field) ((void)(++idris2i_1_worker()->stats.field))
// An operation on the reference of the value `v`, which `set` (dups, drops or
// fieldDrops) counts: the value is a real one (non NULL and not unboxed).
#define IDRIS2I_1_STAT_REAL(set, v)                                               \
  ((void)(++idris2i_1_worker()                                                    \
              ->stats.set.real[idris2i_1_kindOfTag(((Idris2i_1_Value *)(v))->header.tag)]))
#define IDRIS2I_1_STAT_SHARED(set) ((void)(++idris2i_1_worker()->stats.set.shared))
#define IDRIS2I_1_STAT_NULL_OR_UNBOXED(set, v)                                    \
  ((void)((v) ? ++idris2i_1_worker()->stats.set.unboxed                           \
              : ++idris2i_1_worker()->stats.set.null))
#define IDRIS2I_1_STAT_IMMORTAL(set, v)                                           \
  ((void)(++idris2i_1_worker()                                                    \
              ->stats.set.immortal[idris2i_1_kindOfTag(                           \
                  ((Idris2i_1_Value *)(v))->header.tag)],                         \
          (((v)->header.reserved & IDRIS2I_1_STATIC_FLAG)                         \
               ? ++idris2i_1_worker()->stats.set.immortalStatic                   \
               : 0)))
// A uniqueness test of the value `v`, which gave `u`.
#define IDRIS2I_1_STAT_UNIQUE(v, u)                                               \
  ((void)(++idris2i_1_worker()                                                    \
              ->stats.unique[idris2i_1_kindOfTag(                                 \
                  ((Idris2i_1_Value *)(v))->header.tag)][(u) != 0]))
#define IDRIS2I_1_STAT_KIND(field, kind) ((void)(++idris2i_1_worker()->stats.field[kind]))
#else
#define IDRIS2I_1_STAT(field) ((void)0)
#define IDRIS2I_1_STAT_REAL(set, v) ((void)0)
#define IDRIS2I_1_STAT_SHARED(set) ((void)0)
#define IDRIS2I_1_STAT_NULL_OR_UNBOXED(set, v) ((void)0)
#define IDRIS2I_1_STAT_IMMORTAL(set, v) ((void)0)
#define IDRIS2I_1_STAT_UNIQUE(v, u) ((void)0)
#define IDRIS2I_1_STAT_KIND(field, kind) ((void)0)
#endif

// Is a second worker running?  Until then, the values never need atomic
// reference counting.
extern int idris2i_1_multicoreStarted;

// ---------------------------------------------------------------------------
// Spin locks, for the short critical sections of the runtime
// ---------------------------------------------------------------------------

static inline void idris2i_1_cpuRelax(void) {
#if defined(__x86_64__) || defined(__i386__)
  __asm__ volatile("pause");
#elif defined(__aarch64__)
  __asm__ volatile("yield");
#endif
}

void idris2i_1_spinLockSlow(Idris2i_1_SpinLock *lock);

static inline void idris2i_1_spinLock(Idris2i_1_SpinLock *lock) {
#if IDRIS2I_1_MULTICORE
  if (__atomic_exchange_n(lock, 1, __ATOMIC_ACQUIRE))
    idris2i_1_spinLockSlow(lock);
#else
  (void)lock;
#endif
}

static inline void idris2i_1_spinUnlock(Idris2i_1_SpinLock *lock) {
#if IDRIS2I_1_MULTICORE
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
extern int idris2i_1_preemptPending;
#if defined(__GNUC__)
__attribute__((cold))
#endif
void idris2i_1_preemptYield(void);

#if IDRIS2I_1_MULTICORE
#define IDRIS2I_1_SAFEPOINT()                                                     \
  do {                                                                         \
    if (__builtin_expect(                                                      \
            __atomic_load_n(&idris2i_1_preemptPending, __ATOMIC_RELAXED), 0))     \
      idris2i_1_preemptYield();                                                   \
  } while (0)
#else
#define IDRIS2I_1_SAFEPOINT()                                                     \
  do {                                                                         \
  } while (0)
#endif
