#pragma once

#include "_datatypes.h"

#include <time.h>

// ---------------------------------------------------------------------------
// Green threads
//
// The RefC backend runs Idris programs as a set of "green threads": user
// level threads that are multiplexed onto a single OS thread.  Each green
// thread owns a stack, and switching between green threads is done with
// swapcontext(3).
//
// Scheduling is cooperative: a green thread gives up control when it blocks
// on a synchronisation object (a mutex, a condition variable, a semaphore, a
// barrier, a channel or threadWait), when it finishes, or when it is
// explicitly asked to yield.
//
// Note that this gives concurrency, not parallelism: only one green thread
// runs at any given moment.
// ---------------------------------------------------------------------------

typedef enum {
  IDRIS2_THREAD_RUNNABLE = 0,
  IDRIS2_THREAD_BLOCKED = 1,
  IDRIS2_THREAD_FINISHED = 2
} Idris2_ThreadState;

struct Idris2_Thread {
  Idris2_header header;
  // The saved context of the thread.  This is a `ucontext_t *`, but it is
  // kept opaque so that the generated code does not have to include
  // <ucontext.h>, which does not exist on every platform.
  void *ctx;
  void *stack;
  size_t stack_size;
  // The action to run, for threads created by `fork`.  It is a `PrimIO ()`,
  // i.e. a closure waiting for its %World argument.
  Idris2_Closure *action;
  // The entry point, for the thread running the main expression.
  Idris2_Value *(*entry)(void);
  Idris2_ThreadState state;
  int id;
  // The handle handed out to Idris code.
  Idris2_Value *thread_id;
  // Link in the run queue.
  struct Idris2_Thread *next;
  // Link in the list of all the green threads.
  struct Idris2_Thread *all_next;
  // Link in the wait queue of the object this thread is blocked on.
  struct Idris2_Thread *wait_next;
  // Link in the list of threads waiting for this thread to finish.
  struct Idris2_Thread *join_next;
  // Threads waiting for this thread to finish.
  struct Idris2_Thread *joiners;
  // Value handed over directly to this thread (used by channels).
  Idris2_Value *handoff_value;
  // Thread local data, as set by `setThreadData`.
  Idris2_Value *thread_data;
  // Deadline of a timed wait, if any.
  int has_deadline;
  struct timespec deadline;
};

// Entry point used by the generated `main` function.  `mainAction` is the
// compiled main expression; it is run as the first green thread so that
// `fork` and `threadWait` behave the same everywhere.
void idris2_threadSchedulerRun(Idris2_Value *(*mainAction)(void));

// FFI entry points.
void *refc_fork(Idris2_Closure *fct);
void refc_threadWait(Idris2_Value *threadID);

// The green thread that is currently running.
Idris2_Thread *idris2_currentThread(void);

// Block the current thread until it is woken up through `queue`.
void idris2_threadBlockOn(Idris2_WaitQueue *queue);

// Block the current thread until it is woken up through `queue`, or until
// `timeout_us` microseconds have elapsed.  A negative timeout waits forever.
void idris2_threadBlockOnTimeout(Idris2_WaitQueue *queue, long timeout_us);

// Remove the first thread waiting in `queue` without scheduling it.  Returns
// NULL if the queue is empty.
Idris2_Thread *idris2_threadTakeWaiter(Idris2_WaitQueue *queue);

// Remove a thread from a wait queue.  This is needed when a timed wait
// expires: the thread is no longer waiting for the event, so it must not be
// woken up by it.  Returns true if the thread was in the queue.
int idris2_threadRemoveWaiter(Idris2_WaitQueue *queue, Idris2_Thread *thread);

// Make a thread runnable again.
void idris2_threadSchedule(Idris2_Thread *thread);

// Wake up the first thread waiting in `queue`, if any.
void idris2_threadWakeOne(Idris2_WaitQueue *queue);

// Wake up all the threads waiting in `queue`.
void idris2_threadWakeAll(Idris2_WaitQueue *queue);

// Give up the rest of the current thread's time slice.
void idris2_threadYield(void);

// Sleep for the given number of microseconds.  Unlike a system call, this
// does not block the other green threads.
void idris2_threadSleep(long microseconds);
