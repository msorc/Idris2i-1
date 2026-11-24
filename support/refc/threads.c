// ---------------------------------------------------------------------------
// Green threads for the RefC backend.
//
// Idris programs compiled by the RefC backend run as a set of "green
// threads": user level threads that run on a pool of OS threads, the
// workers (see worker.h).
//
// * The main expression runs on a large stack of its own (4GB by default on
//   64-bit systems), like in the Chez backend where the stack grows as
//   needed: much of the library is not tail recursive, so a deep stack is
//   needed to work on long lists.  The memory is only used as the stack
//   grows.
// * Every forked thread owns a stack, allocated with mmap(2) and protected
//   by a guard page, so that a stack overflow crashes the program instead of
//   silently corrupting memory.
// * Every worker has a scheduler, which runs on a stack of its own.  A
//   thread that blocks switches to the scheduler of its worker, which picks
//   the next runnable thread.
// * Switching between threads is done by a few lines of assembly on x86-64
//   and AArch64, and with swapcontext(3) elsewhere.  swapcontext saves and
//   restores the signal mask, which costs a system call per switch.
//
// Scheduling is cooperative: a worker runs a thread until it blocks, sleeps,
// forks a thread or finishes, or until it reaches a safepoint (the back edge
// of a loop) after the monitor asked it to yield, as it ran for more than
// PREEMPT_INTERVAL_NS while other threads waited for its worker.  The program ends when the main expression is
// done, like in the Chez backend.
//
// The program has a single worker, the main OS thread, until it forks its
// first thread.  Then the other workers start: one per processor, or
// IDRIS2I_1_WORKERS of them in all.  Every worker has a run queue.  A thread
// that is woken up goes to the worker that woke it up, and runs next there:
// a thread that hands a value over to another one and waits for the answer
// (a channel ping-pong, say) gives the processor to it at once, with no
// help from the operating system.  The workers that run out of threads take
// half of the run queue of another one, and when there is nothing to take,
// they sleep until a busy worker has more threads than it can run (it forks
// one, say).  The thread that runs next on a worker stays there, unless it
// has been waiting for a while: one of the sleeping workers, the
// "watcher", looks at the run queues every WATCH_INTERVAL_NS nanoseconds
// while some threads are waiting, and it wakes up for the deadlines of the
// sleeping threads.
//
// A thread that waits for a file descriptor parks too: the reactor (see
// reactor.c) wakes it up.  While threads wait for descriptors, the watcher
// waits in the poller of the reactor instead of its condition variable, the
// busy workers poll without blocking now and then, and the monitor makes a
// thread yield when nobody polled for a while (see monitor_main).
//
// A thread that blocks holds the spin lock of the object it waits for until
// it is switched out: the scheduler releases it.  So a thread can only be
// woken up (and run by another worker) once it is off its stack.  The
// deadline of a timed wait is set by the scheduler too, at the same time.
// A thread that may be woken up either by an event or by its deadline is
// claimed atomically (see `claimed`) by whichever comes first.
//
// On the platforms without the POSIX context switching API (Windows and
// WebAssembly) the program runs in a single thread, and forking a thread is
// an error.  The synchronisation objects still work there, as long as they
// do not need another thread to make progress.
// ---------------------------------------------------------------------------

#if defined(__APPLE__)
// <ucontext.h> refuses to work on macOS unless _XOPEN_SOURCE is defined, and
// _XOPEN_SOURCE hides the BSD extensions unless _DARWIN_C_SOURCE is defined.
#define _XOPEN_SOURCE 600
#define _DARWIN_C_SOURCE
#endif

#include "threads.h"
#include "backtrace.h"
#include "crash.h"
#include "memoryManagement.h"
#include "reactor.h"
#include "runtime.h"
#include "worker.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

// The hand written context switch is used on x86-64 (System V ABI, so not
// on Windows, which has no green threads anyway) and on AArch64, for ELF and
// Mach-O objects.  Define IDRIS2I_1_USE_UCONTEXT to use swapcontext(3) instead.
#if IDRIS2I_1_GREEN_THREADS && !defined(IDRIS2I_1_USE_UCONTEXT) &&                   \
    (defined(__x86_64__) || defined(__aarch64__)) &&                           \
    (defined(__ELF__) || defined(__APPLE__))
#define IDRIS2I_1_ASM_CONTEXT 1
#else
#define IDRIS2I_1_ASM_CONTEXT 0
#endif

#if IDRIS2I_1_GREEN_THREADS
#include <sys/mman.h>
#include <unistd.h>
#if !IDRIS2I_1_ASM_CONTEXT
#include <ucontext.h>
#endif
#ifndef MAP_ANONYMOUS
#define MAP_ANONYMOUS MAP_ANON
#endif
#ifndef MAP_NORESERVE
#define MAP_NORESERVE 0
#endif
// Tell Valgrind about the stacks of the green threads, when it is available,
// so that it does not mistake a context switch for a stack overflow.  The
// macros do nothing when the program does not run under Valgrind.
#if defined(__has_include)
#if __has_include(<valgrind/valgrind.h>)
#include <valgrind/valgrind.h>
#define IDRIS2I_1_HAVE_VALGRIND 1
#endif
#endif
#endif

#if IDRIS2I_1_MULTICORE
#include <errno.h>
#include <pthread.h>
#include <sched.h>
#endif

#ifdef _WIN32
#include <windows.h>
#endif

#define NO_DEADLINE ((int64_t)-1)

static void fatal(const char *message);

// ---------------------------------------------------------------------------
// Execution contexts
//
// context_make prepares a context that runs `entry` on the given stack (the
// entry function must never return); context_switch saves the current
// context into `from` and resumes `to`.
// ---------------------------------------------------------------------------

#if IDRIS2I_1_GREEN_THREADS && IDRIS2I_1_ASM_CONTEXT

// The context is just the stack pointer: the callee saved registers are
// pushed onto the stack of the thread being switched out.
typedef struct {
  void *sp;
} Context;

// void idris2i_1_context_switch(void **save_sp, void *load_sp)
void idris2i_1_context_switch(void **save_sp, void *load_sp);

#if defined(__APPLE__)
#define CTX_SYM "_idris2i_1_context_switch"
#define CTX_BEGIN                                                              \
  ".text\n"                                                                    \
  ".globl " CTX_SYM "\n"                                                       \
  ".private_extern " CTX_SYM "\n"                                              \
  ".p2align 4\n" CTX_SYM ":\n"
#define CTX_END ""
#else
#define CTX_SYM "idris2i_1_context_switch"
#define CTX_BEGIN                                                              \
  ".pushsection .text\n"                                                       \
  ".globl " CTX_SYM "\n"                                                       \
  ".hidden " CTX_SYM "\n"                                                      \
  ".type " CTX_SYM ", %function\n"                                             \
  ".p2align 4\n" CTX_SYM ":\n"
#define CTX_END ".size " CTX_SYM ", .-" CTX_SYM "\n.popsection\n"
#endif

#if defined(__x86_64__)

// Saved on the stack, from the top: the return address, rbp, rbx, r12-r15,
// and the SSE (MXCSR) and x87 control words, which are callee saved too.
__asm__(CTX_BEGIN "  pushq %rbp\n"
                  "  pushq %rbx\n"
                  "  pushq %r12\n"
                  "  pushq %r13\n"
                  "  pushq %r14\n"
                  "  pushq %r15\n"
                  "  subq $8, %rsp\n"
                  "  stmxcsr (%rsp)\n"
                  "  fnstcw 4(%rsp)\n"
                  "  movq %rsp, (%rdi)\n"
                  "  movq %rsi, %rsp\n"
                  "  ldmxcsr (%rsp)\n"
                  "  fldcw 4(%rsp)\n"
                  "  addq $8, %rsp\n"
                  "  popq %r15\n"
                  "  popq %r14\n"
                  "  popq %r13\n"
                  "  popq %r12\n"
                  "  popq %rbx\n"
                  "  popq %rbp\n"
                  "  ret\n" CTX_END);

static void context_make(Context *ctx, void *stack, size_t size,
                         void (*entry)(void)) {
  uint64_t *sp = (uint64_t *)(((uintptr_t)stack + size) & ~(uintptr_t)15);
  // `entry` is entered by a `ret`; the slot above its return address is a
  // fake return address, so that the stack is aligned as after a call.
  *--sp = 0;
  *--sp = (uint64_t)(uintptr_t)entry;
  for (int i = 0; i < 6; i++) {
    *--sp = 0; // rbp, rbx, r12-r15
  }
  // The default control words: MXCSR 0x1F80, x87 control word 0x037F.
  *--sp = UINT64_C(0x1F80) | (UINT64_C(0x037F) << 32);
  ctx->sp = sp;
}

#else /* __aarch64__ */

// A frame of 176 bytes: x19-x28, x29 (frame pointer), x30 (return address),
// d8-d15, and 16 bytes of padding to keep the stack 16 byte aligned.
__asm__(CTX_BEGIN "  sub sp, sp, #176\n"
                  "  stp x19, x20, [sp, #0]\n"
                  "  stp x21, x22, [sp, #16]\n"
                  "  stp x23, x24, [sp, #32]\n"
                  "  stp x25, x26, [sp, #48]\n"
                  "  stp x27, x28, [sp, #64]\n"
                  "  stp x29, x30, [sp, #80]\n"
                  "  stp d8, d9, [sp, #96]\n"
                  "  stp d10, d11, [sp, #112]\n"
                  "  stp d12, d13, [sp, #128]\n"
                  "  stp d14, d15, [sp, #144]\n"
                  "  mov x2, sp\n"
                  "  str x2, [x0]\n"
                  "  mov sp, x1\n"
                  "  ldp x19, x20, [sp, #0]\n"
                  "  ldp x21, x22, [sp, #16]\n"
                  "  ldp x23, x24, [sp, #32]\n"
                  "  ldp x25, x26, [sp, #48]\n"
                  "  ldp x27, x28, [sp, #64]\n"
                  "  ldp x29, x30, [sp, #80]\n"
                  "  ldp d8, d9, [sp, #96]\n"
                  "  ldp d10, d11, [sp, #112]\n"
                  "  ldp d12, d13, [sp, #128]\n"
                  "  ldp d14, d15, [sp, #144]\n"
                  "  add sp, sp, #176\n"
                  "  ret\n" CTX_END);

