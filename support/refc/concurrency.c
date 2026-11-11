// ---------------------------------------------------------------------------
// Synchronisation primitives for the RefC backend.
//
// The RefC backend runs green threads (see threads.c), so the synchronisation
// objects are implemented in terms of green threads rather than in terms of
// OS threads: a thread waiting for a mutex, a condition variable, a
// semaphore, a barrier or a channel gives up control to the scheduler until
// it is woken up.
//
// The green threads run on several workers, so the state of every object is
// guarded by its spin lock.  A thread that blocks gives the lock back once it
// is switched out (see idris2_threadBlockOn).  Lock order: a condition
// variable, then a mutex; then the locks of threads.c.
// ---------------------------------------------------------------------------

#include "concurrency.h"
#include "memoryManagement.h"
#include "threads.h"

#include <stdio.h>
#include <stdlib.h>

static void fatal(const char *message) {
  fprintf(stderr, "RefC: %s\n", message);
  exit(1);
}

static int64_t self_id(void) { return idris2_threadId(idris2_currentThread()); }

// ---------------------------------------------------------------------------
// Mutexes
//
// Mutexes are recursive, like the ones of the Scheme backends.  They are
// taken and released with one atomic operation when nobody waits for them
// (`state`, see Idris2_Mutex); the spin lock is only taken to wait for the
// mutex, or to wake up a waiting thread.  A released mutex is free: the first
// waiting thread is woken up to try again, and a running thread may get the
// mutex first (handing it over would cost a context switch per acquisition
// while threads contend for it).  A thread that waited for more than
// STARVING_NS nanoseconds marks the mutex as starving: the next release hands
// the mutex over to the first waiting thread, so waiting threads cannot
// starve.  A thread spins for a while before it waits when the owner runs on
// another worker, as it may release the mutex very soon.
// ---------------------------------------------------------------------------

#define MUTEX_FREE 0
#define MUTEX_HELD 1
#define MUTEX_CONTENDED 2 // held, and threads may wait for it

#define MUTEX_SPIN_ROUNDS 4
#define MUTEX_SPIN_PAUSES 30
#define STARVING_NS ((int64_t)1000000)

void *refc_makeMutex(void) {
  Idris2_Mutex *mutex =
      (Idris2_Mutex *)idris2_newZeroedValue(sizeof(Idris2_Mutex));
  mutex->header.tag = MUTEX_TAG;
  mutex->owner = -1;
  return mutex;
}

// Take the mutex if it is free.  A thread that was woken up takes it as
// contended: others may still wait, and its release must wake one of them
// up (a release of a mutex held as 1 does not look).
static int mutex_try(Idris2_Mutex *m, int woken) {
  int free = MUTEX_FREE;
  return __atomic_compare_exchange_n(&m->state, &free,
                                     woken ? MUTEX_CONTENDED : MUTEX_HELD, 0,
                                     __ATOMIC_ACQUIRE, __ATOMIC_RELAXED);
}

// We got the mutex.
static void mutex_own(Idris2_Mutex *m, int64_t self) {
  __atomic_store_n(&m->owner, self, __ATOMIC_RELAXED);
  __atomic_store_n(&m->owner_worker, idris2_workerIndex(), __ATOMIC_RELAXED);
  m->depth = 1;
}

