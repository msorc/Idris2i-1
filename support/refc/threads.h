#pragma once

#include "_datatypes.h"

#include <stdint.h>

// ---------------------------------------------------------------------------
// Green threads
//
// The RefC backend runs Idris programs as a set of "green threads": user
// level threads that are multiplexed onto a single OS thread.  Each forked
// green thread owns a stack, and switching between green threads is done
// with swapcontext(3).  The main expression runs on the stack of the process.
//
// Scheduling is cooperative: a green thread gives up control when it blocks
// on a synchronisation object (a mutex, a condition variable, a semaphore, a
// barrier, a channel or threadWait), when it sleeps, when it forks a thread
// or when it finishes.
//
// Note that this gives concurrency, not parallelism: only one green thread
// runs at any given moment.
// ---------------------------------------------------------------------------

// Entry point used by the generated `main` function.  `mainAction` is the
// compiled main expression.  It is run as the first green thread, and the
// program ends when it is done (the other threads are abandoned).
void idris2_threadSchedulerRun(Idris2_Value *(*mainAction)(void));

// FFI entry points (see Prelude.IO and System.Concurrency).
void *refc_fork(Idris2_Closure *fct);
void refc_threadWait(Idris2_Value *threadID);
int64_t refc_getThreadId(void);
void refc_setThreadData(Idris2_Value *erased, Idris2_Value *value);
void *refc_getThreadData(Idris2_Value *erased);

// The green thread that is currently running.  Never NULL while Idris code
// runs.
Idris2_Thread *idris2_currentThread(void);

// The identifier of a green thread, as returned by `getThreadId`.  The main
// thread is 0.
int64_t idris2_threadId(Idris2_Thread *thread);

// The current time, in nanoseconds, on a monotonic clock.
int64_t idris2_monotonicNanoseconds(void);

// The time on the monotonic clock `microseconds` from now (now if it is not
// positive), saturating instead of overflowing.
int64_t idris2_deadlineAfter(int64_t microseconds);

// Block the current thread until it is woken up through `queue`.
void idris2_threadBlockOn(Idris2_WaitQueue *queue);

// Block the current thread until it is woken up through `queue`, or until
// the monotonic clock reaches `deadline_ns`.  Returns 1 if the thread was
// woken up, and 0 if the deadline expired.  On expiry the thread is removed
// from `queue`, so it cannot be woken up by a later event.
int idris2_threadBlockOnUntil(Idris2_WaitQueue *queue, int64_t deadline_ns);

// Remove the first thread waiting in `queue` without scheduling it.  Returns
// NULL if the queue is empty.
Idris2_Thread *idris2_threadTakeWaiter(Idris2_WaitQueue *queue);

// Make a blocked thread runnable again.  Does nothing if it is not blocked.
void idris2_threadSchedule(Idris2_Thread *thread);

// Wake up the first thread waiting in `queue`, if any.
void idris2_threadWakeOne(Idris2_WaitQueue *queue);

// Wake up all the threads waiting in `queue`.
void idris2_threadWakeAll(Idris2_WaitQueue *queue);

// Let the other runnable threads run before the current one carries on.
void idris2_threadYield(void);

// Sleep for the given number of microseconds.  Unlike a system call, this
// does not block the other green threads.
void idris2_threadSleep(int64_t microseconds);
