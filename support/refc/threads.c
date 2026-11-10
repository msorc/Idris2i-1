// ---------------------------------------------------------------------------
// Green threads for the RefC backend.
//
// Idris programs compiled by the RefC backend run as a set of "green
// threads": user level threads that are multiplexed onto a single OS thread.
//
// * The main expression runs on a large stack of its own (4GB by default on
//   64-bit systems), like in the Chez backend where the stack grows as
//   needed: much of the library is not tail recursive, so a deep stack is
//   needed to work on long lists.  The memory is only used as the stack
//   grows.
// * Every forked thread owns a stack, allocated with mmap(2) and protected
//   by a guard page, so that a stack overflow crashes the program instead of
//   silently corrupting memory.
// * The scheduler runs on a small stack of its own.  A thread that blocks
//   switches to the scheduler, which picks the next runnable thread, wakes
//   up the threads whose deadline has expired, or sleeps until the earliest
//   deadline.
// * Switching between threads is done by a few lines of assembly on x86-64
//   and AArch64, and with swapcontext(3) elsewhere.  swapcontext saves and
//   restores the signal mask, which costs a system call per switch.
//
// Scheduling is cooperative: a thread runs until it blocks, sleeps, forks a
// thread or finishes.  The program ends when the main expression is done,
// like in the Chez backend.
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

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#if defined(_WIN32) || defined(__wasi__) || defined(__EMSCRIPTEN__)
#define IDRIS2_GREEN_THREADS 0
#elif defined(__unix__) || defined(__APPLE__)
#define IDRIS2_GREEN_THREADS 1
#else
// Unknown platform: assume that it does not have the POSIX context switching
// API.
#define IDRIS2_GREEN_THREADS 0
#endif

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
#include <stdint.h>
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
  THREAD_RUNNABLE = 0, // running, or waiting in the run queue
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
  // Threads waiting for this thread to finish.
  Idris2_WaitQueue joiners;
  // Link in the run queue.
  Idris2_Thread *run_next;
  // The queue this thread is waiting in (if any), and the link in it.
  Idris2_WaitQueue *wait_queue;
  Idris2_Thread *wait_next;
  // The deadline of a timed wait (if any), and the link in the timer list.
  int has_deadline;
  int timed_out;
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

// The main thread is statically allocated, so that there is always a current
// thread, even before the scheduler starts.
static Idris2_Thread main_thread;
static Idris2_Thread *current_thread = &main_thread;

// The threads with a deadline, sorted by deadline.
static Idris2_Thread *timers = NULL;

#if IDRIS2_GREEN_THREADS
// The run queue (FIFO).
static Idris2_Thread *runq_head = NULL;
static Idris2_Thread *runq_tail = NULL;

// The main thread has identifier 0.
static int64_t next_thread_id = 1;

// The number of threads that have not finished yet, the main one included.
static int64_t live_threads = 1;
#endif

static void fatal(const char *message) {
  fprintf(stderr, "RefC: %s\n", message);
  exit(1);
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
    return INT64_MAX;
  }
  return now + microseconds * 1000;
}

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

// ---------------------------------------------------------------------------
// Queues
// ---------------------------------------------------------------------------

#if IDRIS2_GREEN_THREADS
static void runq_push(Idris2_Thread *thread) {
  thread->run_next = NULL;
  if (runq_tail) {
    runq_tail->run_next = thread;
  } else {
    runq_head = thread;
  }
  runq_tail = thread;
}

static Idris2_Thread *runq_pop(void) {
  Idris2_Thread *thread = runq_head;
  if (thread) {
    runq_head = thread->run_next;
    if (!runq_head) {
      runq_tail = NULL;
    }
    thread->run_next = NULL;
  }
  return thread;
}
#endif

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

static void timer_insert(Idris2_Thread *thread, int64_t deadline_ns) {
  thread->has_deadline = 1;
  thread->deadline_ns = deadline_ns;
  // Keep the list sorted; threads with the same deadline stay in FIFO order.
  Idris2_Thread **link = &timers;
  while (*link && (*link)->deadline_ns <= deadline_ns) {
    link = &(*link)->timer_next;
  }
  thread->timer_next = *link;
  *link = thread;
}

static void timer_remove(Idris2_Thread *thread) {
  for (Idris2_Thread **link = &timers; *link; link = &(*link)->timer_next) {
    if (*link == thread) {
      *link = thread->timer_next;
      break;
    }
  }
  thread->has_deadline = 0;
  thread->timer_next = NULL;
}

// ---------------------------------------------------------------------------
// Blocking and waking up
// ---------------------------------------------------------------------------