void refc_mutexAcquire(Idris2_Value *mutex) {
  Idris2_Mutex *m = (Idris2_Mutex *)mutex;
  int64_t self = self_id();
  if (mutex_try(m, 0)) {
    mutex_own(m, self);
    return;
  }
  // (only this thread may have written its own identifier there)
  if (__atomic_load_n(&m->owner, __ATOMIC_RELAXED) == self) {
    m->depth++;
    return;
  }
  int spins = 0;
  int woken = 0;
  int64_t since = 0;
  for (;;) {
    while (spins < MUTEX_SPIN_ROUNDS &&
           idris2_threadRunsElsewhere(
               __atomic_load_n(&m->owner_worker, __ATOMIC_RELAXED),
               __atomic_load_n(&m->owner, __ATOMIC_RELAXED))) {
      spins++;
      for (int i = 0; i < MUTEX_SPIN_PAUSES &&
                      __atomic_load_n(&m->state, __ATOMIC_RELAXED) != MUTEX_FREE;
           i++) {
        idris2_cpuRelax();
      }
      if (__atomic_load_n(&m->state, __ATOMIC_RELAXED) == MUTEX_FREE &&
          mutex_try(m, woken)) {
        mutex_own(m, self);
        return;
      }
    }
    idris2_spinLock(&m->lock);
    // From now on the release has to look for waiting threads.
    if (__atomic_exchange_n(&m->state, MUTEX_CONTENDED, __ATOMIC_ACQUIRE) ==
        MUTEX_FREE) {
      idris2_spinUnlock(&m->lock);
      mutex_own(m, self);
      return;
    }
    int64_t now = idris2_monotonicNanoseconds();
    if (!since) {
      since = now;
    } else if (now - since > STARVING_NS) {
      __atomic_store_n(&m->starving, 1, __ATOMIC_RELAXED);
    }
    idris2_threadBlockOn(&m->waiters, &m->lock);
    if (__atomic_load_n(&m->owner, __ATOMIC_ACQUIRE) == self) {
      // refc_mutexRelease handed the mutex over to us (with a depth of 1).
      __atomic_store_n(&m->owner_worker, idris2_workerIndex(),
                       __ATOMIC_RELAXED);
      return;
    }
    woken = 1;
    spins = 0;
  }
}

void refc_mutexRelease(Idris2_Value *mutex) {
  Idris2_Mutex *m = (Idris2_Mutex *)mutex;
  int64_t self = self_id();
  if (__atomic_load_n(&m->state, __ATOMIC_RELAXED) == MUTEX_FREE ||
      __atomic_load_n(&m->owner, __ATOMIC_RELAXED) != self) {
    fatal("mutexRelease: the mutex is not held by the current thread");
  }
  if (m->depth > 1) {
    m->depth--;
    return;
  }
  if (__atomic_load_n(&m->starving, __ATOMIC_RELAXED)) {
    idris2_spinLock(&m->lock);
    Idris2_Thread *waiter = idris2_threadTakeWaiter(&m->waiters);
    if (waiter) {
      // The mutex stays held, by the waiting thread now.
      m->depth = 1;
      __atomic_store_n(&m->owner_worker, -1, __ATOMIC_RELAXED);
      __atomic_store_n(&m->owner, idris2_threadId(waiter), __ATOMIC_RELEASE);
      if (!m->waiters.head) {
        __atomic_store_n(&m->starving, 0, __ATOMIC_RELAXED);
      }
      idris2_threadSchedule(waiter);
      idris2_spinUnlock(&m->lock);
      return;
    }
    __atomic_store_n(&m->starving, 0, __ATOMIC_RELAXED);
    idris2_spinUnlock(&m->lock);
  }
  m->depth = 0;
  __atomic_store_n(&m->owner, -1, __ATOMIC_RELAXED);
  if (__atomic_exchange_n(&m->state, MUTEX_FREE, __ATOMIC_RELEASE) ==
      MUTEX_CONTENDED) {
    idris2_spinLock(&m->lock);
    idris2_threadWakeOne(&m->waiters);
    idris2_spinUnlock(&m->lock);
  }
}

// Release a mutex completely, however many times it has been acquired, and
// return the recursion depth so that it can be restored.
static int64_t mutex_release_all(Idris2_Mutex *m) {
  if (__atomic_load_n(&m->state, __ATOMIC_RELAXED) == MUTEX_FREE ||
      __atomic_load_n(&m->owner, __ATOMIC_RELAXED) != self_id()) {
    fatal("conditionWait: the mutex is not held by the current thread");
  }
  int64_t depth = m->depth;
  m->depth = 1;
  refc_mutexRelease((Idris2_Value *)m);
  return depth;
}

static void mutex_reacquire(Idris2_Mutex *m, int64_t depth) {
  refc_mutexAcquire((Idris2_Value *)m);
  m->depth = depth; // (only the owner touches the depth)
}

// ---------------------------------------------------------------------------
// Condition variables
// ---------------------------------------------------------------------------

