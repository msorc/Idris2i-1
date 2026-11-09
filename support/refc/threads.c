// ---------------------------------------------------------------------------
// Green threads for the RefC backend.
//
// Idris programs compiled by the RefC backend run as a set of "green
// threads": user level threads that are multiplexed onto a single OS thread.
// Each green thread owns a stack and switching between green threads is done
// with swapcontext(3).
//
// Scheduling is cooperative.  A green thread gives up control when it blocks
// on a synchronisation object, when it finishes, or when it yields.
// ---------------------------------------------------------------------------

#include "threads.h"
#include "memoryManagement.h"
#include "refc_util.h"
#include "runtime.h"

#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>

#if defined(_WIN32) || defined(__wasi__) || defined(__EMSCRIPTEN__)
// Windows (and WebAssembly) do not provide the POSIX context switching API,
// so green threads are not supported there yet.  See the bottom of this file
// for the fallback implementation.
#define IDRIS2_NO_GREEN_THREADS 1
#elif defined(__unix__) || defined(__APPLE__) || defined(__CYGWIN__)
#include <ucontext.h>
#else
// Unknown platform: assume that it does not have the POSIX context switching
// API.
#define IDRIS2_NO_GREEN_THREADS 1
#endif

#ifndef IDRIS2_NO_GREEN_THREADS

// The context of the scheduler.  Whenever a green thread blocks, it switches
// back to this context; the scheduler then picks the next runnable thread.
static ucontext_t sched_ctx;

// The green thread that is currently running.
static Idris2_Thread *current_thread = NULL;

// The run queue of runnable green threads (a plain FIFO queue).
static Idris2_Thread *runq_head = NULL;
static Idris2_Thread *runq_tail = NULL;

// The number of green threads that have not finished yet.
static int live_threads = 0;

// All the green threads that have been created.  The list is only used to
// find the threads with an expired deadline.
static Idris2_Thread *all_threads = NULL;

// The number of green threads that have been created so far.
static int next_thread_id = 0;

// The size of the stacks allocated for green threads.
static size_t thread_stack_size = 0;

// ---------------------------------------------------------------------------
// Run queue
// ---------------------------------------------------------------------------

static void runq_push(Idris2_Thread *thread) {
  thread->next = NULL;
  if (runq_tail) {
    runq_tail->next = thread;
    runq_tail = thread;
  } else {
    runq_head = runq_tail = thread;
  }
}

static Idris2_Thread *runq_pop(void) {
  Idris2_Thread *thread = runq_head;
  if (!thread) {
    return NULL;
  }
  runq_head = thread->next;
  if (!runq_head) {
    runq_tail = NULL;
  }
  thread->next = NULL;
  return thread;
}

// ---------------------------------------------------------------------------
// Wait queues
// ---------------------------------------------------------------------------

static void waitq_push(Idris2_WaitQueue *queue, Idris2_Thread *thread) {
  thread->wait_next = NULL;
  if (queue->tail) {
    queue->tail->wait_next = thread;
    queue->tail = thread;
  } else {
    queue->head = queue->tail = thread;
  }
}

Idris2_Thread *idris2_threadTakeWaiter(Idris2_WaitQueue *queue) {
  Idris2_Thread *thread = queue->head;
  if (!thread) {
    return NULL;
  }
  queue->head = thread->wait_next;
  if (!queue->head) {
    queue->tail = NULL;
  }
  thread->wait_next = NULL;
  return thread;
}

int idris2_threadRemoveWaiter(Idris2_WaitQueue *queue, Idris2_Thread *thread) {
  Idris2_Thread *previous = NULL;
  Idris2_Thread *current = queue->head;
  while (current) {
    if (current == thread) {
      if (previous) {
        previous->wait_next = current->wait_next;
      } else {
        queue->head = current->wait_next;
      }
      if (queue->tail == current) {
        queue->tail = previous;
      }
      current->wait_next = NULL;
      return 1;
    }
    previous = current;
    current = current->wait_next;
  }
  return 0;
}

void idris2_threadSchedule(Idris2_Thread *thread) {  thread->state = IDRIS2_THREAD_RUNNABLE;
  runq_push(thread);
}

void idris2_threadWakeOne(Idris2_WaitQueue *queue) {
  Idris2_Thread *thread = idris2_threadTakeWaiter(queue);
  if (thread) {
    idris2_threadSchedule(thread);
  }
}

