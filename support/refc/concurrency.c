// ---------------------------------------------------------------------------
// Synchronisation primitives for the RefC backend.
//
// The RefC backend runs green threads (see threads.c), so the synchronisation
// objects are implemented in terms of green threads rather than in terms of
// OS threads: a thread waiting for a mutex, a condition variable, a
// semaphore, a barrier or a channel gives up control to the scheduler until
// it is woken up.
// ---------------------------------------------------------------------------

#include "concurrency.h"
#include "memoryManagement.h"
#include "refc_util.h"
#include "runtime.h"
#include "threads.h"

#include <stdlib.h>

// A message travelling through a channel is boxed, so that values which are
// represented by NULL at runtime (such as the unit type) can be told apart
// from "no value".

static Idris2_Value *channel_box_new(Idris2_Value *value) {
  Idris2_ChannelBox *box =
      (Idris2_ChannelBox *)idris2_newZeroedValue(sizeof(Idris2_ChannelBox));
  box->header.tag = CHANNEL_BOX_TAG;
  box->value = idris2_newReference(value);
  return (Idris2_Value *)box;
}

// Take the value out of a box.  The reference on the value is transferred to
// the caller.
static Idris2_Value *channel_box_take(Idris2_Value *boxed) {
  Idris2_ChannelBox *box = (Idris2_ChannelBox *)boxed;
  Idris2_Value *value = box->value;
  box->value = NULL;
  idris2_removeReference(boxed);
  return value;
}

// Build a `Just` value.  `Nothing` is represented by NULL.
static Idris2_Value *make_just(Idris2_Value *value) {
  Idris2_Constructor *constructor = idris2_newConstructor(1, 0);
  constructor->args[0] = value;
  return (Idris2_Value *)constructor;
}

// ---------------------------------------------------------------------------
// Mutexes
// ---------------------------------------------------------------------------

void *refc_makeMutex(void) {
  Idris2_Mutex *mutex =
      (Idris2_Mutex *)idris2_newZeroedValue(sizeof(Idris2_Mutex));
  mutex->header.tag = MUTEX_TAG;
  mutex->locked = 0;
  mutex->depth = 0;
  mutex->owner = NULL;
  return mutex;
}

void refc_mutexAcquire(Idris2_Value *mutex) {
  Idris2_Mutex *m = (Idris2_Mutex *)mutex;
  Idris2_Thread *self = idris2_currentThread();
  if (!m->locked) {
    m->locked = 1;
    m->owner = self;
    m->depth = 1;
    return;
  }
  // Mutexes are recursive: the owner may acquire them again.
  if (m->owner == self) {
    m->depth++;
    return;
  }
  // The mutex is owned by somebody else: wait until it is handed over to us.
  idris2_threadBlockOn(&m->waiters);
}

void refc_mutexRelease(Idris2_Value *mutex) {
  Idris2_Mutex *m = (Idris2_Mutex *)mutex;
  Idris2_Thread *self = idris2_currentThread();
  if (m->owner == self && m->depth > 1) {
    m->depth--;
    return;
  }
  m->depth = 0;
  m->locked = 0;
  m->owner = NULL;
  // Hand the mutex over to the first thread waiting for it, if any.
  Idris2_Thread *waiter = idris2_threadTakeWaiter(&m->waiters);
  if (waiter) {
    m->locked = 1;
    m->owner = waiter;
    m->depth = 1;
    idris2_threadSchedule(waiter);
  }
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
  refc_mutexRelease(mutex);
  idris2_threadBlockOn(&c->waiters);
  refc_mutexAcquire(mutex);
}

void refc_conditionWaitTimeout(Idris2_Value *condition, Idris2_Value *mutex,
                               int64_t timeout_us) {
  Idris2_Condition *c = (Idris2_Condition *)condition;
  Idris2_Thread *self = idris2_currentThread();
  refc_mutexRelease(mutex);
  idris2_threadBlockOnTimeout(&c->waiters, timeout_us);
  // The wait may have timed out, in which case we are not waiting for the
  // condition any more.
  if (self) {
    idris2_threadRemoveWaiter(&c->waiters, self);
  }
  refc_mutexAcquire(mutex);
}

void refc_conditionSignal(Idris2_Value *condition) {
  Idris2_Condition *c = (Idris2_Condition *)condition;
  idris2_threadWakeOne(&c->waiters);
}

void refc_conditionBroadcast(Idris2_Value *condition) {
  Idris2_Condition *c = (Idris2_Condition *)condition;
  idris2_threadWakeAll(&c->waiters);
}

// ---------------------------------------------------------------------------
// Semaphores
// ---------------------------------------------------------------------------

void *refc_makeSemaphore(int64_t count) {
  Idris2_Semaphore *semaphore =
      (Idris2_Semaphore *)idris2_newZeroedValue(sizeof(Idris2_Semaphore));
  semaphore->header.tag = SEMAPHORE_TAG;
  semaphore->count = (int)count;
  return semaphore;
}

void refc_semaphorePost(Idris2_Value *semaphore) {
  Idris2_Semaphore *s = (Idris2_Semaphore *)semaphore;
  // Hand the permit over to a waiting thread, if there is one.
  Idris2_Thread *waiter = idris2_threadTakeWaiter(&s->waiters);
  if (waiter) {
    idris2_threadSchedule(waiter);
    return;
  }
  s->count++;
}

void refc_semaphoreWait(Idris2_Value *semaphore) {
  Idris2_Semaphore *s = (Idris2_Semaphore *)semaphore;
  if (s->count > 0) {
    s->count--;
    return;
  }
  // A permit is handed over to us when we are woken up.
  idris2_threadBlockOn(&s->waiters);
}

