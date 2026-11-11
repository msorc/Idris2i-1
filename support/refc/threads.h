#pragma once

#include "_datatypes.h"

#include <stdint.h>

// ---------------------------------------------------------------------------
// Green threads
//
// The RefC backend runs Idris programs as a set of "green threads": user
// level threads that the scheduler in threads.c runs on a pool of OS threads,
// the workers (see worker.h).  Each forked green thread owns a stack, and
// switching between green threads takes a few instructions.  The main
// expression runs on a large stack of its own (see IDRIS2_MAIN_STACK_SIZE in
// threads.c).
//
// A worker runs a green thread until it blocks on a synchronisation object
// (a mutex, a condition variable, a semaphore, a barrier, a channel or
// threadWait), sleeps, forks a thread or finishes; the idle workers take
// work from the busy ones.  So the green threads run in parallel, one per
// worker at a time.  There is one worker per processor, or as many as the
// IDRIS2_WORKERS environment variable says; the program has a single one
// until it forks its first thread.
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

// Block the current thread until it is woken up through `queue`.  `lock`
// guards the queue: the caller holds it, and it is released once the thread
// is blocked (it is not held any more when this returns).
void idris2_threadBlockOn(Idris2_WaitQueue *queue, Idris2_SpinLock *lock);

// Block the current thread until it is woken up through `queue`, or until
// the monotonic clock reaches `deadline_ns`, as idris2_threadBlockOn.
// Returns 1 if the thread was woken up, and 0 if the deadline expired.  On
// expiry the thread is removed from `queue`, so it cannot be woken up by a
// later event.
int idris2_threadBlockOnUntil(Idris2_WaitQueue *queue, Idris2_SpinLock *lock,
                              int64_t deadline_ns);

// Remove the first thread waiting in `queue` without scheduling it.  Returns
// NULL if the queue is empty.  The caller holds the lock of the queue.  The
// queue must not have threads waiting with a deadline.
Idris2_Thread *idris2_threadTakeWaiter(Idris2_WaitQueue *queue);

// Make a thread taken with idris2_threadTakeWaiter runnable again.
void idris2_threadSchedule(Idris2_Thread *thread);

// Wake up the first thread waiting in `queue`, if any (one whose deadline
// has not expired).  The caller holds the lock of the queue.  Returns 1 when
// a thread was woken up.
int idris2_threadWakeOne(Idris2_WaitQueue *queue);

// Wake up all the threads waiting in `queue`.  The caller holds the lock of
// the queue.
void idris2_threadWakeAll(Idris2_WaitQueue *queue);

// Let the other runnable threads run before the current one carries on.
void idris2_threadYield(void);

// Sleep for the given number of microseconds.  Unlike a system call, this
// does not block the other green threads.
void idris2_threadSleep(int64_t microseconds);

// Are several workers running?
int idris2_threadsInParallel(void);

// The index of the current worker.
int idris2_workerIndex(void);

// Is the thread `thread` running on the worker `worker`, another one than
// the current one, which has nothing else to do?  (Then a lock that the
// thread holds is worth spinning on for a while, as it runs at the same
// time.)
int idris2_threadRunsElsewhere(int worker, int64_t thread);
