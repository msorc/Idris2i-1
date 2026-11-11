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
// IDRIS2_WORKERS of them in all.  Every worker has a run queue.  A thread
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
#include "memoryManagement.h"
#include "runtime.h"
#include "worker.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

// The hand written context switch is used on x86-64 (System V ABI, so not
// on Windows, which has no green threads anyway) and on AArch64, for ELF and
// Mach-O objects.  Define IDRIS2_USE_UCONTEXT to use swapcontext(3) instead.
#if IDRIS2_GREEN_THREADS && !defined(IDRIS2_USE_UCONTEXT) &&                   \
    (defined(__x86_64__) || defined(__aarch64__)) &&                           \
    (defined(__ELF__) || defined(__APPLE__))
#define IDRIS2_ASM_CONTEXT 1
#else
#define IDRIS2_ASM_CONTEXT 0
#endif

#if IDRIS2_GREEN_THREADS
#include <sys/mman.h>
#include <unistd.h>
#if !IDRIS2_ASM_CONTEXT
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
#define IDRIS2_HAVE_VALGRIND 1
#endif
#endif
#endif

#if IDRIS2_MULTICORE
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

#if IDRIS2_GREEN_THREADS && IDRIS2_ASM_CONTEXT

// The context is just the stack pointer: the callee saved registers are
// pushed onto the stack of the thread being switched out.
typedef struct {
  void *sp;
} Context;

// void idris2_context_switch(void **save_sp, void *load_sp)
void idris2_context_switch(void **save_sp, void *load_sp);

#if defined(__APPLE__)
#define CTX_SYM "_idris2_context_switch"
#define CTX_BEGIN                                                              \
  ".text\n"                                                                    \
  ".globl " CTX_SYM "\n"                                                       \
  ".private_extern " CTX_SYM "\n"                                              \
  ".p2align 4\n" CTX_SYM ":\n"
#define CTX_END ""
#else
#define CTX_SYM "idris2_context_switch"
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
  idris2_context_switch(&from->sp, to->sp);
}

#elif IDRIS2_GREEN_THREADS

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

struct Idris2_Thread {
  int64_t id;
  Thread_State state;
  // The action of a forked thread: a `PrimIO ()`, i.e. a closure waiting for
  // its %World argument.  NULL once the thread has started.
  Idris2_Closure *action;
  // The handle handed out by `fork`.  The thread owns one reference to it
  // while it runs.  NULL for the main thread.
  Idris2_ThreadID *handle;
  // Thread local data, as set by `setThreadData`.
  Idris2_Value *thread_data;
  // Link in a run queue.
  Idris2_Thread *run_next;
  // The queue this thread is waiting in (if any), the lock that guards it,
  // and the link in it.
  Idris2_WaitQueue *wait_queue;
  Idris2_SpinLock *wait_lock;
  Idris2_Thread *wait_next;
  // The deadline of a timed wait (if any), and the link in the timer list.
  int has_deadline;
  int in_timers;
  int timed_out;
  // Set by whoever wakes up a thread with a deadline: an event or the
  // deadline (see idris2_threadWakeOne and expire_timers).
  int claimed;
  int64_t deadline_ns;
  Idris2_Thread *timer_next;
#if IDRIS2_GREEN_THREADS
  Context ctx;
  // The mapping holding the stack, guard page included.  NULL for the main
  // thread when it runs on the stack of the process.
  void *stack;
#ifdef IDRIS2_HAVE_VALGRIND
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
  Idris2_Worker *worker;
  int index;
  // The thread that the worker runs, NULL while the scheduler runs, and its
  // identifier (-1 then), which other workers may read.
  Idris2_Thread *current;
  int64_t current_id;
  // The number of threads that the worker started running (see monitor).
  uint64_t switches;
#if IDRIS2_GREEN_THREADS
  Context ctx; // the context of the scheduler
  After after;
  Idris2_SpinLock *after_lock;
  // The run queue (FIFO), and the thread to run next, which goes before the
  // queue; `lock` guards them.  `runnext_gen` changes whenever `runnext`
  // does (see runq_steal).
  Idris2_SpinLock lock;
  Idris2_Thread *head;
  Idris2_Thread *tail;
  int64_t qlen;
  Idris2_Thread *runnext;
  uint64_t runnext_gen;
  void *stack_cache[STACK_CACHE_SIZE];
  int stack_cache_count;
#endif
#if IDRIS2_MULTICORE
  pthread_cond_t cond; // signalled to wake up the worker when it is parked
  int parked;          // (these are guarded by idle_lock)
  struct Sched *idle_next;
  int spinning; // looking for work in the other run queues
  int watching; // the watcher whose wait is over (see park)
  uint32_t random;
#endif
} Sched;