static void context_make(Context *ctx, void *stack, size_t size,
                         void (*entry)(void)) {
  uintptr_t top = ((uintptr_t)stack + size) & ~(uintptr_t)15;
  uint64_t *frame = (uint64_t *)(top - 176);
  memset(frame, 0, 176);
  frame[11] = (uint64_t)(uintptr_t)entry; // x30: where `ret` goes
  ctx->sp = frame;
}

#endif

static inline void context_switch(Context *from, Context *to) {
  idris2i_1_context_switch(&from->sp, to->sp);
}

#elif IDRIS2I_1_GREEN_THREADS

typedef ucontext_t Context;

static void context_make(Context *ctx, void *stack, size_t size,
                         void (*entry)(void)) {
  if (getcontext(ctx) != 0) {
    fatal("getcontext failed");
  }
  ctx->uc_stack.ss_sp = stack;
  ctx->uc_stack.ss_size = size;
  ctx->uc_link = NULL;
  makecontext(ctx, entry, 0);
}

static inline void context_switch(Context *from, Context *to) {
  if (swapcontext(from, to) != 0) {
    fatal("could not switch between green threads");
  }
}

#endif

typedef enum {
  THREAD_RUNNABLE = 0, // running, or waiting in a run queue
  THREAD_BLOCKED,      // waiting for an event and/or a deadline
  THREAD_FINISHED
} Thread_State;

struct Idris2i_1_Thread {
  int64_t id;
  Thread_State state;
  // The action of a forked thread: a `PrimIO ()`, i.e. a closure waiting for
  // its %World argument.  NULL once the thread has started.
  Idris2i_1_Closure *action;
  // The handle handed out by `fork`.  The thread owns one reference to it
  // while it runs.  NULL for the main thread.
  Idris2i_1_ThreadID *handle;
  // Thread local data, as set by `setThreadData`.
  Idris2i_1_Value *thread_data;
  // The crash boundaries of the thread (see crash.c).
  Idris2i_1_CrashState crash;
  // Link in a run queue.
  Idris2i_1_Thread *run_next;
  // The queue this thread is waiting in (if any), the lock that guards it,
  // and the link in it.
  Idris2i_1_WaitQueue *wait_queue;
  Idris2i_1_SpinLock *wait_lock;
  Idris2i_1_Thread *wait_next;
  // The deadline of a timed wait (if any), and the place in the timer heap.
  int has_deadline;
  int in_timers;
  int timed_out;
  // Set by whoever wakes up a thread with a deadline: an event or the
  // deadline (see idris2i_1_threadWakeOne and expire_timers).
  int claimed;
  int64_t deadline_ns;
  uint64_t timer_seq; // the order of the insertions, for equal deadlines
  size_t timer_index; // in `timers`, while in_timers
  // The link in the list of the expired threads (see expire_timers).
  Idris2i_1_Thread *timer_next;
#if IDRIS2I_1_GREEN_THREADS
  Context ctx;
  // The mapping holding the stack, guard page included.  NULL for the main
  // thread when it runs on the stack of the process.
  void *stack;
#ifdef IDRIS2I_1_HAVE_VALGRIND
  unsigned valgrind_stack_id;
#endif
#endif
};

// What the scheduler does once the thread that it ran has switched out.
typedef enum {
  AFTER_NOTHING = 0,
  AFTER_PARK,   // the thread blocks: set its deadline, release its lock
  AFTER_YIELD,  // the thread goes back to the run queue
  AFTER_FINISH, // the thread is done: free it
} After;

// The stacks of the finished threads are kept for reuse, up to a limit.
#define STACK_CACHE_SIZE 16

// The scheduler of a worker.
typedef struct Sched {
  Idris2i_1_Worker *worker;
  int index;
  // The thread that the worker runs, NULL while the scheduler runs, and its
  // identifier (-1 then), which other workers may read.
  Idris2i_1_Thread *current;
  int64_t current_id;
  // The number of threads that the worker started running (see monitor).
  uint64_t switches;
#if IDRIS2I_1_GREEN_THREADS
  Context ctx; // the context of the scheduler
  After after;
  Idris2i_1_SpinLock *after_lock;
  // The run queue (FIFO), and the thread to run next, which goes before the
  // queue; `lock` guards them.  `runnext_gen` changes whenever `runnext`
  // does (see runq_steal).
  Idris2i_1_SpinLock lock;
  Idris2i_1_Thread *head;
  Idris2i_1_Thread *tail;
  int64_t qlen;
  Idris2i_1_Thread *runnext;
  uint64_t runnext_gen;
  void *stack_cache[STACK_CACHE_SIZE];
  int stack_cache_count;
#endif
#if IDRIS2I_1_MULTICORE
  pthread_cond_t cond; // signalled to wake up the worker when it is parked
  int parked;          // (these are guarded by idle_lock)
  struct Sched *idle_next;
  int spinning; // looking for work in the other run queues
  int watching; // the watcher whose wait is over (see park)
  int stopped;  // for good, see idris2i_1_threadStopOthers (under idle_lock)
  int polling;  // parked in idris2i_1_reactorPoll (under idle_lock)
  // Polls for threads that it runs itself (see sched_poll).
  int local_wake;
  uint32_t random;
#endif
} Sched;

// The main thread is statically allocated, so that there is always a current
// thread, even before the scheduler starts.
static Idris2i_1_Thread main_thread;
static Sched main_sched;
Idris2i_1_Worker idris2i_1_mainWorker = {.sched = &main_sched};
static Sched main_sched = {
    .worker = &idris2i_1_mainWorker, .current = &main_thread, .current_id = 0};

int idris2i_1_multicoreStarted = 0;

#if IDRIS2I_1_MULTICORE
__thread Idris2i_1_Worker *idris2i_1_tlsWorker = &idris2i_1_mainWorker;

Idris2i_1_Worker *idris2i_1_workerSlow(void) { return idris2i_1_tlsWorker; }
#endif

static inline Sched *self(void) { return (Sched *)idris2i_1_worker()->sched; }

// The workers.  workers[0] is the main OS thread.
static Sched *main_workers[1] = {&main_sched};
static Sched **workers = main_workers;
static int n_workers = 1;

// The main thread has identifier 0.
static int64_t next_thread_id = 1;

// The number of threads that have not finished yet, the main one included.
static int64_t live_threads = 1;

// The threads with a deadline, in a 4-ary min-heap ordered by deadline (and
// then by order of insertion, so that threads with the same deadline wake
// up in FIFO order), and the earliest deadline (INT64_MAX if there is
// none).  Guarded by timer_lock.
static Idris2i_1_SpinLock timer_lock = 0;
static Idris2i_1_Thread **timers = NULL;
static size_t n_timers = 0, timers_capacity = 0;
static uint64_t timer_seq = 0;
static int64_t next_deadline = INT64_MAX;

// Do threads wait for file descriptors (see reactor.h)?  One load, so that
// a program that never waits for one pays nothing.
static inline int io_pending(void) {
  return __builtin_expect(
      __atomic_load_n(&idris2i_1_ioPending, __ATOMIC_RELAXED) != 0, 0);
}

static void fatal(const char *message) {
  fprintf(stderr, "RefC: %s\n", message);
  exit(1);
}

int idris2i_1_workerCount(void) {
  return __atomic_load_n(&n_workers, __ATOMIC_ACQUIRE);
}

Idris2i_1_Worker *idris2i_1_workerAt(int i) { return workers[i]->worker; }

int idris2i_1_workerIndex(void) { return self()->index; }


void idris2i_1_spinLockSlow(Idris2i_1_SpinLock *lock) {
  for (unsigned spins = 0;; spins++) {
    while (__atomic_load_n(lock, __ATOMIC_RELAXED)) {
      if (spins++ < 1000) {
        idris2i_1_cpuRelax();
      } else {
#if IDRIS2I_1_MULTICORE
        // The owner may have been preempted by the operating system.
        sched_yield();
#endif
      }
    }
    if (!__atomic_exchange_n(lock, 1, __ATOMIC_ACQUIRE))
      return;
  }
}

// ---------------------------------------------------------------------------
// Time
// ---------------------------------------------------------------------------

int64_t idris2i_1_monotonicNanoseconds(void) {
#ifdef _WIN32
  static LARGE_INTEGER frequency;
  LARGE_INTEGER counter;
  if (frequency.QuadPart == 0) {
    QueryPerformanceFrequency(&frequency);
  }
  QueryPerformanceCounter(&counter);
  return (int64_t)((double)counter.QuadPart * 1e9 / (double)frequency.QuadPart);
#else
  struct timespec now;
  clock_gettime(CLOCK_MONOTONIC, &now);
  return (int64_t)now.tv_sec * 1000000000 + (int64_t)now.tv_nsec;
#endif
}

int64_t idris2i_1_deadlineAfter(int64_t microseconds) {
  int64_t now = idris2i_1_monotonicNanoseconds();
  if (microseconds <= 0) {
    return now;
  }
  if (microseconds > (INT64_MAX - now) / 1000) {
    return INT64_MAX - 1;
  }
  return now + microseconds * 1000;
}

#if !IDRIS2I_1_MULTICORE
// Block the whole process until the monotonic clock reaches `deadline_ns`.
static void sleep_until(int64_t deadline_ns) {
  for (;;) {
    int64_t remaining = deadline_ns - idris2i_1_monotonicNanoseconds();
    if (remaining <= 0) {
      return;
    }
#ifdef _WIN32
    int64_t ms = (remaining + 999999) / 1000000;
    Sleep(ms > 0x7fffffff ? 0x7fffffff : (DWORD)ms);
#else
    struct timespec request;
    request.tv_sec = (time_t)(remaining / 1000000000);
    request.tv_nsec = (long)(remaining % 1000000000);
    nanosleep(&request, NULL);
#endif
  }
}
#endif