// Detach a blocked thread from whatever it is waiting for.
static void thread_unblock(Idris2_Thread *thread, int timed_out) {
  if (thread->wait_queue) {
    waitq_remove(thread->wait_queue, thread);
  }
  if (thread->has_deadline) {
    timer_remove(thread);
  }
  thread->timed_out = timed_out;
  thread->state = THREAD_RUNNABLE;
}

void idris2_threadSchedule(Idris2_Thread *thread) {
  if (!thread || thread->state != THREAD_BLOCKED) {
    return;
  }
  thread_unblock(thread, 0);
#if IDRIS2_GREEN_THREADS
  runq_push(thread);
#endif
}

void idris2_threadWakeOne(Idris2_WaitQueue *queue) {
  idris2_threadSchedule(idris2_threadTakeWaiter(queue));
}

void idris2_threadWakeAll(Idris2_WaitQueue *queue) {
  Idris2_Thread *thread;
  while ((thread = idris2_threadTakeWaiter(queue)) != NULL) {
    idris2_threadSchedule(thread);
  }
}

#if IDRIS2_GREEN_THREADS
// Make the threads whose deadline has expired runnable again.
static void expire_timers(void) {
  if (!timers) {
    return;
  }
  int64_t now = idris2_monotonicNanoseconds();
  while (timers && timers->deadline_ns <= now) {
    Idris2_Thread *thread = timers;
    thread_unblock(thread, 1);
    runq_push(thread);
  }
}

static Context sched_ctx;
#endif

// Give control away until the current thread, which is blocked, is woken up.
static void switch_out(Idris2_Thread *self) {
#if IDRIS2_GREEN_THREADS
  context_switch(&self->ctx, &sched_ctx);
#else
  // There is no other thread to wake us up: only a deadline can.
  if (!self->has_deadline) {
    fatal("deadlock detected: the only thread is blocked forever (green "
          "threads are not supported on this platform)");
  }
  sleep_until(self->deadline_ns);
  thread_unblock(self, 1);
#endif
}

static int block_current(Idris2_WaitQueue *queue, int64_t deadline_ns) {
  Idris2_Thread *self = current_thread;
  self->state = THREAD_BLOCKED;
  self->timed_out = 0;
  if (queue) {
    waitq_push(queue, self);
  }
  if (deadline_ns != NO_DEADLINE) {
    timer_insert(self, deadline_ns);
  }
  switch_out(self);
  return !self->timed_out;
}

Idris2_Thread *idris2_currentThread(void) { return current_thread; }

int64_t idris2_threadId(Idris2_Thread *thread) {
  return thread ? thread->id : 0;
}

void idris2_threadBlockOn(Idris2_WaitQueue *queue) {
  block_current(queue, NO_DEADLINE);
}

int idris2_threadBlockOnUntil(Idris2_WaitQueue *queue, int64_t deadline_ns) {
  if (deadline_ns < 0) {
    deadline_ns = 0;
  }
  return block_current(queue, deadline_ns);
}

void idris2_threadYield(void) {
#if IDRIS2_GREEN_THREADS
  expire_timers();
  if (!runq_head) {
    return; // nobody else wants to run
  }
  Idris2_Thread *self = current_thread;
  self->state = THREAD_RUNNABLE;
  runq_push(self);
  context_switch(&self->ctx, &sched_ctx);
#endif
}

void idris2_threadSleep(int64_t microseconds) {
  if (microseconds <= 0) {
    return;
  }
  block_current(NULL, idris2_deadlineAfter(microseconds));
}

// ---------------------------------------------------------------------------
// Thread lifecycle
// ---------------------------------------------------------------------------