// The main thread is statically allocated, so that there is always a current
// thread, even before the scheduler starts.
static Idris2_Thread main_thread;
static Sched main_sched;
Idris2_Worker idris2_mainWorker = {.sched = &main_sched};
static Sched main_sched = {
    .worker = &idris2_mainWorker, .current = &main_thread, .current_id = 0};

int idris2_multicoreStarted = 0;

#if IDRIS2_MULTICORE
__thread Idris2_Worker *idris2_tlsWorker = &idris2_mainWorker;

Idris2_Worker *idris2_workerSlow(void) { return idris2_tlsWorker; }
#endif

static inline Sched *self(void) { return (Sched *)idris2_worker()->sched; }

// The workers.  workers[0] is the main OS thread.
static Sched *main_workers[1] = {&main_sched};
static Sched **workers = main_workers;
static int n_workers = 1;

// The main thread has identifier 0.
static int64_t next_thread_id = 1;

// The number of threads that have not finished yet, the main one included.
static int64_t live_threads = 1;

// The threads with a deadline, sorted by deadline, and the earliest
// deadline (INT64_MAX if there is none).
static Idris2_SpinLock timer_lock = 0;
static Idris2_Thread *timers = NULL;
static int64_t next_deadline = INT64_MAX;

static void fatal(const char *message) {
  fprintf(stderr, "RefC: %s\n", message);
  exit(1);
}

int idris2_threadsInParallel(void) {
  return __atomic_load_n(&n_workers, __ATOMIC_RELAXED) > 1;
}

int idris2_workerIndex(void) { return self()->index; }


