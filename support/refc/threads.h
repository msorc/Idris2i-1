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
// expression runs on a large stack of its own (see IDRIS2I_1_MAIN_STACK_SIZE in
// threads.c).
//
// A worker runs a green thread until it blocks on a synchronisation object
// (a mutex, a condition variable, a semaphore, a barrier, a channel or
// threadWait), sleeps, forks a thread or finishes; the idle workers take
// work from the busy ones.  So the green threads run in parallel, one per
// worker at a time.  There is one worker per processor, or as many as the
// IDRIS2I_1_WORKERS environment variable says; the program has a single one
// until it forks its first thread.
// ---------------------------------------------------------------------------

// Entry point used by the generated `main` function.  `mainAction` is the
// compiled main expression.  It is run as the first green thread, and the
// program ends when it is done (the other threads are abandoned).
void idris2i_1_threadSchedulerRun(Idris2i_1_Value *(*mainAction)(void));

// FFI entry points (see Prelude.IO and System.Concurrency).
void *refc_fork(Idris2i_1_Closure *fct);
void refc_threadWait(Idris2i_1_Value *threadID);
int64_t refc_getThreadId(void);
void refc_setThreadData(Idris2i_1_Value *erased, Idris2i_1_Value *value);
void *refc_getThreadData(Idris2i_1_Value *erased);

// The green thread that is currently running.  Never NULL while Idris code
// runs.
Idris2i_1_Thread *idris2i_1_currentThread(void);

// The identifier of a green thread, as returned by `getThreadId`.  The main
// thread is 0.
int64_t idris2i_1_threadId(Idris2i_1_Thread *thread);

// Is `addr` in (or just below) the guard page of the stack of the current
// green thread?  For the report of a stack overflow (see backtrace.c).
int idris2i_1_threadStackGuard(const void *addr);

// The current time, in nanoseconds, on a monotonic clock.
int64_t idris2i_1_monotonicNanoseconds(void);

// The time on the monotonic clock `microseconds` from now (now if it is not
// positive), saturating instead of overflowing.
int64_t idris2i_1_deadlineAfter(int64_t microseconds);

// Block the current thread until it is woken up through `queue`.  `lock`
// guards the queue: the caller holds it, and it is released once the thread
// is blocked (it is not held any more when this returns).
void idris2i_1_threadBlockOn(Idris2i_1_WaitQueue *queue, Idris2i_1_SpinLock *lock);

// Block the current thread until it is woken up through `queue`, or until
// the monotonic clock reaches `deadline_ns`, as idris2i_1_threadBlockOn.
// Returns 1 if the thread was woken up, and 0 if the deadline expired.  On
// expiry the thread is removed from `queue`, so it cannot be woken up by a
// later event.
int idris2i_1_threadBlockOnUntil(Idris2i_1_WaitQueue *queue, Idris2i_1_SpinLock *lock,
                              int64_t deadline_ns);

// Remove the first thread waiting in `queue` without scheduling it.  Returns
// NULL if the queue is empty.  The caller holds the lock of the queue.  The
// queue must not have threads waiting with a deadline.
Idris2i_1_Thread *idris2i_1_threadTakeWaiter(Idris2i_1_WaitQueue *queue);

// Make a thread taken with idris2i_1_threadTakeWaiter runnable again.
void idris2i_1_threadSchedule(Idris2i_1_Thread *thread);

// Wake up the first thread waiting in `queue`, if any (one whose deadline
// has not expired).  The caller holds the lock of the queue.  Returns 1 when
// a thread was woken up.
int idris2i_1_threadWakeOne(Idris2i_1_WaitQueue *queue);

// Wake up all the threads waiting in `queue`.  The caller holds the lock of
// the queue.
void idris2i_1_threadWakeAll(Idris2i_1_WaitQueue *queue);

// Called before a thread may block for the first time on a new kind of thing:
// by the functions that make the objects that threads block on (mutexes,
// channels, ...), by those that block without one (sleep), and by the
// reactor when it is made (see reactor.c).  It sets up the loop of the scheduler, which a program that
// never blocks nor forks then does not link (see scheduler_start in
// threads.c); idris2i_1_threadBlockOn and the like do not test it.
void idris2i_1_threadsMayBlock(void);

// Let the other runnable threads run before the current one carries on.
void idris2i_1_threadYield(void);

// Sleep for the given number of microseconds.  Unlike a system call, this
// does not block the other green threads.
void idris2i_1_threadSleep(int64_t microseconds);

// The same, for the sleeps of the FFI (see concurrency.c): a pointer that a
// program which never sleeps does not link, and that sets the scheduler up
// on its first call only (see idris2i_1_threadsMayBlock), so that a sleep
// costs no test.
extern void (*idris2i_1_threadSleepHook)(int64_t microseconds);

// The index of the current worker.
int idris2i_1_workerIndex(void);

// Stop the other workers for good, for the reports at exit (see
// idris2i_1_reportAtExit): each one stops at the next safepoint of the thread
// that it runs, or before it runs one.  Returns the number of workers that
// did not stop within a second (they make a system call, say) and may still
// run.
int idris2i_1_threadStopOthers(void);

// Is the thread `thread` running on the worker `worker`, another one than
// the current one, which has nothing else to do?  (Then a lock that the
// thread holds is worth spinning on for a while, as it runs at the same
// time.)
int idris2i_1_threadRunsElsewhere(int worker, int64_t thread);

// For the reactor (see reactor.c): threads start to wait for file
// descriptors, so a parked worker must poll.
void idris2i_1_threadKickWatcher(void);