void idris2_threadWakeAll(Idris2_WaitQueue *queue) {
  Idris2_Thread *thread;
  while ((thread = idris2_threadTakeWaiter(queue)) != NULL) {
    idris2_threadSchedule(thread);
  }
}

// ---------------------------------------------------------------------------
// Blocking and yielding
// ---------------------------------------------------------------------------

Idris2_Thread *idris2_currentThread(void) { return current_thread; }

static void thread_set_deadline(Idris2_Thread *thread, long timeout_us) {
  if (timeout_us < 0) {
    thread->has_deadline = 0;
    return;
  }
  clock_gettime(CLOCK_MONOTONIC, &thread->deadline);
  thread->deadline.tv_sec += (time_t)(timeout_us / 1000000);
  thread->deadline.tv_nsec += (long)(timeout_us % 1000000) * 1000;
  if (thread->deadline.tv_nsec >= 1000000000) {
    thread->deadline.tv_nsec -= 1000000000;
    thread->deadline.tv_sec += 1;
  }
  thread->has_deadline = 1;
}

void idris2_threadBlockOn(Idris2_WaitQueue *queue) {
  Idris2_Thread *self = current_thread;
  if (!self) {
    return;
  }
  self->state = IDRIS2_THREAD_BLOCKED;
  self->has_deadline = 0;
  waitq_push(queue, self);
  swapcontext((ucontext_t *)self->ctx, &sched_ctx);
}

void idris2_threadBlockOnTimeout(Idris2_WaitQueue *queue, long timeout_us) {
  Idris2_Thread *self = current_thread;
  if (!self) {
    return;
  }
  self->state = IDRIS2_THREAD_BLOCKED;
  thread_set_deadline(self, timeout_us);
  waitq_push(queue, self);
  swapcontext((ucontext_t *)self->ctx, &sched_ctx);
}

void idris2_threadYield(void) {
  Idris2_Thread *self = current_thread;
  if (!self) {
    return;
  }
  self->state = IDRIS2_THREAD_RUNNABLE;
  runq_push(self);
  swapcontext((ucontext_t *)self->ctx, &sched_ctx);
}

void idris2_threadSleep(long microseconds) {
  Idris2_Thread *self = current_thread;
  if (microseconds <= 0) {
    return;
  }
  if (!self) {
    // Not running under the scheduler: fall back to a system call.
    struct timespec request;
    request.tv_sec = (time_t)(microseconds / 1000000);
    request.tv_nsec = (long)(microseconds % 1000000) * 1000;
    while (nanosleep(&request, &request) == -1 && errno == EINTR) {
      // Retry with the remaining time.
    }
    return;
  }
  // The thread is not waiting for an event, only for its deadline to expire.
  self->state = IDRIS2_THREAD_BLOCKED;
  thread_set_deadline(self, microseconds);
  swapcontext((ucontext_t *)self->ctx, &sched_ctx);
}

// ---------------------------------------------------------------------------
// Threads
// ---------------------------------------------------------------------------

static Idris2_Value *thread_id_new(Idris2_Thread *thread) {
  Idris2_ThreadID *id =
      (Idris2_ThreadID *)idris2_newZeroedValue(sizeof(Idris2_ThreadID));
  id->header.tag = THREAD_ID_TAG;
  id->thread = thread;
  // The handle is owned by the runtime, so it must never be collected.
  id->header.refCounter = IDRIS2_VP_REFCOUNTER_MAX;
  return (Idris2_Value *)id;
}

// The body of every green thread.  It runs the thread's action and then hands
// control back to the scheduler.
static void thread_trampoline(void) {
  Idris2_Thread *self = current_thread;

  if (self->entry) {
    idris2_trampoline(self->entry());
  } else if (self->action) {
    Idris2_Closure *action = self->action;
    self->action = NULL;
    // Running the action applies its %World argument, which consumes the
    // reference to it, so it must not be released here.
    idris2_run_primio(action);
  }

  self->state = IDRIS2_THREAD_FINISHED;
  self->has_deadline = 0;
  live_threads--;

  // Release the thread local data, if any.
  if (self->thread_data) {
    idris2_removeReference(self->thread_data);
    self->thread_data = NULL;
  }

  // Wake up the threads waiting for this one to finish.
  Idris2_Thread *joiner = self->joiners;
  self->joiners = NULL;
  while (joiner) {
    Idris2_Thread *next = joiner->join_next;
    joiner->join_next = NULL;
    joiner->state = IDRIS2_THREAD_RUNNABLE;
    runq_push(joiner);
    joiner = next;
  }

  // Give control back to the scheduler.  This never returns.
  swapcontext((ucontext_t *)self->ctx, &sched_ctx);

  fprintf(stderr, "RefC: green thread returned unexpectedly\n");
  exit(1);
}