void idris2_spinLockSlow(Idris2_SpinLock *lock) {
  for (unsigned spins = 0;; spins++) {
    while (__atomic_load_n(lock, __ATOMIC_RELAXED)) {
      if (spins++ < 1000) {
        idris2_cpuRelax();
      } else {
#if IDRIS2_MULTICORE
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

int64_t idris2_monotonicNanoseconds(void) {
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

int64_t idris2_deadlineAfter(int64_t microseconds) {
  int64_t now = idris2_monotonicNanoseconds();
  if (microseconds <= 0) {
    return now;
  }
  if (microseconds > (INT64_MAX - now) / 1000) {
    return INT64_MAX - 1;
  }
  return now + microseconds * 1000;
}

#if !IDRIS2_MULTICORE
// Block the whole process until the monotonic clock reaches `deadline_ns`.
static void sleep_until(int64_t deadline_ns) {
  for (;;) {
    int64_t remaining = deadline_ns - idris2_monotonicNanoseconds();
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

static void waitq_push(Idris2_WaitQueue *queue, Idris2_Thread *thread) {
  thread->wait_queue = queue;
  thread->wait_next = NULL;
  if (queue->tail) {
    queue->tail->wait_next = thread;
  } else {
    queue->head = thread;
  }
  queue->tail = thread;
}

static void waitq_remove(Idris2_WaitQueue *queue, Idris2_Thread *thread) {
  Idris2_Thread *previous = NULL;
  for (Idris2_Thread *t = queue->head; t; previous = t, t = t->wait_next) {
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

Idris2_Thread *idris2_threadTakeWaiter(Idris2_WaitQueue *queue) {
  Idris2_Thread *thread = queue->head;
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

// The timer list is guarded by timer_lock.  Returns 1 when the deadline is
// the earliest one.
static int timer_insert(Idris2_Thread *thread) {
  // Keep the list sorted; threads with the same deadline stay in FIFO order.
  Idris2_Thread **link = &timers;
  while (*link && (*link)->deadline_ns <= thread->deadline_ns) {
    link = &(*link)->timer_next;
  }
  thread->timer_next = *link;
  *link = thread;
  thread->in_timers = 1;
  __atomic_store_n(&next_deadline, timers->deadline_ns, __ATOMIC_RELEASE);
  return timers == thread;
}

static void timer_remove(Idris2_Thread *thread) {
  for (Idris2_Thread **link = &timers; *link; link = &(*link)->timer_next) {
    if (*link == thread) {
      *link = thread->timer_next;
      break;
    }
  }
  thread->in_timers = 0;
  thread->timer_next = NULL;
  __atomic_store_n(&next_deadline, timers ? timers->deadline_ns : INT64_MAX,
                   __ATOMIC_RELEASE);
}

// ---------------------------------------------------------------------------
// Run queues and idle workers
// ---------------------------------------------------------------------------

#if IDRIS2_GREEN_THREADS

#if IDRIS2_MULTICORE
// The parked workers wait on their condition variable with idle_lock.
static pthread_mutex_t idle_lock = PTHREAD_MUTEX_INITIALIZER;
static Sched *idle_list = NULL;
static int n_parked = 0;   // written under idle_lock
static int n_spinning = 0; // atomic
// The parked worker that wakes up for the deadlines and to look at the run
// queues, if any (guarded by idle_lock).
static Sched *watcher = NULL;
// What the watcher saw as the next thread of every worker (see runq_steal).
static Idris2_Thread **seen_runnext = NULL;
static uint64_t *seen_runnext_gen = NULL;
#endif

// How often the watcher looks at the run queues while threads wait in them.
#define WATCH_INTERVAL_NS ((int64_t)100000)

static void wakep(void);

static int64_t queued(Sched *s) {
  return __atomic_load_n(&s->qlen, __ATOMIC_RELAXED) +
         (__atomic_load_n(&s->runnext, __ATOMIC_RELAXED) ? 1 : 0);
}

static void runq_append(Sched *s, Idris2_Thread *thread) {
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
static void runq_put(Sched *s, Idris2_Thread *thread, int next) {
  Idris2_Thread *kicked = NULL;
  idris2_spinLock(&s->lock);
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
  idris2_spinUnlock(&s->lock);
  // A thread in the queue may be run by another worker; the next one is
  // left for this worker, which is likely to run it soon.
  if (!next || kicked) {
    wakep();
  }
}

static Idris2_Thread *runq_get(Sched *s) {
  if (!__atomic_load_n(&s->runnext, __ATOMIC_RELAXED) &&
      !__atomic_load_n(&s->head, __ATOMIC_RELAXED)) {
    return NULL;
  }
  idris2_spinLock(&s->lock);
  Idris2_Thread *thread = s->runnext;
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
  idris2_spinUnlock(&s->lock);
  return thread;
}

#if IDRIS2_MULTICORE
// Take half of the run queue of `victim`: the first thread is returned, the
// others go to the run queue of `thief`.  The watcher also takes the next
// thread of a worker, when it has been waiting since its previous look.
static Idris2_Thread *runq_steal(Sched *thief, Sched *victim, int watching) {
  if (!__atomic_load_n(&victim->head, __ATOMIC_RELAXED) &&
      !(watching && __atomic_load_n(&victim->runnext, __ATOMIC_RELAXED))) {
    return NULL;
  }
  Idris2_Thread *first = NULL, *rest = NULL, *rest_tail = NULL;
  int64_t taken = 0;
  idris2_spinLock(&victim->lock);
  int64_t take = (victim->qlen + 1) / 2;
  while (taken < take) {
    Idris2_Thread *thread = victim->head;
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
  idris2_spinUnlock(&victim->lock);
  if (rest) {
    idris2_spinLock(&thief->lock);
    if (thief->tail) {
      thief->tail->run_next = rest;
    } else {
      thief->head = rest;
    }
    thief->tail = rest_tail;
    __atomic_store_n(&thief->qlen, thief->qlen + taken - 1, __ATOMIC_RELAXED);
    idris2_spinUnlock(&thief->lock);
  }
  return first;
}

static Idris2_Thread *steal_work(Sched *s, int watching) {
  int n = __atomic_load_n(&n_workers, __ATOMIC_ACQUIRE);
  s->random = s->random * 1103515245u + 12345u;
  int start = (int)((s->random >> 16) % (unsigned)n);
  for (int i = 0; i < n; i++) {
    Sched *victim = workers[(start + i) % n];
    if (victim != s) {
      Idris2_Thread *thread = runq_steal(s, victim, watching);
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
  } else {
    __atomic_fetch_sub(&n_spinning, 1, __ATOMIC_SEQ_CST);
  }
  pthread_mutex_unlock(&idle_lock);
}

// A deadline was set that is earlier than the others: make sure that a
// parked worker waits for it.
static void timer_kick(void) {
  if (__atomic_load_n(&n_parked, __ATOMIC_RELAXED) == 0) {
    return;
  }
  pthread_mutex_lock(&idle_lock);
  if (watcher) {
    pthread_cond_signal(&watcher->cond);
  } else if (idle_list) {
    pthread_cond_signal(&idle_list->cond);
  }
  pthread_mutex_unlock(&idle_lock);
}

static void timed_wait(Sched *s, int64_t deadline_ns) {
#if defined(__APPLE__)
  int64_t remaining = deadline_ns - idris2_monotonicNanoseconds();
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
#else
static void wakep(void) {}
static void timer_kick(void) {}
#endif

static void deadlock(void) {
  fprintf(stderr,
          "RefC: deadlock detected: all the %lld remaining green "
          "thread(s) are blocked forever\n",
          (long long)__atomic_load_n(&live_threads, __ATOMIC_RELAXED));
  exit(1);
}

// Wait until there may be something to do: a thread to run, or a deadline.
static void park(Sched *s) {
#if IDRIS2_MULTICORE
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
    if (n_parked == n_workers && waiting == 0 && deadline == INT64_MAX) {
      // Nobody runs, and nothing can happen.
      deadlock();
    }
    if (!watcher && (waiting > 0 || deadline != INT64_MAX)) {
      watcher = s;
    }
    if (watcher != s) {
      pthread_cond_wait(&s->cond, &idle_lock);
      continue;
    }
    int64_t now = idris2_monotonicNanoseconds();
    int64_t until = deadline;
    if (waiting > 0 && now + WATCH_INTERVAL_NS < until) {
      until = now + WATCH_INTERVAL_NS;
    }
    if (until > now) {
      timed_wait(s, until);
      if (s->parked && idris2_monotonicNanoseconds() < until) {
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
  if (deadline == INT64_MAX) {
    deadlock();
  }
  sleep_until(deadline);
#endif
}

#endif /* IDRIS2_GREEN_THREADS */

// ---------------------------------------------------------------------------
// Blocking and waking up
// ---------------------------------------------------------------------------

// Make a thread that was blocked runnable.
static void make_runnable(Idris2_Thread *thread) {
  thread->state = THREAD_RUNNABLE;
#if IDRIS2_GREEN_THREADS
  Sched *s = self();
  // Woken up by a running thread: it runs next on the same worker.  (A
  // single worker keeps the plain FIFO order, as there is nothing to gain.)
  runq_put(s, thread,
           s->current != NULL &&
               __atomic_load_n(&n_workers, __ATOMIC_RELAXED) > 1);
#endif
}

void idris2_threadSchedule(Idris2_Thread *thread) {
  if (thread) {
    make_runnable(thread);
  }
}

int idris2_threadWakeOne(Idris2_WaitQueue *queue) {
  Idris2_Thread *thread;
  while ((thread = idris2_threadTakeWaiter(queue)) != NULL) {
    if (thread->has_deadline) {
      int zero = 0;
      if (!__atomic_compare_exchange_n(&thread->claimed, &zero, 1, 0,
                                       __ATOMIC_ACQ_REL, __ATOMIC_ACQUIRE)) {
        continue; // its deadline expired first: it wakes up anyway
      }
      idris2_spinLock(&timer_lock);
      if (thread->in_timers) {
        timer_remove(thread);
      }
      idris2_spinUnlock(&timer_lock);
    }
    make_runnable(thread);
    return 1;
  }
  return 0;
}

void idris2_threadWakeAll(Idris2_WaitQueue *queue) {
  while (idris2_threadWakeOne(queue)) {
  }
}

#if IDRIS2_GREEN_THREADS
// Make the threads whose deadline has expired runnable again.
static void expire_timers(void) {
  int64_t deadline = __atomic_load_n(&next_deadline, __ATOMIC_ACQUIRE);
  if (deadline == INT64_MAX) {
    return;
  }
  int64_t now = idris2_monotonicNanoseconds();
  if (deadline > now) {
    return;
  }
  Idris2_Thread *expired = NULL;
  idris2_spinLock(&timer_lock);
  while (timers && timers->deadline_ns <= now) {
    Idris2_Thread *thread = timers;
    timer_remove(thread);
    thread->timer_next = expired;
    expired = thread;
  }
  idris2_spinUnlock(&timer_lock);
  while (expired) {
    Idris2_Thread *thread = expired;
    expired = thread->timer_next;
    thread->timer_next = NULL;
    int zero = 0;
    if (__atomic_compare_exchange_n(&thread->claimed, &zero, 1, 0,
                                    __ATOMIC_ACQ_REL, __ATOMIC_ACQUIRE)) {
      // It leaves its wait queue itself (see block_current).
      thread->timed_out = 1;
      make_runnable(thread);
    }
  }
}
#endif

Idris2_Thread *idris2_currentThread(void) { return self()->current; }

int64_t idris2_threadId(Idris2_Thread *thread) {
  return thread ? thread->id : 0;
}

// Block the current thread, see idris2_threadBlockOnUntil.  `queue` and
// `lock` may be NULL (to sleep).
static int block_current(Idris2_WaitQueue *queue, Idris2_SpinLock *lock,
                         int64_t deadline_ns) {
  Sched *s = self();
  Idris2_Thread *thread = s->current;
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
#if IDRIS2_GREEN_THREADS
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
    idris2_spinLock(lock);
    if (thread->wait_queue) {
      waitq_remove(thread->wait_queue, thread);
    }
    idris2_spinUnlock(lock);
  }
  thread->has_deadline = 0;
  thread->wait_lock = NULL;
  return !thread->timed_out;
}

void idris2_threadBlockOn(Idris2_WaitQueue *queue, Idris2_SpinLock *lock) {
  block_current(queue, lock, NO_DEADLINE);
}

int idris2_threadBlockOnUntil(Idris2_WaitQueue *queue, Idris2_SpinLock *lock,
                              int64_t deadline_ns) {
  if (deadline_ns < 0) {
    deadline_ns = 0;
  }
  return block_current(queue, lock, deadline_ns);
}

void idris2_threadYield(void) {
#if IDRIS2_GREEN_THREADS
  expire_timers();
  Sched *s = self();
  if (!queued(s)) {
    return; // nobody else wants to run here
  }
  Idris2_Thread *thread = s->current;
  thread->state = THREAD_RUNNABLE;
  s->after = AFTER_YIELD;
  context_switch(&thread->ctx, &s->ctx);
#endif
}

int idris2_preemptPending = 0;

void idris2_preemptYield(void) {
  Idris2_Worker *w = idris2_worker();
  if (__atomic_load_n(&w->preempt, __ATOMIC_RELAXED)) {
    __atomic_store_n(&w->preempt, 0, __ATOMIC_RELAXED);
    idris2_threadYield();
  }
}

void idris2_threadSleep(int64_t microseconds) {
  if (microseconds <= 0) {
    return;
  }
  block_current(NULL, NULL, idris2_deadlineAfter(microseconds));
}

// ---------------------------------------------------------------------------
// Thread lifecycle
// ---------------------------------------------------------------------------

// Called on the stack of the thread, once its action is done.
static void thread_finish(Idris2_Thread *self) {
  self->state = THREAD_FINISHED;
  __atomic_fetch_sub(&live_threads, 1, __ATOMIC_RELAXED);
  if (self->thread_data) {
    idris2_removeReference(self->thread_data);
    self->thread_data = NULL;
  }
  Idris2_ThreadID *handle = self->handle;
  if (handle) {
    // From now on the handle says that the thread is finished.
    idris2_spinLock(&handle->lock);
    handle->finished = 1;
    idris2_threadWakeAll(&handle->joiners);
    idris2_spinUnlock(&handle->lock);
    self->handle = NULL;
    idris2_removeReference((Idris2_Value *)handle);
  }
}

#if IDRIS2_GREEN_THREADS

// The size of the stacks of the forked threads.  It defaults to 8MB, which
// matches the stack of a typical process, and it can be changed with the
// IDRIS2_THREAD_STACK_SIZE environment variable (in bytes).  The memory is
// reserved lazily by the operating system, so a large stack is cheap.
#define DEFAULT_STACK_SIZE ((size_t)8 * 1024 * 1024)
#define MIN_STACK_SIZE ((size_t)64 * 1024)

// The size of the stack of the main expression, which can be changed with the
// IDRIS2_MAIN_STACK_SIZE environment variable (in bytes).  It is reserved
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
  stack_size = stack_size_from_env("IDRIS2_THREAD_STACK_SIZE",
                                   DEFAULT_STACK_SIZE);
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
static void thread_destroy(Sched *s, Idris2_Thread *thread) {
#ifdef IDRIS2_HAVE_VALGRIND
  VALGRIND_STACK_DEREGISTER(thread->valgrind_stack_id);
#endif
  stack_release(s, thread->stack);
  free(thread);
}

// The body of every forked thread.
static void thread_entry(void) {
  Idris2_Thread *thread = self()->current;
  Idris2_Closure *action = thread->action;
  thread->action = NULL;
  // This consumes the reference to the action.
  idris2_removeReference(idris2_run_primio(action));
  thread_finish(thread);
  // Hand control back to the scheduler for good; it frees this thread.
  Sched *s = self();
  s->after = AFTER_FINISH;
  context_switch(&thread->ctx, &s->ctx);
  fatal("a finished green thread was resumed");
}

// Find a thread to run, and wait for one if need be.
static Idris2_Thread *find_work(Sched *s) {
  Idris2_Thread *thread;
  for (;;) {
    expire_timers();
    thread = runq_get(s);
    if (thread) {
      break;
    }
#if IDRIS2_MULTICORE
    if (__atomic_load_n(&n_workers, __ATOMIC_RELAXED) > 1) {
      if (!s->spinning) {
        s->spinning = 1;
        __atomic_fetch_add(&n_spinning, 1, __ATOMIC_SEQ_CST);
      }
      for (int round = 0; round < 4 && !thread; round++) {
        thread = steal_work(s, 0);
        for (int i = 0; i < 64 && !thread; i++) {
          idris2_cpuRelax();
        }
      }
      if (!thread && s->watching) {
        thread = steal_work(s, 1);
      }
      s->watching = 0;
      if (thread) {
        break;
      }
      expire_timers();
      if ((thread = runq_get(s)) != NULL) {
        break;
      }
    }
#endif
    park(s);
  }
#if IDRIS2_MULTICORE
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
  Idris2_Thread *thread = s->current;
  for (;;) {
    // The thread switched out, saying why.
    s->current = NULL;
    switch (thread ? s->after : AFTER_NOTHING) {
    case AFTER_PARK:
      if (thread->has_deadline) {
        idris2_spinLock(&timer_lock);
        int earliest = timer_insert(thread);
        idris2_spinUnlock(&timer_lock);
        if (earliest) {
          timer_kick();
        }
      }
      if (s->after_lock) {
        idris2_spinUnlock(s->after_lock);
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
#ifdef IDRIS2_HAVE_VALGRIND
  (void)VALGRIND_STACK_REGISTER((char *)sched_stack + page_size,
                                (char *)sched_stack + page_size +
                                    SCHEDULER_STACK_SIZE);
#endif
#if IDRIS2_MULTICORE
  init_cond(&main_sched.cond);
#endif
}

#if IDRIS2_MULTICORE
// The number of workers: IDRIS2_WORKERS, or the number of processors.
static int configured_workers(void) {
  const char *env = getenv("IDRIS2_WORKERS");
  if (env && *env) {
    char *end = NULL;
    long n = strtol(env, &end, 10);
    if (*end == '\0' && n >= 1 && n <= 1024) {
      return (int)n;
    }
    fprintf(stderr,
            "RefC: ignoring IDRIS2_WORKERS=%s (expected a number of workers "
            "from 1 to 1024)\n",
            env);
  }
  long n = sysconf(_SC_NPROCESSORS_ONLN);
  return n < 1 ? 1 : n > 256 ? 256 : (int)n;
}

static void *worker_main(void *arg) {
  Sched *s = (Sched *)arg;
  idris2_tlsWorker = s->worker;
  scheduler_loop();
  return NULL;
}

// How often the monitor looks at the workers, and so how long a thread may
// run while others wait for its worker.
#define PREEMPT_INTERVAL_NS ((int64_t)10000000)

// The monitor asks the threads that ran for a whole interval while other
// threads waited for their worker to yield (see IDRIS2_SAFEPOINT).
static void *monitor_main(void *arg) {
  (void)arg;
  int n = n_workers;
  uint64_t *seen = calloc((size_t)n, sizeof(uint64_t));
  if (!seen) {
    return NULL;
  }
  for (;;) {
    struct timespec delay;
    delay.tv_sec = 0;
    delay.tv_nsec = (long)PREEMPT_INTERVAL_NS;
    nanosleep(&delay, NULL);
    int pending = 0;
    for (int i = 0; i < n; i++) {
      Sched *w = workers[i];
      uint64_t switches = __atomic_load_n(&w->switches, __ATOMIC_RELAXED);
      if (switches == seen[i] &&
          __atomic_load_n(&w->current_id, __ATOMIC_RELAXED) != -1 &&
          queued(w) > 0) {
        __atomic_store_n(&w->worker->preempt, 1, __ATOMIC_RELAXED);
      }
      pending |= __atomic_load_n(&w->worker->preempt, __ATOMIC_RELAXED);
      seen[i] = switches;
    }
    __atomic_store_n(&idris2_preemptPending, pending, __ATOMIC_RELAXED);
  }
  return NULL;
}

// Start the other workers, the first time that a thread is forked.
static void start_workers(void) {
  static int started = 0;
  if (started) {
    return;
  }
  started = 1;
  int n = configured_workers();
  if (n <= 1) {
    return;
  }
  // From now on, the values that threads hand over to each other are
  // shared, and so are the constants of the program.
  idris2_multicoreStarted = 1;
  idris2_shareConstants();
  idris2_markShared(main_thread.thread_data);

  Sched **all = calloc((size_t)n, sizeof(Sched *));
  seen_runnext = calloc((size_t)n, sizeof(Idris2_Thread *));
  seen_runnext_gen = calloc((size_t)n, sizeof(uint64_t));
  if (!all || !seen_runnext || !seen_runnext_gen) {
    fatal("could not allocate the workers");
  }
  all[0] = &main_sched;
  main_sched.random = 1;
  int created = 1;
  for (int i = 1; i < n; i++) {
    Sched *s = calloc(1, sizeof(Sched));
    Idris2_Worker *w = aligned_alloc(64, (sizeof(Idris2_Worker) + 63) / 64 * 64);
    if (!s || !w) {
      free(s);
      free(w);
      break;
    }
    memset(w, 0, sizeof(Idris2_Worker));
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
  pthread_attr_t attr;
  pthread_attr_init(&attr);
  pthread_attr_setdetachstate(&attr, PTHREAD_CREATE_DETACHED);
  // The scheduler of a worker runs on the stack of its OS thread.
  pthread_attr_setstacksize(&attr, SCHEDULER_STACK_SIZE);
  for (int i = 1; i < created; i++) {
    pthread_t pthread;
    if (pthread_create(&pthread, &attr, worker_main, all[i]) != 0) {
      fatal("could not start the workers (try IDRIS2_WORKERS=1)");
    }
  }
  // IDRIS2_PREEMPT=0 turns preemption off.
  const char *preempt = getenv("IDRIS2_PREEMPT");
  if (!preempt || strcmp(preempt, "0") != 0) {
    pthread_t monitor;
    if (pthread_create(&monitor, &attr, monitor_main, NULL) != 0) {
      fatal("could not start the workers (try IDRIS2_WORKERS=1)");
    }
  }
  pthread_attr_destroy(&attr);
}
#else
static void start_workers(void) {}
#endif

// The main expression, while it is started on its own stack.
static Idris2_Value *(*main_action)(void) = NULL;
// The context of the process stack, to come back to when main is done.
static Context process_ctx;

static void main_entry(void) {
  idris2_trampoline(main_action());
  // Back to the process stack, from whichever worker the main thread runs
  // on now: the program ends there.
  context_switch(&main_thread.ctx, &process_ctx);
  fatal("the main thread was resumed after it finished");
}

// Run the main expression on a stack of its own.  Returns 0, without running
// it, when that stack cannot be allocated.
static int run_main_on_own_stack(Idris2_Value *(*mainAction)(void)) {
  size_t size = stack_size_from_env("IDRIS2_MAIN_STACK_SIZE",
                                    DEFAULT_MAIN_STACK_SIZE);
  void *mapping = stack_try_map(size);
  if (!mapping) {
    return 0;
  }
  main_thread.stack = mapping;
  main_action = mainAction;
  prepare_context(&main_thread.ctx, mapping, size, main_entry);
#ifdef IDRIS2_HAVE_VALGRIND
  main_thread.valgrind_stack_id = VALGRIND_STACK_REGISTER(
      (char *)mapping + page_size, (char *)mapping + page_size + size);
#endif
  context_switch(&process_ctx, &main_thread.ctx);
  // The mapping is left alone: the program is about to end.
  return 1;
}

#endif /* IDRIS2_GREEN_THREADS */

void idris2_threadSchedulerRun(Idris2_Value *(*mainAction)(void)) {
  main_sched.current = &main_thread;
#if IDRIS2_GREEN_THREADS
  scheduler_init();
  if (!run_main_on_own_stack(mainAction))
#endif
  {
    // No stack of its own: run on the stack of the process.
    idris2_trampoline(mainAction());
  }
  // Like in the Chez backend, the program is over once the main expression
  // is done: the other threads, if any, are abandoned.
  thread_finish(&main_thread);
}

int idris2_threadRunsElsewhere(int worker, int64_t thread) {
#if IDRIS2_GREEN_THREADS
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

void *refc_fork(Idris2_Closure *fct) {
#if IDRIS2_GREEN_THREADS
  start_workers();
  Sched *s = self();
  Idris2_Thread *parent = s->current;
  Idris2_Thread *thread = (Idris2_Thread *)calloc(1, sizeof(Idris2_Thread));
  if (!thread) {
    fatal("could not allocate a green thread");
  }
  thread->id = __atomic_fetch_add(&next_thread_id, 1, __ATOMIC_RELAXED);
  thread->state = THREAD_RUNNABLE;
  if (idris2_multicoreStarted) {
    // The new thread may run in parallel with this one.
    idris2_markShared((Idris2_Value *)fct);
    idris2_markShared(parent->thread_data);
  }
  thread->action = (Idris2_Closure *)idris2_newReference((Idris2_Value *)fct);
  // Like the thread parameters of Chez Scheme, the thread local data is
  // inherited from the parent.
  thread->thread_data = idris2_newReference(parent->thread_data);

  Idris2_ThreadID *handle =
      (Idris2_ThreadID *)idris2_newZeroedValue(sizeof(Idris2_ThreadID));
  handle->header.tag = THREAD_ID_TAG;
  handle->id = thread->id;
  if (idris2_multicoreStarted) {
    handle->header.reserved |= IDRIS2_SHARED_FLAG;
  }
  thread->handle = handle; // the reference created by idris2_newValue

  thread->stack = stack_alloc(s);
  prepare_context(&thread->ctx, thread->stack, stack_size, thread_entry);
#ifdef IDRIS2_HAVE_VALGRIND
  thread->valgrind_stack_id =
      VALGRIND_STACK_REGISTER((char *)thread->stack + page_size,
                              (char *)thread->stack + page_size + stack_size);
#endif

  __atomic_fetch_add(&live_threads, 1, __ATOMIC_RELAXED);
  // The reference for the caller must be taken before the new thread gets a
  // chance to run, as the thread drops its own reference when it finishes.
  void *result = idris2_newReference((Idris2_Value *)handle);
  // Let the new thread start right away; an idle worker may take this one
  // over in the meantime.
  runq_put(s, thread, __atomic_load_n(&n_workers, __ATOMIC_RELAXED) > 1);
  idris2_threadYield();
  return result;
#else
  (void)fct;
  fatal("green threads are not supported on this platform");
  return NULL;
#endif
}

void refc_threadWait(Idris2_Value *threadID) {
  Idris2_ThreadID *handle = (Idris2_ThreadID *)threadID;
  if (!handle || handle->id == self()->current->id) {
    return; // waiting for itself
  }
  idris2_spinLock(&handle->lock);
  if (handle->finished) {
    idris2_spinUnlock(&handle->lock);
    return;
  }
  idris2_threadBlockOn(&handle->joiners, &handle->lock);
}

int64_t refc_getThreadId(void) { return self()->current->id; }

void refc_setThreadData(Idris2_Value *erased, Idris2_Value *value) {
  (void)erased;
  Idris2_Thread *thread = self()->current;
  Idris2_Value *previous = thread->thread_data;
  thread->thread_data = idris2_newReference(value);
  idris2_removeReference(previous);
}

void *refc_getThreadData(Idris2_Value *erased) {
  (void)erased;
  // The data stays in the thread: the caller gets a reference of its own.
  return idris2_newReference(self()->current->thread_data);
}
