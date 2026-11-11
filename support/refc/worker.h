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
  struct Idris2_Page *nextAvailable; // in the available list of the class
  int available;                     // in that list, or the current page
  struct Idris2_Worker *owner;       // the worker that allocates from it
  unsigned cls;                      // the size class of its values
} Idris2_Page;

typedef struct {
  Idris2_Page *current;   // the page that the class allocates from
  Idris2_Page *available; // pages with free values, besides the current one
} Idris2_SizeClass;

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
  Idris2_PendingTailCall tailcall;
  // Set when the thread that runs has run for long while others wait for
  // the worker: it yields at its next safepoint (see IDRIS2_SAFEPOINT).
  int preempt;
  // The scheduler of the worker (see threads.c).
  void *sched;
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