// ---------------------------------------------------------------------------
// Wait queues and timers
// ---------------------------------------------------------------------------

static void waitq_push(Idris2i_1_WaitQueue *queue, Idris2i_1_Thread *thread) {
  thread->wait_queue = queue;
  thread->wait_next = NULL;
  if (queue->tail) {
    queue->tail->wait_next = thread;
  } else {
    queue->head = thread;
  }
  queue->tail = thread;
}

static void waitq_remove(Idris2i_1_WaitQueue *queue, Idris2i_1_Thread *thread) {
  Idris2i_1_Thread *previous = NULL;
  for (Idris2i_1_Thread *t = queue->head; t; previous = t, t = t->wait_next) {
    if (t == thread) {
      if (previous) {
        previous->wait_next = t->wait_next;
      } else {
        queue->head = t->wait_next;
      }
      if (queue->tail == t) {
        queue->tail = previous;
      }
      break;
    }
  }
  thread->wait_queue = NULL;
  thread->wait_next = NULL;
}

Idris2i_1_Thread *idris2i_1_threadTakeWaiter(Idris2i_1_WaitQueue *queue) {
  Idris2i_1_Thread *thread = queue->head;
  if (thread) {
    queue->head = thread->wait_next;
    if (!queue->head) {
      queue->tail = NULL;
    }
    thread->wait_queue = NULL;
    thread->wait_next = NULL;
  }
  return thread;
}

// The timer heap is guarded by timer_lock.

static inline int timer_before(Idris2i_1_Thread *a, Idris2i_1_Thread *b) {
  return a->deadline_ns < b->deadline_ns ||
         (a->deadline_ns == b->deadline_ns && a->timer_seq < b->timer_seq);
}

static inline void timer_place(Idris2i_1_Thread *thread, size_t i) {
  timers[i] = thread;
  thread->timer_index = i;
}

static void timer_sift_up(Idris2i_1_Thread *thread, size_t i) {
  while (i > 0) {
    size_t parent = (i - 1) / 4;
    if (!timer_before(thread, timers[parent])) {
      break;
    }
    timer_place(timers[parent], i);
    i = parent;
  }
  timer_place(thread, i);
}

static void timer_sift_down(Idris2i_1_Thread *thread, size_t i) {
  for (;;) {
    size_t first = 4 * i + 1;
    if (first >= n_timers) {
      break;
    }
    size_t last = first + 4 < n_timers ? first + 4 : n_timers;
    size_t best = first;
    for (size_t c = first + 1; c < last; c++) {
      if (timer_before(timers[c], timers[best])) {
        best = c;
      }
    }
    if (!timer_before(timers[best], thread)) {
      break;
    }
    timer_place(timers[best], i);
    i = best;
  }
  timer_place(thread, i);
}

static void timer_publish(void) {
  __atomic_store_n(&next_deadline,
                   n_timers ? timers[0]->deadline_ns : INT64_MAX,
                   __ATOMIC_RELEASE);
}

// Returns 1 when the deadline is the earliest one.
static int timer_insert(Idris2i_1_Thread *thread) {
  if (n_timers == timers_capacity) {
    size_t capacity = timers_capacity ? timers_capacity * 2 : 64;
    Idris2i_1_Thread **bigger = realloc(timers, capacity * sizeof(*timers));
    if (!bigger) {
      fatal("could not allocate the timers");
    }
    timers = bigger;
    timers_capacity = capacity;
  }
  thread->timer_seq = timer_seq++;
  thread->in_timers = 1;
  timer_sift_up(thread, n_timers++);
  timer_publish();
  return timers[0] == thread;
}

static void timer_remove(Idris2i_1_Thread *thread) {
  size_t i = thread->timer_index;
  Idris2i_1_Thread *last = timers[--n_timers];
  if (last != thread) {
    // `last` takes the place of `thread`, and moves up or down from there.
    if (i > 0 && timer_before(last, timers[(i - 1) / 4])) {
      timer_sift_up(last, i);
    } else {
      timer_sift_down(last, i);
    }
  }
  thread->in_timers = 0;
  timer_publish();
}

// ---------------------------------------------------------------------------
// Run queues and idle workers
// ---------------------------------------------------------------------------

#if IDRIS2I_1_GREEN_THREADS

#if IDRIS2I_1_MULTICORE
// The parked workers wait on their condition variable with idle_lock.
static pthread_mutex_t idle_lock = PTHREAD_MUTEX_INITIALIZER;
static Sched *idle_list = NULL;
static int n_parked = 0;   // written under idle_lock
static int n_spinning = 0; // atomic
// The parked worker that wakes up for the deadlines and to look at the run
// queues, if any (guarded by idle_lock).
static Sched *watcher = NULL;
// The parked worker that blocks in the poller of the reactor, if any
// (guarded by idle_lock).  There is one at most, so that the wakeups of the
// reactor (see wakep) go to it: it may not be the watcher any more, as wakep
// may take it out of the idle list while it polls.
static Sched *in_poller = NULL;
// What the watcher saw as the next thread of every worker (see runq_steal).
static Idris2i_1_Thread **seen_runnext = NULL;
static uint64_t *seen_runnext_gen = NULL;
#endif

// How often the watcher looks at the run queues while threads wait in them.
#define WATCH_INTERVAL_NS ((int64_t)100000)

static void wakep(void);

static int64_t queued(Sched *s) {
  return __atomic_load_n(&s->qlen, __ATOMIC_RELAXED) +
         (__atomic_load_n(&s->runnext, __ATOMIC_RELAXED) ? 1 : 0);
}

static void runq_append(Sched *s, Idris2i_1_Thread *thread) {
  thread->run_next = NULL;
  if (s->tail) {
    s->tail->run_next = thread;
  } else {
    s->head = thread;
  }
  s->tail = thread;
  __atomic_store_n(&s->qlen, s->qlen + 1, __ATOMIC_RELAXED);
}

// Add a runnable thread to the run queue of `s`, or make it the next thread
// to run there.
static void runq_put(Sched *s, Idris2i_1_Thread *thread, int next) {
  Idris2i_1_Thread *kicked = NULL;
  idris2i_1_spinLock(&s->lock);
  if (next) {
    kicked = s->runnext;
    __atomic_store_n(&s->runnext, thread, __ATOMIC_RELAXED);
    s->runnext_gen++;
    if (kicked) {
      runq_append(s, kicked);
    }
  } else {
    runq_append(s, thread);
  }
  idris2i_1_spinUnlock(&s->lock);
  // A thread in the queue may be run by another worker; the next one is
  // left for this worker, which is likely to run it soon.
  if (!next || kicked) {
    wakep();
  }
}

static Idris2i_1_Thread *runq_get(Sched *s) {
  if (!__atomic_load_n(&s->runnext, __ATOMIC_RELAXED) &&
      !__atomic_load_n(&s->head, __ATOMIC_RELAXED)) {
    return NULL;
  }
  idris2i_1_spinLock(&s->lock);
  Idris2i_1_Thread *thread = s->runnext;
  if (thread) {
    __atomic_store_n(&s->runnext, NULL, __ATOMIC_RELAXED);
  } else if ((thread = s->head) != NULL) {
    __atomic_store_n(&s->head, thread->run_next, __ATOMIC_RELAXED);
    if (!s->head) {
      s->tail = NULL;
    }
    __atomic_store_n(&s->qlen, s->qlen - 1, __ATOMIC_RELAXED);
    thread->run_next = NULL;
  }
  idris2i_1_spinUnlock(&s->lock);
  return thread;
}

#if IDRIS2I_1_MULTICORE
// Take half of the run queue of `victim`: the first thread is returned, the
// others go to the run queue of `thief`.  The watcher also takes the next
// thread of a worker, when it has been waiting since its previous look.
static Idris2i_1_Thread *runq_steal(Sched *thief, Sched *victim, int watching) {
  if (!__atomic_load_n(&victim->head, __ATOMIC_RELAXED) &&
      !(watching && __atomic_load_n(&victim->runnext, __ATOMIC_RELAXED))) {
    return NULL;
  }
  Idris2i_1_Thread *first = NULL, *rest = NULL, *rest_tail = NULL;
  int64_t taken = 0;
  idris2i_1_spinLock(&victim->lock);
  int64_t take = (victim->qlen + 1) / 2;
  while (taken < take) {
    Idris2i_1_Thread *thread = victim->head;
    victim->head = thread->run_next;
    thread->run_next = NULL;
    if (!first) {
      first = thread;
    } else {
      if (rest_tail) {
        rest_tail->run_next = thread;
      } else {
        rest = thread;
      }
      rest_tail = thread;
    }
    taken++;
  }
  if (!victim->head) {
    victim->tail = NULL;
  }
  __atomic_store_n(&victim->qlen, victim->qlen - taken, __ATOMIC_RELAXED);
  if (!first && watching && victim->runnext) {
    int v = victim->index;
    if (victim->runnext == seen_runnext[v] &&
        victim->runnext_gen == seen_runnext_gen[v]) {
      first = victim->runnext;
      __atomic_store_n(&victim->runnext, NULL, __ATOMIC_RELAXED);
      victim->runnext_gen++;
    } else {
      seen_runnext[v] = victim->runnext;
      seen_runnext_gen[v] = victim->runnext_gen;
    }
  }
  idris2i_1_spinUnlock(&victim->lock);
  if (rest) {
    idris2i_1_spinLock(&thief->lock);
    if (thief->tail) {
      thief->tail->run_next = rest;
    } else {
      thief->head = rest;
    }
    thief->tail = rest_tail;
    __atomic_store_n(&thief->qlen, thief->qlen + taken - 1, __ATOMIC_RELAXED);
    idris2i_1_spinUnlock(&thief->lock);
  }
  return first;
}