static size_t default_thread_stack_size(void) {
  if (thread_stack_size == 0) {
    // The default matches the stack size of a typical process, so that
    // programs behave the same whether they run on the main thread or on a
    // green thread.  It can be overridden with IDRIS2_THREAD_STACK_SIZE.
    thread_stack_size = 8 * 1024 * 1024;
    const char *env = getenv("IDRIS2_THREAD_STACK_SIZE");
    if (env) {
      long size = atol(env);
      if (size >= 64 * 1024) {
        thread_stack_size = (size_t)size;
      }
    }
  }
  return thread_stack_size;
}

static Idris2_Thread *thread_create(Idris2_Closure *action,
                                    Idris2_Value *(*entry)(void)) {
  Idris2_Thread *thread =
      (Idris2_Thread *)idris2_newZeroedValue(sizeof(Idris2_Thread));
  thread->header.tag = THREAD_TAG;
  thread->header.refCounter = IDRIS2_VP_REFCOUNTER_MAX;
  thread->action = action;
  thread->entry = entry;
  thread->state = IDRIS2_THREAD_RUNNABLE;
  thread->id = next_thread_id++;
  thread->stack_size = default_thread_stack_size();
  thread->stack = malloc(thread->stack_size);
  if (!thread->stack) {
    fprintf(stderr, "RefC: could not allocate a stack for a green thread\n");
    exit(1);
  }
  thread->thread_id = thread_id_new(thread);

  thread->all_next = all_threads;
  all_threads = thread;

  ucontext_t *ctx = (ucontext_t *)malloc(sizeof(ucontext_t));
  if (!ctx) {
    fprintf(stderr, "RefC: could not allocate a context for a green thread\n");
    exit(1);
  }
  thread->ctx = ctx;
  getcontext(ctx);
  ctx->uc_stack.ss_sp = thread->stack;
  ctx->uc_stack.ss_size = thread->stack_size;
  ctx->uc_link = NULL;
  makecontext(ctx, thread_trampoline, 0);

  live_threads++;
  return thread;
}

// ---------------------------------------------------------------------------
// The scheduler
// ---------------------------------------------------------------------------

// Returns the thread with the earliest deadline, or NULL if no thread has a
// deadline.
static Idris2_Thread *earliest_deadline(void) {
  Idris2_Thread *earliest = NULL;
  for (Idris2_Thread *thread = all_threads; thread; thread = thread->all_next) {
    if (!thread->has_deadline || thread->state != IDRIS2_THREAD_BLOCKED) {
      continue;
    }
    if (!earliest ||
        thread->deadline.tv_sec < earliest->deadline.tv_sec ||
        (thread->deadline.tv_sec == earliest->deadline.tv_sec &&
         thread->deadline.tv_nsec < earliest->deadline.tv_nsec)) {
      earliest = thread;
    }
  }
  return earliest;
}

static void scheduler_run(void) {
  for (;;) {
    Idris2_Thread *thread = runq_pop();
    if (!thread) {
      // Nothing is runnable.  If some threads are waiting for a deadline,
      // sleep until the earliest one expires.
      Idris2_Thread *waiting = earliest_deadline();
      if (waiting) {
        struct timespec now;
        clock_gettime(CLOCK_MONOTONIC, &now);
        struct timespec deadline = waiting->deadline;
        long long nsec = (long long)(deadline.tv_sec - now.tv_sec) * 1000000000LL +
                         (deadline.tv_nsec - now.tv_nsec);
        if (nsec > 0) {
          struct timespec request;
          request.tv_sec = (time_t)(nsec / 1000000000LL);
          request.tv_nsec = (long)(nsec % 1000000000LL);
          while (nanosleep(&request, &request) == -1 && errno == EINTR) {
            // Retry with the remaining time.
          }
        }
        // Wake up every thread whose deadline has expired.
        for (Idris2_Thread *t = all_threads; t; t = t->all_next) {
          if (t->has_deadline && t->state == IDRIS2_THREAD_BLOCKED) {
            clock_gettime(CLOCK_MONOTONIC, &now);
            if (t->deadline.tv_sec < now.tv_sec ||
                (t->deadline.tv_sec == now.tv_sec &&
                 t->deadline.tv_nsec <= now.tv_nsec)) {
              t->has_deadline = 0;
              idris2_threadSchedule(t);
            }
          }
        }
        continue;
      }
      if (live_threads == 0) {
        break;
      }
      fprintf(stderr,
              "RefC: deadlock detected, %d green thread(s) are blocked\n",
              live_threads);
      exit(1);
    }

    current_thread = thread;
    swapcontext(&sched_ctx, (ucontext_t *)thread->ctx);
    current_thread = NULL;

    if (thread->state == IDRIS2_THREAD_FINISHED && thread->stack) {
      free(thread->stack);
      thread->stack = NULL;
    }
  }
}