void *refc_makeCondition(void) {
  Idris2_Condition *condition =
      (Idris2_Condition *)idris2_newZeroedValue(sizeof(Idris2_Condition));
  condition->header.tag = CONDITION_TAG;
  return condition;
}

void refc_conditionWait(Idris2_Value *condition, Idris2_Value *mutex) {
  Idris2_Condition *c = (Idris2_Condition *)condition;
  Idris2_Mutex *m = (Idris2_Mutex *)mutex;
  // The thread waits for the condition before the mutex is released, so
  // that a signal sent once the mutex is free is not lost.
  idris2_spinLock(&c->lock);
  int64_t depth = mutex_release_all(m);
  idris2_threadBlockOn(&c->waiters, &c->lock);
  mutex_reacquire(m, depth);
}

void refc_conditionWaitTimeout(Idris2_Value *condition, Idris2_Value *mutex,
                               int64_t timeout_us) {
  Idris2_Condition *c = (Idris2_Condition *)condition;
  Idris2_Mutex *m = (Idris2_Mutex *)mutex;
  int64_t deadline = idris2_deadlineAfter(timeout_us);
  idris2_spinLock(&c->lock);
  int64_t depth = mutex_release_all(m);
  // On expiry the thread leaves the queue, so a later signal is not lost.
  (void)idris2_threadBlockOnUntil(&c->waiters, &c->lock, deadline);
  mutex_reacquire(m, depth);
}

void refc_conditionSignal(Idris2_Value *condition) {
  Idris2_Condition *c = (Idris2_Condition *)condition;
  idris2_spinLock(&c->lock);
  idris2_threadWakeOne(&c->waiters);
  idris2_spinUnlock(&c->lock);
}

void refc_conditionBroadcast(Idris2_Value *condition) {
  Idris2_Condition *c = (Idris2_Condition *)condition;
  idris2_spinLock(&c->lock);
  idris2_threadWakeAll(&c->waiters);
  idris2_spinUnlock(&c->lock);
}

// ---------------------------------------------------------------------------
// Semaphores
// ---------------------------------------------------------------------------

void *refc_makeSemaphore(int64_t count) {
  Idris2_Semaphore *semaphore =
      (Idris2_Semaphore *)idris2_newZeroedValue(sizeof(Idris2_Semaphore));
  semaphore->header.tag = SEMAPHORE_TAG;
  semaphore->count = count;
  return semaphore;
}

void refc_semaphorePost(Idris2_Value *semaphore) {
  Idris2_Semaphore *s = (Idris2_Semaphore *)semaphore;
  idris2_spinLock(&s->lock);
  // Hand the permit over to a waiting thread, if there is one.
  Idris2_Thread *waiter = idris2_threadTakeWaiter(&s->waiters);
  if (waiter) {
    idris2_threadSchedule(waiter);
  } else {
    s->count++;
  }
  idris2_spinUnlock(&s->lock);
}

void refc_semaphoreWait(Idris2_Value *semaphore) {
  Idris2_Semaphore *s = (Idris2_Semaphore *)semaphore;
  idris2_spinLock(&s->lock);
  if (s->count > 0) {
    s->count--;
    idris2_spinUnlock(&s->lock);
  } else {
    // refc_semaphorePost hands a permit over to us before waking us up.
    idris2_threadBlockOn(&s->waiters, &s->lock);
  }
}

// ---------------------------------------------------------------------------
// Barriers
// ---------------------------------------------------------------------------

void *refc_makeBarrier(int64_t num_threads) {
  Idris2_Barrier *barrier =
      (Idris2_Barrier *)idris2_newZeroedValue(sizeof(Idris2_Barrier));
  barrier->header.tag = BARRIER_TAG;
  barrier->num_threads = num_threads;
  return barrier;
}

void refc_barrierWait(Idris2_Value *barrier) {
  Idris2_Barrier *b = (Idris2_Barrier *)barrier;
  idris2_spinLock(&b->lock);
  if (++b->count >= b->num_threads) {
    // The last thread to arrive releases the others, and the barrier can be
    // used again.
    b->count = 0;
    idris2_threadWakeAll(&b->waiters);
    idris2_spinUnlock(&b->lock);
  } else {
    idris2_threadBlockOn(&b->waiters, &b->lock);
  }
}