static Idris2i_1_Thread *steal_work(Sched *s, int watching) {
  int n = __atomic_load_n(&n_workers, __ATOMIC_ACQUIRE);
  s->random = s->random * 1103515245u + 12345u;
  int start = (int)((s->random >> 16) % (unsigned)n);
  for (int i = 0; i < n; i++) {
    Sched *victim = workers[(start + i) % n];
    if (victim != s) {
      Idris2i_1_Thread *thread = runq_steal(s, victim, watching);
      if (thread) {
        return thread;
      }
    }
  }
  return NULL;
}

// Is there a thread that a worker could take, in a run queue (but not as
// the next thread of a worker)?
static int stealable_work(void) {
  for (int i = 0; i < n_workers; i++) {
    if (__atomic_load_n(&workers[i]->qlen, __ATOMIC_RELAXED) > 0) {
      return 1;
    }
  }
  return 0;
}

static int64_t total_queued(void) {
  int64_t total = 0;
  for (int i = 0; i < n_workers; i++) {
    total += queued(workers[i]);
  }
  return total;
}

// Wake up a parked worker, unless one is already looking for work.
static void wakep(void) {
  if (__atomic_load_n(&n_workers, __ATOMIC_RELAXED) <= 1) {
    return;
  }
  __atomic_thread_fence(__ATOMIC_SEQ_CST);
  if (__atomic_load_n(&n_parked, __ATOMIC_RELAXED) == 0) {
    return;
  }
  int zero = 0;
  if (!__atomic_compare_exchange_n(&n_spinning, &zero, 1, 0, __ATOMIC_SEQ_CST,
                                   __ATOMIC_RELAXED)) {
    return; // the spinning worker will find the work
  }
  pthread_mutex_lock(&idle_lock);
  // Rather not the watcher, which has more to do.
  Sched **link = &idle_list;
  while (*link && *link == watcher && (*link)->idle_next) {
    link = &(*link)->idle_next;
  }
  Sched *w = *link;
  if (w) {
    *link = w->idle_next;
    w->parked = 0;
    w->spinning = 1; // the spinning count is taken already
    __atomic_store_n(&n_parked, n_parked - 1, __ATOMIC_RELAXED);
    if (w == watcher) {
      watcher = NULL;
    }
    pthread_cond_signal(&w->cond);
    if (w->polling) {
      idris2i_1_reactorWakeup();
    }
  } else {
    __atomic_fetch_sub(&n_spinning, 1, __ATOMIC_SEQ_CST);
  }
  pthread_mutex_unlock(&idle_lock);
}

// A deadline was set that is earlier than the others: make sure that a
// parked worker waits for it.
static void timer_kick(void) {
  // A worker that parks writes n_parked, then reads next_deadline; we wrote
  // next_deadline, and read n_parked: without the fence (park has one too),
  // both could read the old value, and the worker would wait without the new
  // deadline while nobody wakes it up.
  __atomic_thread_fence(__ATOMIC_SEQ_CST);
  if (__atomic_load_n(&n_parked, __ATOMIC_RELAXED) == 0) {
    return;
  }
  pthread_mutex_lock(&idle_lock);
  Sched *w = watcher ? watcher : idle_list;
  if (w) {
    pthread_cond_signal(&w->cond);
    if (w->polling) {
      idris2i_1_reactorWakeup();
    }
  }
  pthread_mutex_unlock(&idle_lock);
}

// The first thread starts to wait for a file descriptor (see reactor.c), or
// a blocking call starts: a parked worker must watch the descriptors.  Like
// timer_kick: the worker that parks increments n_parked and then reads
// idris2i_1_ioPending under idle_lock, the caller incremented idris2i_1_ioPending
// and then reads n_parked, so either that worker sees the threads waiting,
// or this signals a parked worker, which looks again.
void idris2i_1_threadKickWatcher(void) { timer_kick(); }

static void timed_wait(Sched *s, int64_t deadline_ns) {
#if defined(__APPLE__)
  int64_t remaining = deadline_ns - idris2i_1_monotonicNanoseconds();
  if (remaining <= 0) {
    return;
  }
  struct timespec delay;
  delay.tv_sec = (time_t)(remaining / 1000000000);
  delay.tv_nsec = (long)(remaining % 1000000000);
  pthread_cond_timedwait_relative_np(&s->cond, &idle_lock, &delay);
#else
  struct timespec until;
  until.tv_sec = (time_t)(deadline_ns / 1000000000);
  until.tv_nsec = (long)(deadline_ns % 1000000000);
  pthread_cond_timedwait(&s->cond, &idle_lock, &until);
#endif
}

static void init_cond(pthread_cond_t *cond) {
#if defined(__APPLE__)
  pthread_cond_init(cond, NULL);
#else
  pthread_condattr_t attr;
  pthread_condattr_init(&attr);
  pthread_condattr_setclock(&attr, CLOCK_MONOTONIC);
  pthread_cond_init(cond, &attr);
  pthread_condattr_destroy(&attr);
#endif
}

// Set by idris2i_1_threadStopOthers: the workers stop instead of running a
// thread, or at the next safepoint of the one that they run.
static int stopping = 0;

int idris2i_1_threadStopping(void) {
  return __atomic_load_n(&stopping, __ATOMIC_ACQUIRE);
}

// Stop the worker for good: the thread that it runs, if any, is never
// resumed.
static void stop_worker(Sched *s) {
  pthread_mutex_lock(&idle_lock);
  s->stopped = 1;
  for (;;) {
    pthread_cond_wait(&s->cond, &idle_lock);
  }
}
#else
static void wakep(void) {}
static void timer_kick(void) {}
void idris2i_1_threadKickWatcher(void) {}
int idris2i_1_threadStopping(void) { return 0; }
#endif

static void deadlock(void) {
  fprintf(stderr,
          "RefC: deadlock detected: all the %lld remaining green "
          "thread(s) are blocked forever\n",
          (long long)__atomic_load_n(&live_threads, __ATOMIC_RELAXED));
  exit(1);
}

// Poll the reactor for the scheduler of `s`, which then runs the threads
// that the poll woke up: the first one becomes its next thread, without
// waking up another worker for it (runq_put wakes one up for the second).
static int sched_poll(Sched *s, int64_t timeout_ns) {
#if IDRIS2I_1_MULTICORE
  s->local_wake = 1;
  int woken = idris2i_1_reactorPoll(timeout_ns);
  s->local_wake = 0;
  return woken;
#else
  (void)s;
  return idris2i_1_reactorPoll(timeout_ns);
#endif
}

// Is a worker blocked in the poller (then the events go to it anyway)?
static inline int someone_polls(void) {
#if IDRIS2I_1_MULTICORE
  return __atomic_load_n(&in_poller, __ATOMIC_RELAXED) != NULL;
#else
  return 0;
#endif
}

// Wait until there may be something to do: a thread to run, or a deadline.
static void park(Sched *s) {
#if IDRIS2I_1_MULTICORE
  // (an idle worker does not need its empty pages)
  idris2i_1_releaseWorkerPages(s->worker);
  pthread_mutex_lock(&idle_lock);
  if (s->spinning) {
    s->spinning = 0;
    __atomic_fetch_sub(&n_spinning, 1, __ATOMIC_SEQ_CST);
  }
  s->parked = 1;
  s->idle_next = idle_list;
  idle_list = s;
  __atomic_store_n(&n_parked, n_parked + 1, __ATOMIC_RELAXED);
  __atomic_thread_fence(__ATOMIC_SEQ_CST);
  // A thread may have been queued after we last looked, by a worker that
  // did not wake anybody up as we were still looking (see wakep): look again
  // now that we are parked.
  if (n_workers > 1 && stealable_work()) {
    for (Sched **link = &idle_list; *link; link = &(*link)->idle_next) {
      if (*link == s) {
        *link = s->idle_next;
        break;
      }
    }
    s->parked = 0;
    __atomic_store_n(&n_parked, n_parked - 1, __ATOMIC_RELAXED);
  }
  while (s->parked) {
    int64_t deadline = __atomic_load_n(&next_deadline, __ATOMIC_ACQUIRE);
    int64_t waiting = total_queued();
    int io = io_pending();
    if (n_parked == n_workers && waiting == 0 && deadline == INT64_MAX &&
        !io) {
      // Nobody runs, and nothing can happen.
      deadlock();
    }
    int watch = waiting > 0 || deadline != INT64_MAX || io;
    if (watcher == s && !watch) {
      // Nothing to watch: give the part up, rather than keep it while
      // waiting without a timeout, as nothing would wake this worker up when
      // there is something to watch again (threads start to wait for
      // descriptors, say: idris2i_1_threadKickWatcher signals the idle workers
      // that are not watching then).
      watcher = NULL;
    }
    if (!watcher && watch) {
      watcher = s;
    }
    if (watcher != s) {
      pthread_cond_wait(&s->cond, &idle_lock);
      continue;
    }
    int64_t now = idris2i_1_monotonicNanoseconds();
    int64_t until = deadline;
    if (waiting > 0 && now + WATCH_INTERVAL_NS < until) {
      until = now + WATCH_INTERVAL_NS;
    }
    if (io && !in_poller &&
        (idris2i_1_reactorFineTimeout || until == INT64_MAX ||
         until - now >= 1000000)) {
      // Threads wait for file descriptors: wait in the poller instead, which
      // wakep and timer_kick interrupt (see idris2i_1_reactorWakeup).  The
      // threads that it wakes up go to the run queue of this worker, which
      // stays parked meanwhile, so it may be woken up while it polls.
      s->polling = 1;
      __atomic_store_n(&in_poller, s, __ATOMIC_RELAXED);
      pthread_mutex_unlock(&idle_lock);
      int woken =
          sched_poll(s, until == INT64_MAX ? -1
                        : until > now      ? until - now
                                           : 0);
      pthread_mutex_lock(&idle_lock);
      s->polling = 0;
      __atomic_store_n(&in_poller, NULL, __ATOMIC_RELAXED);
      if (watcher && watcher != s) {
        // (it may wait on its condition variable as this one polled)
        pthread_cond_signal(&watcher->cond);
      }
      if (stopping) {
        pthread_mutex_unlock(&idle_lock);
        stop_worker(s);
      }
      if (woken == 0 && s->parked &&
          idris2i_1_monotonicNanoseconds() < until) {
        continue; // woken up early, by idris2i_1_reactorWakeup
      }
    } else if (until > now) {
      timed_wait(s, until);
      if (io && s->parked) {
        // (a timeout shorter than the poller can wait, or another worker
        // is in the poller: look on every wake)
        pthread_mutex_unlock(&idle_lock);
        int woken = sched_poll(s, 0);
        pthread_mutex_lock(&idle_lock);
        if (woken > 0) {
          until = now; // run them
        }
      }
      if (s->parked && idris2i_1_monotonicNanoseconds() < until) {
        continue; // woken up early (by timer_kick, say)
      }
    }
    if (s->parked) {
      // Time to look: leave the idle list.
      for (Sched **link = &idle_list; *link; link = &(*link)->idle_next) {
        if (*link == s) {
          *link = s->idle_next;
          break;
        }
      }
      s->parked = 0;
      __atomic_store_n(&n_parked, n_parked - 1, __ATOMIC_RELAXED);
      s->watching = 1;
    }
  }
  if (watcher == s) {
    watcher = NULL;
  }
  pthread_mutex_unlock(&idle_lock);
#else
  (void)s;
  int64_t deadline = __atomic_load_n(&next_deadline, __ATOMIC_ACQUIRE);
  if (io_pending()) {
    // The only worker waits in the poller, for the descriptors and the
    // earliest deadline.  (A deadline that the poller cannot wait for
    // exactly is waited for up to a millisecond late.)
    int64_t now = idris2i_1_monotonicNanoseconds();
    idris2i_1_reactorPoll(deadline == INT64_MAX ? -1
                       : deadline > now      ? deadline - now
                                             : 0);
    return;
  }
  if (deadline == INT64_MAX) {
    deadlock();
  }
  sleep_until(deadline);
#endif
}

