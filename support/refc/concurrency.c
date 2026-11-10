// ---------------------------------------------------------------------------
// Synchronisation primitives for the RefC backend.
//
// The RefC backend runs green threads (see threads.c), so the synchronisation
// objects are implemented in terms of green threads rather than in terms of
// OS threads: a thread waiting for a mutex, a condition variable, a
// semaphore, a barrier or a channel gives up control to the scheduler until
// it is woken up.
//
// Green threads only switch when they block, so the state of the objects is
// updated without any further synchronisation.
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
// Mutexes are recursive, like the ones of the Scheme backends.  When a mutex
// is released, it is handed over to the first waiting thread, so waiting
// threads cannot starve.
// ---------------------------------------------------------------------------

void *refc_makeMutex(void) {
  Idris2_Mutex *mutex =
      (Idris2_Mutex *)idris2_newZeroedValue(sizeof(Idris2_Mutex));
  mutex->header.tag = MUTEX_TAG;
  return mutex;
}

void refc_mutexAcquire(Idris2_Value *mutex) {
  Idris2_Mutex *m = (Idris2_Mutex *)mutex;
  int64_t self = self_id();
  if (m->depth == 0) {
    m->owner = self;
    m->depth = 1;
  } else if (m->owner == self) {
    m->depth++;
  } else {
    // refc_mutexRelease hands the mutex over to us before waking us up.
    idris2_threadBlockOn(&m->waiters);
  }
}

void refc_mutexRelease(Idris2_Value *mutex) {
  Idris2_Mutex *m = (Idris2_Mutex *)mutex;
  if (m->depth == 0 || m->owner != self_id()) {
    fatal("mutexRelease: the mutex is not held by the current thread");
  }
  if (--m->depth > 0) {
    return;
  }
  Idris2_Thread *waiter = idris2_threadTakeWaiter(&m->waiters);
  if (waiter) {
    m->owner = idris2_threadId(waiter);
    m->depth = 1;
    idris2_threadSchedule(waiter);
  }
}

// Release a mutex completely, however many times it has been acquired, and
// return the recursion depth so that it can be restored.
static int64_t mutex_release_all(Idris2_Mutex *m) {
  if (m->depth == 0 || m->owner != self_id()) {
    fatal("conditionWait: the mutex is not held by the current thread");
  }
  int64_t depth = m->depth;
  m->depth = 1;
  refc_mutexRelease((Idris2_Value *)m);
  return depth;
}

static void mutex_reacquire(Idris2_Mutex *m, int64_t depth) {
  refc_mutexAcquire((Idris2_Value *)m);
  m->depth = depth;
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
  int64_t depth = mutex_release_all(m);
  idris2_threadBlockOn(&c->waiters);
  mutex_reacquire(m, depth);
}

void refc_conditionWaitTimeout(Idris2_Value *condition, Idris2_Value *mutex,
                               int64_t timeout_us) {
  Idris2_Condition *c = (Idris2_Condition *)condition;
  Idris2_Mutex *m = (Idris2_Mutex *)mutex;
  int64_t deadline = idris2_deadlineAfter(timeout_us);
  int64_t depth = mutex_release_all(m);
  // On expiry the thread leaves the queue, so a later signal is not lost.
  (void)idris2_threadBlockOnUntil(&c->waiters, deadline);
  mutex_reacquire(m, depth);
}

void refc_conditionSignal(Idris2_Value *condition) {
  idris2_threadWakeOne(&((Idris2_Condition *)condition)->waiters);
}

void refc_conditionBroadcast(Idris2_Value *condition) {
  idris2_threadWakeAll(&((Idris2_Condition *)condition)->waiters);
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
  // Hand the permit over to a waiting thread, if there is one.
  Idris2_Thread *waiter = idris2_threadTakeWaiter(&s->waiters);
  if (waiter) {
    idris2_threadSchedule(waiter);
  } else {
    s->count++;
  }
}

void refc_semaphoreWait(Idris2_Value *semaphore) {
  Idris2_Semaphore *s = (Idris2_Semaphore *)semaphore;
  if (s->count > 0) {
    s->count--;
  } else {
    // refc_semaphorePost hands a permit over to us before waking us up.
    idris2_threadBlockOn(&s->waiters);
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
  if (++b->count >= b->num_threads) {
    // The last thread to arrive releases the others, and the barrier can be
    // used again.
    b->count = 0;
    idris2_threadWakeAll(&b->waiters);
  } else {
    idris2_threadBlockOn(&b->waiters);
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
  while (c->full) {
    idris2_threadBlockOn(&c->writers);
  }
  c->value = idris2_newReference(value);
  c->full = 1;
  idris2_threadWakeOne(&c->readers);
}

// Take the value out of a full channel.  The reference is handed over to the
// caller.
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
  // Another reader may get the value first, hence the loop.
  while (!c->full) {
    idris2_threadBlockOn(&c->readers);
  }
  return channel_take(c);
}

void *refc_channelGetNonBlocking(Idris2_Value *erased, Idris2_Value *channel) {
  (void)erased;
  Idris2_Channel *c = (Idris2_Channel *)channel;
  return c->full ? make_just(channel_take(c)) : NULL;
}

void *refc_channelGetWithTimeout(Idris2_Value *erased, Idris2_Value *channel,
                                 int64_t timeout_ms) {
  (void)erased;
  Idris2_Channel *c = (Idris2_Channel *)channel;
  int64_t deadline = idris2_deadlineAfter(
      timeout_ms > INT64_MAX / 1000 ? INT64_MAX : timeout_ms * 1000);
  while (!c->full) {
    if (!idris2_threadBlockOnUntil(&c->readers, deadline)) {
      break; // timed out
    }
  }
  return c->full ? make_just(channel_take(c)) : NULL;
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