void idris2_threadSchedulerRun(Idris2_Value *(*mainAction)(void)) {
  // The main expression runs as the first green thread, so that `fork` and
  // `threadWait` behave the same whether they are called from the main
  // expression or from a forked thread.
  Idris2_Thread *mainThread = thread_create(NULL, mainAction);
  runq_push(mainThread);
  scheduler_run();
}

// ---------------------------------------------------------------------------
// FFI
// ---------------------------------------------------------------------------

void *refc_fork(Idris2_Closure *fct) {
  if (!fct) {
    return NULL;
  }
  // The thread takes over the reference to the action.
  idris2_newReference((Idris2_Value *)fct);
  Idris2_Thread *thread = thread_create(fct, NULL);
  runq_push(thread);
  // Let the new thread start immediately: it runs until it blocks or
  // finishes.
  idris2_threadYield();
  return (void *)thread->thread_id;
}

void refc_threadWait(Idris2_Value *threadID) {
  if (!threadID) {
    return;
  }
  Idris2_ThreadID *id = (Idris2_ThreadID *)threadID;
  Idris2_Thread *target = id->thread;
  Idris2_Thread *self = current_thread;
  if (!target || !self || target == self) {
    return;
  }
  if (target->state == IDRIS2_THREAD_FINISHED) {
    return;
  }
  self->state = IDRIS2_THREAD_BLOCKED;
  self->has_deadline = 0;
  self->join_next = target->joiners;
  target->joiners = self;
  swapcontext((ucontext_t *)self->ctx, &sched_ctx);
}

#else /* IDRIS2_NO_GREEN_THREADS */

// ---------------------------------------------------------------------------
// The fallback implementation, for the platforms that do not support green
// threads.
//
// The program is run in a single thread, and forking a thread is an error.
// ---------------------------------------------------------------------------

void idris2_threadSchedulerRun(Idris2_Value *(*mainAction)(void)) {
  idris2_trampoline(mainAction());
}

void *refc_fork(Idris2_Closure *fct) {
  (void)fct;
  fprintf(stderr, "RefC: green threads are not supported on this platform\n");
  exit(1);
}

void refc_threadWait(Idris2_Value *threadID) { (void)threadID; }

Idris2_Thread *idris2_currentThread(void) { return NULL; }

void idris2_threadBlockOn(Idris2_WaitQueue *queue) { (void)queue; }

void idris2_threadBlockOnTimeout(Idris2_WaitQueue *queue, long timeout_us) {
  (void)queue;
  (void)timeout_us;
}

Idris2_Thread *idris2_threadTakeWaiter(Idris2_WaitQueue *queue) {
  (void)queue;
  return NULL;
}

int idris2_threadRemoveWaiter(Idris2_WaitQueue *queue, Idris2_Thread *thread) {
  (void)queue;
  (void)thread;
  return 0;
}

void idris2_threadSchedule(Idris2_Thread *thread) { (void)thread; }

void idris2_threadWakeOne(Idris2_WaitQueue *queue) { (void)queue; }

void idris2_threadWakeAll(Idris2_WaitQueue *queue) { (void)queue; }

void idris2_threadYield(void) {}

void idris2_threadSleep(long microseconds) {
  if (microseconds <= 0) {
    return;
  }
  struct timespec request;
  request.tv_sec = (time_t)(microseconds / 1000000);
  request.tv_nsec = (long)(microseconds % 1000000) * 1000;
  while (nanosleep(&request, &request) == -1 && errno == EINTR) {
    // Retry with the remaining time.
  }
}

#endif /* IDRIS2_NO_GREEN_THREADS */