#endif /* IDRIS2I_1_GREEN_THREADS */

// ---------------------------------------------------------------------------
// Blocking and waking up
// ---------------------------------------------------------------------------

// Make a thread that was blocked runnable.
static void make_runnable(Idris2i_1_Thread *thread) {
  thread->state = THREAD_RUNNABLE;
#if IDRIS2I_1_GREEN_THREADS
  Sched *s = self();
  // Woken up by a running thread: it runs next on the same worker.  So does
  // a thread that the scheduler woke up as it polled for itself (see
  // sched_poll): no other worker needs waking up for it.  (A single worker
  // keeps the plain FIFO order, as there is nothing to gain.)
#if IDRIS2I_1_MULTICORE
  int local = s->current != NULL || s->local_wake;
#else
  int local = s->current != NULL;
#endif
  runq_put(s, thread,
           local && __atomic_load_n(&n_workers, __ATOMIC_RELAXED) > 1);
#endif
}

void idris2i_1_threadSchedule(Idris2i_1_Thread *thread) {
  if (thread) {
    make_runnable(thread);
  }
}

int idris2i_1_threadWakeOne(Idris2i_1_WaitQueue *queue) {
  Idris2i_1_Thread *thread;
  while ((thread = idris2i_1_threadTakeWaiter(queue)) != NULL) {
    if (thread->has_deadline) {
      int zero = 0;
      if (!__atomic_compare_exchange_n(&thread->claimed, &zero, 1, 0,
                                       __ATOMIC_ACQ_REL, __ATOMIC_ACQUIRE)) {
        continue; // its deadline expired first: it wakes up anyway
      }
      idris2i_1_spinLock(&timer_lock);
      if (thread->in_timers) {
        timer_remove(thread);
      }
      idris2i_1_spinUnlock(&timer_lock);
    }
    make_runnable(thread);
    return 1;
  }
  return 0;
}

void idris2i_1_threadWakeAll(Idris2i_1_WaitQueue *queue) {
  while (idris2i_1_threadWakeOne(queue)) {
  }
}

#if IDRIS2I_1_GREEN_THREADS
// Make the threads whose deadline has expired runnable again.  `preempted`
// says that the running thread was asked to yield for them (see
// monitor_main).
static void expire_timers(int preempted) {
  int64_t deadline = __atomic_load_n(&next_deadline, __ATOMIC_ACQUIRE);
  if (deadline == INT64_MAX) {
    return;
  }
  int64_t now = idris2i_1_monotonicNanoseconds();
  if (deadline > now) {
    return;
  }
  // The threads are claimed while timer_lock is held, that is while they are
  // still in the wait that set the deadline.  A thread that an event claims
  // first is left alone: once it is off the timer list, it may be woken up,
  // run, and wait again (with a new deadline, and `claimed` reset) at any
  // time, so it must not be touched after timer_lock is released.
  Idris2i_1_Thread *expired = NULL;
  idris2i_1_spinLock(&timer_lock);
  while (n_timers && timers[0]->deadline_ns <= now) {
    Idris2i_1_Thread *thread = timers[0];
    timer_remove(thread);
    int zero = 0;
    if (__atomic_compare_exchange_n(&thread->claimed, &zero, 1, 0,
                                    __ATOMIC_ACQ_REL, __ATOMIC_ACQUIRE)) {
      thread->timer_next = expired;
      expired = thread;
    }
  }
  idris2i_1_spinUnlock(&timer_lock);
  // Only this worker may wake up the threads that it claimed.  Like any
  // thread that a running one wakes up, they run next (see make_runnable),
  // and so they do on a single worker too when the running thread was asked
  // to yield for them: they would wait behind the threads of its run queue
  // otherwise, which a single worker does not preempt.
  Sched *s = self();
  int next = s->current != NULL &&
             (preempted || __atomic_load_n(&n_workers, __ATOMIC_RELAXED) > 1);
  while (expired) {
    Idris2i_1_Thread *thread = expired;
    expired = thread->timer_next;
    thread->timer_next = NULL;
    // It leaves its wait queue itself (see block_current).
    thread->timed_out = 1;
    thread->state = THREAD_RUNNABLE;
    runq_put(s, thread, next);
  }
}
#endif

Idris2i_1_Thread *idris2i_1_currentThread(void) { return self()->current; }

Idris2i_1_CrashState *idris2i_1_crashState(void) {
  Idris2i_1_Thread *thread = self()->current;
  return thread ? &thread->crash : NULL;
}

int64_t idris2i_1_threadId(Idris2i_1_Thread *thread) {
  return thread ? thread->id : 0;
}

// Block the current thread, see idris2i_1_threadBlockOnUntil.  `queue` and
// `lock` may be NULL (to sleep).
static int block_current(Idris2i_1_WaitQueue *queue, Idris2i_1_SpinLock *lock,
                         int64_t deadline_ns) {
  Sched *s = self();
  Idris2i_1_Thread *thread = s->current;
  thread->state = THREAD_BLOCKED;
  thread->timed_out = 0;
  thread->wait_lock = lock;
  if (queue) {
    waitq_push(queue, thread);
  }
  thread->has_deadline = deadline_ns != NO_DEADLINE;
  if (thread->has_deadline) {
    thread->deadline_ns = deadline_ns;
    thread->claimed = 0;
  }
#if IDRIS2I_1_GREEN_THREADS
  // The scheduler sets the deadline and releases the lock (see
  // scheduler_loop).
  s->after = AFTER_PARK;
  s->after_lock = lock;
  context_switch(&thread->ctx, &s->ctx);
  // (we may be on another worker now)
#else
  // There is no other thread to wake us up: only a deadline can.
  if (!thread->has_deadline) {
    fatal("deadlock detected: the only thread is blocked forever (green "
          "threads are not supported on this platform)");
  }
  sleep_until(thread->deadline_ns);
  thread->timed_out = 1;
  thread->state = THREAD_RUNNABLE;
#endif
  if (thread->timed_out && queue) {
    idris2i_1_spinLock(lock);
    if (thread->wait_queue) {
      waitq_remove(thread->wait_queue, thread);
    }
    idris2i_1_spinUnlock(lock);
  }
  thread->has_deadline = 0;
  thread->wait_lock = NULL;
  return !thread->timed_out;
}

void idris2i_1_threadBlockOn(Idris2i_1_WaitQueue *queue, Idris2i_1_SpinLock *lock) {
  block_current(queue, lock, NO_DEADLINE);
}

int idris2i_1_threadBlockOnUntil(Idris2i_1_WaitQueue *queue, Idris2i_1_SpinLock *lock,
                              int64_t deadline_ns) {
  if (deadline_ns < 0) {
    deadline_ns = 0;
  }
  return block_current(queue, lock, deadline_ns);
}

#if IDRIS2I_1_GREEN_THREADS
static void yield_current(int preempted) {
  expire_timers(preempted);
  // (not on every yield: fork yields)
  if (preempted && io_pending()) {
    idris2i_1_reactorPoll(0);
  }
  Sched *s = self();
  if (!queued(s)) {
    return; // nobody else wants to run here
  }
  Idris2i_1_Thread *thread = s->current;
  thread->state = THREAD_RUNNABLE;
  s->after = AFTER_YIELD;
  context_switch(&thread->ctx, &s->ctx);
}
#endif

void idris2i_1_threadYield(void) {
#if IDRIS2I_1_GREEN_THREADS
  yield_current(0);
#endif
}

int idris2i_1_preemptPending = 0;

void idris2i_1_preemptYield(void) {
  Idris2i_1_Worker *w = idris2i_1_worker();
  if (__atomic_load_n(&w->preempt, __ATOMIC_RELAXED)) {
    __atomic_store_n(&w->preempt, 0, __ATOMIC_RELAXED);
#if IDRIS2I_1_MULTICORE
    if (__atomic_load_n(&stopping, __ATOMIC_ACQUIRE)) {
      stop_worker(self());
    }
#endif
#if IDRIS2I_1_GREEN_THREADS
    yield_current(1);
#endif
  }
}