// ---------------------------------------------------------------------------
// Channels
//
// Like the channels of the Chez backend, a channel holds at most one value:
// `channelPut` waits until the channel is empty, then stores the value and
// returns without waiting for a receiver.
// ---------------------------------------------------------------------------

void *refc_makeChannel(Idris2_Value *erased) {
  (void)erased;
  Idris2_Channel *channel =
      (Idris2_Channel *)idris2_newZeroedValue(sizeof(Idris2_Channel));
  channel->header.tag = CHANNEL_TAG;
  return channel;
}

void refc_channelPut(Idris2_Value *erased, Idris2_Value *channel,
                     Idris2_Value *value) {
  (void)erased;
  Idris2_Channel *c = (Idris2_Channel *)channel;
  if (idris2_isShared(channel)) {
    // The receiver may run in parallel with us.
    idris2_markShared(value);
  }
  idris2_newReference(value);
  idris2_spinLock(&c->lock);
  while (c->full) {
    idris2_threadBlockOn(&c->writers, &c->lock);
    idris2_spinLock(&c->lock);
  }
  c->value = value;
  c->full = 1;
  idris2_threadWakeOne(&c->readers);
  idris2_spinUnlock(&c->lock);
}

// Take the value out of a full channel, whose lock is held.  The reference
// is handed over to the caller.
static Idris2_Value *channel_take(Idris2_Channel *c) {
  Idris2_Value *value = c->value;
  c->value = NULL;
  c->full = 0;
  idris2_threadWakeOne(&c->writers);
  return value;
}

// Build a `Just` value.  `Nothing` is represented by NULL.
static Idris2_Value *make_just(Idris2_Value *value) {
  Idris2_Constructor *just = idris2_newConstructor(1, 1);
  just->args[0] = value;
  return (Idris2_Value *)just;
}

void *refc_channelGet(Idris2_Value *erased, Idris2_Value *channel) {
  (void)erased;
  Idris2_Channel *c = (Idris2_Channel *)channel;
  idris2_spinLock(&c->lock);
  // Another reader may get the value first, hence the loop.
  while (!c->full) {
    idris2_threadBlockOn(&c->readers, &c->lock);
    idris2_spinLock(&c->lock);
  }
  Idris2_Value *value = channel_take(c);
  idris2_spinUnlock(&c->lock);
  return value;
}

void *refc_channelGetNonBlocking(Idris2_Value *erased, Idris2_Value *channel) {
  (void)erased;
  Idris2_Channel *c = (Idris2_Channel *)channel;
  idris2_spinLock(&c->lock);
  int full = c->full;
  Idris2_Value *value = full ? channel_take(c) : NULL;
  idris2_spinUnlock(&c->lock);
  return full ? make_just(value) : NULL;
}

void *refc_channelGetWithTimeout(Idris2_Value *erased, Idris2_Value *channel,
                                 int64_t timeout_ms) {
  (void)erased;
  Idris2_Channel *c = (Idris2_Channel *)channel;
  int64_t deadline = idris2_deadlineAfter(
      timeout_ms > INT64_MAX / 1000 ? INT64_MAX : timeout_ms * 1000);
  idris2_spinLock(&c->lock);
  while (!c->full) {
    int woken = idris2_threadBlockOnUntil(&c->readers, &c->lock, deadline);
    idris2_spinLock(&c->lock);
    if (!woken) {
      break; // timed out
    }
  }
  int full = c->full;
  Idris2_Value *value = full ? channel_take(c) : NULL;
  idris2_spinUnlock(&c->lock);
  return full ? make_just(value) : NULL;
}

// ---------------------------------------------------------------------------
// Sleeping
// ---------------------------------------------------------------------------

void refc_sleep(int64_t seconds) {
  if (seconds > 0) {
    idris2_threadSleep(seconds > INT64_MAX / 1000000 ? INT64_MAX
                                                     : seconds * 1000000);
  }
}

void refc_usleep(int64_t microseconds) { idris2_threadSleep(microseconds); }