// ---------------------------------------------------------------------------
// Barriers
// ---------------------------------------------------------------------------

void *refc_makeBarrier(int64_t num_threads) {
  Idris2_Barrier *barrier =
      (Idris2_Barrier *)idris2_newZeroedValue(sizeof(Idris2_Barrier));
  barrier->header.tag = BARRIER_TAG;
  barrier->count = 0;
  barrier->num_threads = (int)num_threads;
  return barrier;
}

void refc_barrierWait(Idris2_Value *barrier) {
  Idris2_Barrier *b = (Idris2_Barrier *)barrier;
  // Green threads only switch at explicit yield points, so the count is
  // safely updated without any further synchronisation.
  b->count++;
  if (b->count >= b->num_threads) {
    b->count = 0;
    idris2_threadWakeAll(&b->waiters);
    return;
  }
  idris2_threadBlockOn(&b->waiters);
}

// ---------------------------------------------------------------------------
// Channels
//
// Channels are rendezvous channels: a value is handed over directly from the
// sender to the receiver, and both sides wait for the other one.
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
  Idris2_Thread *self = idris2_currentThread();
  Idris2_Value *boxed = channel_box_new(value);
  self->handoff_value = boxed;
  for (;;) {
    // Is somebody waiting for a value?
    Idris2_Thread *reader = idris2_threadTakeWaiter(&c->readers);
    if (reader) {
      reader->handoff_value = self->handoff_value;
      self->handoff_value = NULL;
      idris2_threadSchedule(reader);
      return;
    }
    // No reader yet: wait for one to show up.
    idris2_threadBlockOn(&c->writers);
    // When we are woken up, the value has been taken.
    if (!self->handoff_value) {
      return;
    }
  }
}

void *refc_channelGet(Idris2_Value *erased, Idris2_Value *channel) {
  (void)erased;
  Idris2_Channel *c = (Idris2_Channel *)channel;
  Idris2_Thread *self = idris2_currentThread();
  for (;;) {
    // Is somebody waiting to send a value?
    Idris2_Thread *writer = idris2_threadTakeWaiter(&c->writers);
    if (writer) {
      Idris2_Value *boxed = writer->handoff_value;
      writer->handoff_value = NULL;
      idris2_threadSchedule(writer);
      return channel_box_take(boxed);
    }
    // No sender yet: wait for one to show up.
    self->handoff_value = NULL;
    idris2_threadBlockOn(&c->readers);
    if (self->handoff_value) {
      Idris2_Value *boxed = self->handoff_value;
      self->handoff_value = NULL;
      return channel_box_take(boxed);
    }
  }
}

void *refc_channelGetNonBlocking(Idris2_Value *erased, Idris2_Value *channel) {
  (void)erased;
  Idris2_Channel *c = (Idris2_Channel *)channel;
  Idris2_Thread *writer = idris2_threadTakeWaiter(&c->writers);
  if (!writer) {
    return NULL;
  }
  Idris2_Value *boxed = writer->handoff_value;
  writer->handoff_value = NULL;
  idris2_threadSchedule(writer);
  return make_just(channel_box_take(boxed));
}

void *refc_channelGetWithTimeout(Idris2_Value *erased, Idris2_Value *channel,
                                 int64_t timeout_ms) {
  (void)erased;
  Idris2_Channel *c = (Idris2_Channel *)channel;
  Idris2_Thread *self = idris2_currentThread();
  long timeout_us = (long)timeout_ms * 1000;
  for (;;) {
    Idris2_Thread *writer = idris2_threadTakeWaiter(&c->writers);
    if (writer) {
      Idris2_Value *boxed = writer->handoff_value;
      writer->handoff_value = NULL;
      idris2_threadSchedule(writer);
      return make_just(channel_box_take(boxed));
    }
    self->handoff_value = NULL;
    idris2_threadBlockOnTimeout(&c->readers, timeout_us);
    if (self->handoff_value) {
      Idris2_Value *boxed = self->handoff_value;
      self->handoff_value = NULL;
      return make_just(channel_box_take(boxed));
    }
    // The timeout expired: we are not waiting for a value any more.
    idris2_threadRemoveWaiter(&c->readers, self);
    return NULL;
  }
}

// ---------------------------------------------------------------------------
// Thread local data
// ---------------------------------------------------------------------------

int64_t refc_getThreadId(void) {
  Idris2_Thread *self = idris2_currentThread();
  return self ? (int64_t)self->id : 0;
}

void refc_setThreadData(Idris2_Value *erased, Idris2_Value *value) {
  (void)erased;
  Idris2_Thread *self = idris2_currentThread();
  if (!self) {
    return;
  }
  if (self->thread_data) {
    idris2_removeReference(self->thread_data);
  }
  self->thread_data = idris2_newReference(value);
}

void *refc_getThreadData(Idris2_Value *erased) {
  (void)erased;
  Idris2_Thread *self = idris2_currentThread();
  if (!self || !self->thread_data) {
    return NULL;
  }
  // The reference is handed over to the caller.
  Idris2_Value *value = self->thread_data;
  self->thread_data = NULL;
  return value;
}

// ---------------------------------------------------------------------------
// Sleeping
// ---------------------------------------------------------------------------

void refc_sleep(int64_t seconds) {
  if (seconds <= 0) {
    return;
  }
  idris2_threadSleep((long)seconds * 1000000);
}

void refc_usleep(int64_t microseconds) {
  if (microseconds <= 0) {
    return;
  }
  idris2_threadSleep((long)microseconds);
}