void idris2i_1_threadSleep(int64_t microseconds) {
  if (microseconds <= 0) {
    return;
  }
  block_current(NULL, NULL, idris2i_1_deadlineAfter(microseconds));
}

// ---------------------------------------------------------------------------
// Thread lifecycle
// ---------------------------------------------------------------------------

// Called on the stack of the thread, once its action is done.
static void thread_finish(Idris2i_1_Thread *self) {
  self->state = THREAD_FINISHED;
  __atomic_fetch_sub(&live_threads, 1, __ATOMIC_RELAXED);
  if (self->thread_data) {
    idris2i_1_removeReference(self->thread_data);
    self->thread_data = NULL;
  }
  Idris2i_1_ThreadID *handle = self->handle;
  if (handle) {
    // From now on the handle says that the thread is finished.
    idris2i_1_spinLock(&handle->lock);
    handle->finished = 1;
    idris2i_1_threadWakeAll(&handle->joiners);
    idris2i_1_spinUnlock(&handle->lock);
    self->handle = NULL;
    idris2i_1_removeReference((Idris2i_1_Value *)handle);
  }
}

#if IDRIS2I_1_GREEN_THREADS

// The size of the stacks of the forked threads.  It defaults to 8MB, which
// matches the stack of a typical process, and it can be changed with the
// IDRIS2I_1_THREAD_STACK_SIZE environment variable (in bytes).  The memory is
// reserved lazily by the operating system, so a large stack is cheap.
#define DEFAULT_STACK_SIZE ((size_t)8 * 1024 * 1024)
#define MIN_STACK_SIZE ((size_t)64 * 1024)

// The size of the stack of the main expression, which can be changed with the
// IDRIS2I_1_MAIN_STACK_SIZE environment variable (in bytes).  It is reserved
// lazily too, so it only costs address space: 4GB on 64-bit systems, 64MB on
// the others.  (Checking the type of `foo 1000000 === Just ()`, with a monadic
// `foo` that recurses a million times, needs about 1.5GB.)
#define DEFAULT_MAIN_STACK_SIZE                                                \
  (sizeof(void *) >= 8 ? (size_t)4 * 1024 * 1024 * 1024                        \
                       : (size_t)64 * 1024 * 1024)
#define SCHEDULER_STACK_SIZE ((size_t)256 * 1024)

static size_t page_size = 0;
static size_t stack_size = 0;

static void *sched_stack = NULL;

static size_t round_to_page(size_t size) {
  return (size + page_size - 1) / page_size * page_size;
}

// The stack size given by the environment variable `var`, or `dflt`.
static size_t stack_size_from_env(const char *var, size_t dflt) {
  size_t result = dflt;
  const char *env = getenv(var);
  if (env && *env) {
    char *end = NULL;
    unsigned long long size = strtoull(env, &end, 10);
    if (*end == '\0' && size >= MIN_STACK_SIZE && size <= SIZE_MAX / 2) {
      result = (size_t)size;
    } else {
      fprintf(stderr,
              "RefC: ignoring %s=%s (expected a number of bytes, at least "
              "%zu)\n",
              var, env, MIN_STACK_SIZE);
    }
  }
  return round_to_page(result);
}

static void stack_configure(void) {
  long page = sysconf(_SC_PAGESIZE);
  page_size = page > 0 ? (size_t)page : 4096;
  stack_size = stack_size_from_env("IDRIS2I_1_THREAD_STACK_SIZE",
                                   DEFAULT_STACK_SIZE);
}

int idris2i_1_threadStackGuard(const void *addr) {
  Idris2i_1_Thread *thread = self()->current;
  if (!thread || !thread->stack) {
    return 0;
  }
  // (a big frame may jump over the guard page)
  uintptr_t a = (uintptr_t)addr, guard = (uintptr_t)thread->stack;
  return a < guard + page_size && a + 65536 >= guard;
}

// Like stack_map, but NULL when the memory is not available.
static void *stack_try_map(size_t size) {
  void *mapping = mmap(NULL, size + page_size, PROT_READ | PROT_WRITE,
                       MAP_PRIVATE | MAP_ANONYMOUS | MAP_NORESERVE, -1, 0);
  if (mapping == MAP_FAILED) {
    return NULL;
  }
  (void)mprotect(mapping, page_size, PROT_NONE);
  return mapping;
}

// Map a stack of `size` bytes, preceded by a guard page.  Stacks grow
// downwards on every platform we support, so the guard page catches
// overflows.
static void *stack_map(size_t size) {
  void *mapping = stack_try_map(size);
  if (!mapping) {
    fatal("could not allocate the stack of a green thread");
  }
  return mapping;
}

static void *stack_alloc(Sched *s) {
  if (s->stack_cache_count > 0) {
    return s->stack_cache[--s->stack_cache_count];
  }
  return stack_map(stack_size);
}

static void stack_release(Sched *s, void *mapping) {
  if (s->stack_cache_count < STACK_CACHE_SIZE) {
    s->stack_cache[s->stack_cache_count++] = mapping;
  } else {
    munmap(mapping, stack_size + page_size);
  }
}

static void prepare_context(Context *ctx, void *mapping, size_t size,
                            void (*entry)(void)) {
  context_make(ctx, (char *)mapping + page_size, size, entry);
}

// Free a finished thread.  Runs on the scheduler stack, since the stack of
// the thread goes away.
static void thread_destroy(Sched *s, Idris2i_1_Thread *thread) {
#ifdef IDRIS2I_1_HAVE_VALGRIND
  VALGRIND_STACK_DEREGISTER(thread->valgrind_stack_id);
#endif
  stack_release(s, thread->stack);
  free(thread);
}

// The body of every forked thread.
static void thread_entry(void) {
  Idris2i_1_Thread *thread = self()->current;
  Idris2i_1_Closure *action = thread->action;
  thread->action = NULL;
  // This consumes the reference to the action.
  idris2i_1_removeReference(idris2i_1_run_primio(action));
  thread_finish(thread);
  // Hand control back to the scheduler for good; it frees this thread.
  Sched *s = self();
  s->after = AFTER_FINISH;
  context_switch(&thread->ctx, &s->ctx);
  fatal("a finished green thread was resumed");
}

// Find a thread to run, and wait for one if need be.
static Idris2i_1_Thread *find_work(Sched *s) {
  Idris2i_1_Thread *thread;
  // A busy worker looks at the file descriptors now and then too, as the
  // idle ones may not (see park).
  if (io_pending() && (s->switches & 63) == 0 && !someone_polls()) {
    sched_poll(s, 0);
  }
  for (;;) {
    expire_timers(0);
    thread = runq_get(s);
    if (thread) {
      break;
    }
    if (io_pending() && !someone_polls() && sched_poll(s, 0) > 0) {
      continue;
    }
#if IDRIS2I_1_MULTICORE
    if (__atomic_load_n(&n_workers, __ATOMIC_RELAXED) > 1) {
      if (!s->spinning) {
        s->spinning = 1;
        __atomic_fetch_add(&n_spinning, 1, __ATOMIC_SEQ_CST);
      }
      for (int round = 0; round < 4 && !thread; round++) {
        thread = steal_work(s, 0);
        for (int i = 0; i < 64 && !thread; i++) {
          idris2i_1_cpuRelax();
        }
      }
      if (!thread && s->watching) {
        thread = steal_work(s, 1);
      }
      s->watching = 0;
      if (thread) {
        break;
      }
      expire_timers(0);
      if ((thread = runq_get(s)) != NULL) {
        break;
      }
    }
#endif
    park(s);
  }
#if IDRIS2I_1_MULTICORE
  s->watching = 0;
  if (s->spinning) {
    s->spinning = 0;
    // The last worker that was looking for work found some: there may be
    // more, so another worker has a look.
    if (__atomic_sub_fetch(&n_spinning, 1, __ATOMIC_SEQ_CST) == 0) {
      wakep();
    }
  }
#endif
  return thread;
}

static void scheduler_loop(void) {
  Sched *s = self();
  // The scheduler of the main worker is first entered from the main thread,
  // which switched out like any other.
  Idris2i_1_Thread *thread = s->current;
  for (;;) {
    // The thread switched out, saying why.
    s->current = NULL;
    switch (thread ? s->after : AFTER_NOTHING) {
    case AFTER_PARK:
      if (thread->has_deadline) {
        idris2i_1_spinLock(&timer_lock);
        int earliest = timer_insert(thread);
        idris2i_1_spinUnlock(&timer_lock);
        if (earliest) {
          timer_kick();
        }
      }
      if (s->after_lock) {
        idris2i_1_spinUnlock(s->after_lock);
      }
      break;
    case AFTER_YIELD:
      runq_put(s, thread, 0);
      break;
    case AFTER_FINISH:
      if (thread != &main_thread) {
        thread_destroy(s, thread);
      }
      break;
    default:
      break;
    }
    s->after = AFTER_NOTHING;
    s->after_lock = NULL;
    thread = find_work(s);
#if IDRIS2I_1_MULTICORE
    if (__atomic_load_n(&stopping, __ATOMIC_ACQUIRE)) {
      stop_worker(s);
    }
#endif
    s->current = thread;
    __atomic_store_n(&s->current_id, thread->id, __ATOMIC_RELAXED);
    __atomic_store_n(&s->switches, s->switches + 1, __ATOMIC_RELAXED);
    context_switch(&s->ctx, &thread->ctx);
    __atomic_store_n(&s->current_id, -1, __ATOMIC_RELAXED);
  }
}