// Called on the stack of the thread, once its action is done.
static void thread_finish(Idris2_Thread *self) {
  self->state = THREAD_FINISHED;
#if IDRIS2_GREEN_THREADS
  live_threads--;
#endif
  if (self->thread_data) {
    idris2_removeReference(self->thread_data);
    self->thread_data = NULL;
  }
  idris2_threadWakeAll(&self->joiners);
  if (self->handle) {
    // From now on the handle says that the thread is finished.
    self->handle->thread = NULL;
    idris2_removeReference((Idris2_Value *)self->handle);
    self->handle = NULL;
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

// The stacks of the finished threads are kept for reuse, up to a limit.
#define STACK_CACHE_SIZE 16
static void *stack_cache[STACK_CACHE_SIZE];
static int stack_cache_count = 0;

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
  void *mapping = mmap(NULL, size + page_size, PROT_READ | PROT_WRITE,
                       MAP_PRIVATE | MAP_ANONYMOUS | MAP_NORESERVE, -1, 0);
  if (mapping == MAP_FAILED) {
    fatal("could not allocate the stack of a green thread");
  }
  // Without a guard page the program still works, it just loses the
  // protection against stack overflows.
  (void)mprotect(mapping, page_size, PROT_NONE);
  return mapping;
}

static void *stack_alloc(void) {
  if (stack_cache_count > 0) {
    return stack_cache[--stack_cache_count];
  }
  return stack_map(stack_size);
}

static void stack_release(void *mapping) {
  if (stack_cache_count < STACK_CACHE_SIZE) {
    stack_cache[stack_cache_count++] = mapping;
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
static void thread_destroy(Idris2_Thread *thread) {
#ifdef IDRIS2_HAVE_VALGRIND
  VALGRIND_STACK_DEREGISTER(thread->valgrind_stack_id);
#endif
  stack_release(thread->stack);
  free(thread);
}

// The body of every forked thread.
static void thread_entry(void) {
  Idris2_Thread *self = current_thread;
  Idris2_Closure *action = self->action;
  self->action = NULL;
  // This consumes the reference to the action.
  idris2_removeReference(idris2_run_primio(action));
  thread_finish(self);
  // Hand control back to the scheduler for good; it frees this thread.
  context_switch(&self->ctx, &sched_ctx);
  fatal("a finished green thread was resumed");
}

static void scheduler_loop(void) {
  for (;;) {
    expire_timers();
    Idris2_Thread *thread = runq_pop();
    if (!thread) {
      if (timers) {
        // Nothing to do until the earliest deadline.
        sleep_until(timers->deadline_ns);
        continue;
      }
      fprintf(stderr,
              "RefC: deadlock detected: all the %lld remaining green "
              "thread(s) are blocked forever\n",
              (long long)live_threads);
      exit(1);
    }
    current_thread = thread;
    context_switch(&sched_ctx, &thread->ctx);
    if (thread->state == THREAD_FINISHED && thread != &main_thread) {
      thread_destroy(thread);
    }
  }
}

static void scheduler_init(void) {
  stack_configure();
  sched_stack = stack_map(SCHEDULER_STACK_SIZE);
  prepare_context(&sched_ctx, sched_stack, SCHEDULER_STACK_SIZE,
                  scheduler_loop);
#ifdef IDRIS2_HAVE_VALGRIND
  (void)VALGRIND_STACK_REGISTER((char *)sched_stack + page_size,
                                (char *)sched_stack + page_size +
                                    SCHEDULER_STACK_SIZE);
#endif
}

// The main expression, while it is started on its own stack.
static Idris2_Value *(*main_action)(void) = NULL;
// The context of the process stack, to come back to when main is done.
static Context process_ctx;

static void main_entry(void) {
  idris2_trampoline(main_action());
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
  current_thread = &main_thread;
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

// ---------------------------------------------------------------------------
// FFI
// ---------------------------------------------------------------------------

void *refc_fork(Idris2_Closure *fct) {
#if IDRIS2_GREEN_THREADS
  Idris2_Thread *thread = (Idris2_Thread *)calloc(1, sizeof(Idris2_Thread));
  if (!thread) {
    fatal("could not allocate a green thread");
  }
  thread->id = next_thread_id++;
  thread->state = THREAD_RUNNABLE;
  thread->action = (Idris2_Closure *)idris2_newReference((Idris2_Value *)fct);
  // Like the thread parameters of Chez Scheme, the thread local data is
  // inherited from the parent.
  thread->thread_data = idris2_newReference(current_thread->thread_data);

  Idris2_ThreadID *handle =
      (Idris2_ThreadID *)idris2_newValue(sizeof(Idris2_ThreadID));
  handle->header.tag = THREAD_ID_TAG;
  handle->thread = thread;
  thread->handle = handle; // the reference created by idris2_newValue

  thread->stack = stack_alloc();
  prepare_context(&thread->ctx, thread->stack, stack_size, thread_entry);
#ifdef IDRIS2_HAVE_VALGRIND
  thread->valgrind_stack_id =
      VALGRIND_STACK_REGISTER((char *)thread->stack + page_size,
                              (char *)thread->stack + page_size + stack_size);
#endif

  live_threads++;
  runq_push(thread);

  // The reference for the caller must be taken before the new thread gets a
  // chance to run, as the thread drops its own reference when it finishes.
  void *result = idris2_newReference((Idris2_Value *)handle);
  // Let the new thread start right away.
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
  if (!handle || !handle->thread || handle->thread == current_thread) {
    return; // already finished (or waiting for itself)
  }
  idris2_threadBlockOn(&handle->thread->joiners);
}

int64_t refc_getThreadId(void) { return current_thread->id; }

void refc_setThreadData(Idris2_Value *erased, Idris2_Value *value) {
  (void)erased;
  Idris2_Value *previous = current_thread->thread_data;
  current_thread->thread_data = idris2_newReference(value);
  idris2_removeReference(previous);
}

void *refc_getThreadData(Idris2_Value *erased) {
  (void)erased;
  // The data stays in the thread: the caller gets a reference of its own.
  return idris2_newReference(current_thread->thread_data);
}