static void scheduler_init(void) {
  stack_configure();
  sched_stack = stack_map(SCHEDULER_STACK_SIZE);
  prepare_context(&main_sched.ctx, sched_stack, SCHEDULER_STACK_SIZE,
                  scheduler_loop);
#ifdef IDRIS2I_1_HAVE_VALGRIND
  (void)VALGRIND_STACK_REGISTER((char *)sched_stack + page_size,
                                (char *)sched_stack + page_size +
                                    SCHEDULER_STACK_SIZE);
#endif
#if IDRIS2I_1_MULTICORE
  init_cond(&main_sched.cond);
#endif
}

#if IDRIS2I_1_MULTICORE
// The number of workers: IDRIS2I_1_WORKERS, or the number of processors.
static int configured_workers(void) {
  const char *env = getenv("IDRIS2I_1_WORKERS");
  if (env && *env) {
    char *end = NULL;
    long n = strtol(env, &end, 10);
    if (*end == '\0' && n >= 1 && n <= 1024) {
      return (int)n;
    }
    fprintf(stderr,
            "RefC: ignoring IDRIS2I_1_WORKERS=%s (expected a number of workers "
            "from 1 to 1024)\n",
            env);
  }
  long n = sysconf(_SC_NPROCESSORS_ONLN);
  return n < 1 ? 1 : n > 256 ? 256 : (int)n;
}

static void *worker_main(void *arg) {
  Sched *s = (Sched *)arg;
  idris2i_1_tlsWorker = s->worker;
  idris2i_1_backtraceThreadSetup();
  scheduler_loop();
  return NULL;
}

// How often the monitor looks at the workers, and so how long a thread may
// run while others wait for its worker.
#define PREEMPT_INTERVAL_NS ((int64_t)10000000)

// How long threads that wait for file descriptors may go without a poll
// while every worker is busy (see monitor_main).
#define IO_CHECK_NS ((int64_t)1000000)

// Is every worker running a thread?  Then nobody looks at the deadlines:
// a worker does in its scheduler, and a parked one waits for the earliest
// deadline (see park), but a thread that computes may not switch out for
// long.
static int all_workers_busy(int n) {
  if (__atomic_load_n(&n_parked, __ATOMIC_RELAXED) > 0) {
    return 0;
  }
  for (int i = 0; i < n; i++) {
    if (__atomic_load_n(&workers[i]->current_id, __ATOMIC_RELAXED) == -1) {
      return 0;
    }
  }
  return 1;
}

// Ask a worker to yield at its next safepoint.  Returns 1 when it was not
// asked already.
static int ask_to_yield(Sched *w) {
  if (__atomic_load_n(&w->worker->preempt, __ATOMIC_RELAXED)) {
    return 0;
  }
  __atomic_store_n(&w->worker->preempt, 1, __ATOMIC_RELAXED);
  return 1;
}

// The monitor asks the threads that ran for a whole interval while other
// threads waited for their worker to yield (see IDRIS2I_1_SAFEPOINT), when
// there are several workers.  (With a single one, threads are not preempted
// to let the others run, see refc.rst.)
//
// It also wakes up for the earliest deadline, and when it is over while
// every worker runs a thread, it asks one of them to yield:
// idris2i_1_threadYield makes the threads whose deadline is over runnable, and
// lets them run.  Otherwise a thread that sleeps, or waits with a timeout,
// would wait until a thread that computes blocks or ends.  (A deadline that
// is set while the monitor sleeps, or while a worker is idle, may be missed
// by up to PREEMPT_INTERVAL_NS, as nothing wakes the monitor up.)
static void *monitor_main(void *arg) {
  (void)arg;
  int n = n_workers;
  uint64_t *seen = calloc((size_t)n, sizeof(uint64_t));
  if (!seen) {
    return NULL;
  }
  int64_t next_look = idris2i_1_monotonicNanoseconds() + PREEMPT_INTERVAL_NS;
  int asked = 0; // a worker was asked to yield in the last round
  // The worker asked last to yield for a deadline, and when.
  Sched *victim = NULL;
  int64_t victim_asked = 0;
  int next_victim = 0;
  // The poll count of the reactor, and since when it has not changed.
  uint64_t io_polls_seen = 0;
  int64_t io_polls_when = 0;
  for (;;) {
    int64_t now = idris2i_1_monotonicNanoseconds();
    int64_t until = next_look;
    // (when a worker is idle, it looks at the deadlines itself)
    int64_t deadline = __atomic_load_n(&next_deadline, __ATOMIC_ACQUIRE);
    if (deadline > now && deadline < until && all_workers_busy(n)) {
      until = deadline;
    }
    // Once a worker has been asked to yield, look again soon, so that the
    // safepoints of the other workers stop calling idris2i_1_preemptYield (see
    // idris2i_1_preemptPending) once it has.
    if (asked && now + WATCH_INTERVAL_NS < until) {
      until = now + WATCH_INTERVAL_NS;
    }
    // Threads wait for file descriptors while every worker runs a thread:
    // look whether somebody polls (see below).
    if (io_pending() && now + IO_CHECK_NS < until &&
        (all_workers_busy(n) ||
         __atomic_load_n(&in_poller, __ATOMIC_RELAXED) == NULL)) {
      until = now + IO_CHECK_NS;
    }
    if (until > now) {
      struct timespec delay;
      delay.tv_sec = (time_t)((until - now) / 1000000000);
      delay.tv_nsec = (long)((until - now) % 1000000000);
      nanosleep(&delay, NULL);
      now = idris2i_1_monotonicNanoseconds();
    }
    asked = 0;
    if (now >= next_look) {
      next_look = now + PREEMPT_INTERVAL_NS;
      for (int i = 0; i < n; i++) {
        Sched *w = workers[i];
        uint64_t switches = __atomic_load_n(&w->switches, __ATOMIC_RELAXED);
        if (n > 1 && switches == seen[i] &&
            __atomic_load_n(&w->current_id, __ATOMIC_RELAXED) != -1 &&
            queued(w) > 0) {
          asked |= ask_to_yield(w);
        }
        seen[i] = switches;
      }
    }
    deadline = __atomic_load_n(&next_deadline, __ATOMIC_ACQUIRE);
    if (deadline <= now && all_workers_busy(n) &&
        !(victim && __atomic_load_n(&victim->worker->preempt, __ATOMIC_RELAXED) &&
          now - victim_asked < PREEMPT_INTERVAL_NS)) {
      // (another worker every time, in case the one asked before does not
      // get to a safepoint: it runs a system call, say)
      victim = workers[next_victim];
      next_victim = (next_victim + 1) % n;
      victim_asked = now;
      asked |= ask_to_yield(victim);
    }
    // Nobody polled for IO_CHECK_NS while threads wait for file descriptors
    // and every worker runs a thread: ask one to yield, as for a deadline
    // (yield_current polls).
    // When some workers are parked but none of them polls (the one that
    // polled left to run the threads that it woke up, say, and runs one that
    // computes), wake one of them up: it becomes the watcher.
    uint64_t polls = __atomic_load_n(&idris2i_1_reactorPolls, __ATOMIC_RELAXED);
    int busy = all_workers_busy(n);
    if (io_pending() && !busy &&
        __atomic_load_n(&in_poller, __ATOMIC_RELAXED) == NULL) {
      if (polls != io_polls_seen) {
        io_polls_seen = polls;
        io_polls_when = now;
      } else if (now - io_polls_when >= IO_CHECK_NS) {
        io_polls_when = now;
        timer_kick();
      }
    } else if (io_pending() && busy) {
      if (polls != io_polls_seen) {
        io_polls_seen = polls;
        io_polls_when = now;
      } else if (now - io_polls_when >= IO_CHECK_NS &&
                 !(victim &&
                   __atomic_load_n(&victim->worker->preempt,
                                   __ATOMIC_RELAXED) &&
                   now - victim_asked < PREEMPT_INTERVAL_NS)) {
        victim = workers[next_victim];
        next_victim = (next_victim + 1) % n;
        victim_asked = now;
        io_polls_when = now;
        asked |= ask_to_yield(victim);
      }
    } else {
      io_polls_seen = polls;
      io_polls_when = now;
    }
    int pending = 0;
    for (int i = 0; i < n; i++) {
      pending |=
          __atomic_load_n(&workers[i]->worker->preempt, __ATOMIC_RELAXED);
    }
    __atomic_store_n(&idris2i_1_preemptPending, pending, __ATOMIC_RELAXED);
  }
  return NULL;
}

// Start the other workers, the first time that a thread is forked, and the
// monitor.
static void start_workers(void) {
  static int started = 0;
  if (started) {
    return;
  }
  started = 1;
  int n = configured_workers();
  pthread_attr_t attr;
  pthread_attr_init(&attr);
  pthread_attr_setdetachstate(&attr, PTHREAD_CREATE_DETACHED);
  // The scheduler of a worker runs on the stack of its OS thread.
  pthread_attr_setstacksize(&attr, SCHEDULER_STACK_SIZE);
  if (n > 1) {
    // From now on, the values that threads hand over to each other are
    // shared, and so are the constants of the program.
    idris2i_1_multicoreStarted = 1;
    idris2i_1_shareConstants();
    idris2i_1_markShared(main_thread.thread_data);

    Sched **all = calloc((size_t)n, sizeof(Sched *));
    seen_runnext = calloc((size_t)n, sizeof(Idris2i_1_Thread *));
    seen_runnext_gen = calloc((size_t)n, sizeof(uint64_t));
    if (!all || !seen_runnext || !seen_runnext_gen) {
      fatal("could not allocate the workers");
    }
    all[0] = &main_sched;
    main_sched.random = 1;
    int created = 1;
    for (int i = 1; i < n; i++) {
      Sched *s = calloc(1, sizeof(Sched));
      Idris2i_1_Worker *w =
          aligned_alloc(64, (sizeof(Idris2i_1_Worker) + 63) / 64 * 64);
      if (!s || !w) {
        free(s);
        free(w);
        break;
      }
      memset(w, 0, sizeof(Idris2i_1_Worker));
      w->sched = s;
      s->worker = w;
      s->index = i;
      s->current_id = -1;
      s->random = (uint32_t)i * 2654435761u;
      init_cond(&s->cond);
      all[created++] = s;
    }
    workers = all;
    __atomic_store_n(&n_workers, created, __ATOMIC_RELEASE);
    for (int i = 1; i < created; i++) {
      pthread_t pthread;
      if (pthread_create(&pthread, &attr, worker_main, all[i]) != 0) {
        fatal("could not start the workers (try IDRIS2I_1_WORKERS=1)");
      }
    }
  }
  // IDRIS2I_1_PREEMPT=0 turns preemption off.  The monitor runs with a single
  // worker too, for the deadlines (see monitor_main).
  const char *preempt = getenv("IDRIS2I_1_PREEMPT");
  if (!preempt || strcmp(preempt, "0") != 0) {
    pthread_t monitor;
    if (pthread_create(&monitor, &attr, monitor_main, NULL) != 0) {
      fatal("could not start the monitor of the workers (try "
            "IDRIS2I_1_PREEMPT=0)");
    }
  }
  pthread_attr_destroy(&attr);
}
#else
static void start_workers(void) {}
#endif

// The main expression, while it is started on its own stack.
static Idris2i_1_Value *(*main_action)(void) = NULL;
// The context of the process stack, to come back to when main is done.
static Context process_ctx;

static void main_entry(void) {
  idris2i_1_trampoline(main_action());
  // Back to the process stack, from whichever worker the main thread runs
  // on now: the program ends there.
  context_switch(&main_thread.ctx, &process_ctx);
  fatal("the main thread was resumed after it finished");
}

// Run the main expression on a stack of its own.  Returns 0, without running
// it, when that stack cannot be allocated.
static int run_main_on_own_stack(Idris2i_1_Value *(*mainAction)(void)) {
  size_t size = stack_size_from_env("IDRIS2I_1_MAIN_STACK_SIZE",
                                    DEFAULT_MAIN_STACK_SIZE);
  void *mapping = stack_try_map(size);
  if (!mapping) {
    return 0;
  }
  main_thread.stack = mapping;
  main_action = mainAction;
  prepare_context(&main_thread.ctx, mapping, size, main_entry);
#ifdef IDRIS2I_1_HAVE_VALGRIND
  main_thread.valgrind_stack_id = VALGRIND_STACK_REGISTER(
      (char *)mapping + page_size, (char *)mapping + page_size + size);
#endif
  context_switch(&process_ctx, &main_thread.ctx);
  // The mapping is left alone: the program is about to end.
  return 1;
}

#else

int idris2i_1_threadStackGuard(const void *addr) {
  (void)addr;
  return 0;
}

#endif /* IDRIS2I_1_GREEN_THREADS */

// The reports of memoryManagement.c, when the program exits before the end
// of its main expression (by `exitWith`, say).
static void report_at_exit(void) {
  idris2i_1_reportAtExit(0, __atomic_load_n(&live_threads, __ATOMIC_RELAXED));
}

// IDRIS2I_1_REFC_KEEP_PAGES: the number of empty pages that a worker keeps
// (see memoryManagement.c).
static void configure_keep_pages(void) {
  const char *env = getenv("IDRIS2I_1_REFC_KEEP_PAGES");
  if (env && *env) {
    char *end = NULL;
    long n = strtol(env, &end, 10);
    if (*end == '\0' && n >= 0 && n <= 1000000) {
      idris2i_1_keepPages = (int)n;
      return;
    }
    fprintf(stderr,
            "RefC: ignoring IDRIS2I_1_REFC_KEEP_PAGES=%s (expected a number of "
            "pages from 0 to 1000000)\n",
            env);
  }
}

void idris2i_1_threadSchedulerRun(Idris2i_1_Value *(*mainAction)(void)) {
  main_sched.current = &main_thread;
  idris2i_1_backtraceSetup();
  configure_keep_pages();
  atexit(report_at_exit);
#if IDRIS2I_1_GREEN_THREADS
  scheduler_init();
  if (!run_main_on_own_stack(mainAction))
#endif
  {
    // No stack of its own: run on the stack of the process.
    idris2i_1_trampoline(mainAction());
  }
  // Like in the Chez backend, the program is over once the main expression
  // is done: the other threads, if any, are abandoned.
  thread_finish(&main_thread);
  idris2i_1_reportAtExit(1, __atomic_load_n(&live_threads, __ATOMIC_RELAXED));
}

int idris2i_1_threadStopOthers(void) {
#if IDRIS2I_1_MULTICORE
  int n = idris2i_1_workerCount();
  if (n <= 1) {
    return 0;
  }
  Sched *me = self();
  // (seen by a parked worker when it takes idle_lock to wake up, see
  // stop_worker)
  __atomic_store_n(&stopping, 1, __ATOMIC_SEQ_CST);
  for (int i = 0; i < n; i++) {
    if (workers[i] != me) {
      __atomic_store_n(&workers[i]->worker->preempt, 1, __ATOMIC_RELAXED);
    }
  }
  __atomic_store_n(&idris2i_1_preemptPending, 1, __ATOMIC_RELAXED);
  // A worker may not get to a safepoint (it makes a system call, say): give
  // up after a while.
  int64_t give_up = idris2i_1_monotonicNanoseconds() + 1000000000;
  for (;;) {
    int running = 0;
    pthread_mutex_lock(&idle_lock);
    for (int i = 0; i < n; i++) {
      // A parked worker touches nothing on its way to stop_worker.
      if (workers[i] != me && !workers[i]->stopped && !workers[i]->parked) {
        running++;
      }
    }
    pthread_mutex_unlock(&idle_lock);
    if (running == 0 || idris2i_1_monotonicNanoseconds() >= give_up) {
      return running;
    }
    struct timespec delay = {0, 100000};
    nanosleep(&delay, NULL);
  }
#else
  return 0;
#endif
}

int idris2i_1_threadRunsElsewhere(int worker, int64_t thread) {
#if IDRIS2I_1_GREEN_THREADS
  Sched *s = self();
  return worker >= 0 && worker < n_workers && workers[worker] != s &&
         __atomic_load_n(&workers[worker]->current_id, __ATOMIC_RELAXED) ==
             thread &&
         !queued(s);
#else
  (void)worker;
  (void)thread;
  return 0;
#endif
}

// ---------------------------------------------------------------------------
// FFI
// ---------------------------------------------------------------------------

void *refc_fork(Idris2i_1_Closure *fct) {
#if IDRIS2I_1_GREEN_THREADS
  start_workers();
  Sched *s = self();
  Idris2i_1_Thread *parent = s->current;
  Idris2i_1_Thread *thread = (Idris2i_1_Thread *)calloc(1, sizeof(Idris2i_1_Thread));
  if (!thread) {
    fatal("could not allocate a green thread");
  }
  thread->id = __atomic_fetch_add(&next_thread_id, 1, __ATOMIC_RELAXED);
  thread->state = THREAD_RUNNABLE;
  if (idris2i_1_multicoreStarted) {
    // The new thread may run in parallel with this one.
    idris2i_1_markShared((Idris2i_1_Value *)fct);
    idris2i_1_markShared(parent->thread_data);
  }
  thread->action = (Idris2i_1_Closure *)idris2i_1_newReference((Idris2i_1_Value *)fct);
  // Like the thread parameters of Chez Scheme, the thread local data is
  // inherited from the parent.
  thread->thread_data = idris2i_1_newReference(parent->thread_data);

  Idris2i_1_ThreadID *handle =
      (Idris2i_1_ThreadID *)idris2i_1_newZeroedValue(sizeof(Idris2i_1_ThreadID));
  handle->header.tag = THREAD_ID_TAG;
  handle->id = thread->id;
  if (idris2i_1_multicoreStarted) {
    handle->header.reserved |= IDRIS2I_1_SHARED_FLAG;
  }
  thread->handle = handle; // the reference created by idris2i_1_newValue

  thread->stack = stack_alloc(s);
  prepare_context(&thread->ctx, thread->stack, stack_size, thread_entry);
#ifdef IDRIS2I_1_HAVE_VALGRIND
  thread->valgrind_stack_id =
      VALGRIND_STACK_REGISTER((char *)thread->stack + page_size,
                              (char *)thread->stack + page_size + stack_size);
#endif

  __atomic_fetch_add(&live_threads, 1, __ATOMIC_RELAXED);
  // The reference for the caller must be taken before the new thread gets a
  // chance to run, as the thread drops its own reference when it finishes.
  void *result = idris2i_1_newReference((Idris2i_1_Value *)handle);
  // Let the new thread start right away; an idle worker may take this one
  // over in the meantime.
  runq_put(s, thread, __atomic_load_n(&n_workers, __ATOMIC_RELAXED) > 1);
  idris2i_1_threadYield();
  return result;
#else
  (void)fct;
  fatal("green threads are not supported on this platform");
  return NULL;
#endif
}

void refc_threadWait(Idris2i_1_Value *threadID) {
  Idris2i_1_ThreadID *handle = (Idris2i_1_ThreadID *)threadID;
  if (!handle || handle->id == self()->current->id) {
    return; // waiting for itself
  }
  idris2i_1_spinLock(&handle->lock);
  if (handle->finished) {
    idris2i_1_spinUnlock(&handle->lock);
    return;
  }
  idris2i_1_threadBlockOn(&handle->joiners, &handle->lock);
}

int64_t refc_getThreadId(void) { return self()->current->id; }

void refc_setThreadData(Idris2i_1_Value *erased, Idris2i_1_Value *value) {
  (void)erased;
  Idris2i_1_Thread *thread = self()->current;
  Idris2i_1_Value *previous = thread->thread_data;
  thread->thread_data = idris2i_1_newReference(value);
  idris2i_1_removeReference(previous);
}

void *refc_getThreadData(Idris2i_1_Value *erased) {
  (void)erased;
  // The data stays in the thread: the caller gets a reference of its own.
  return idris2i_1_newReference(self()->current->thread_data);
}
