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
#include "prim.h"
#include "runtime.h"
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
// A channel is a queue of at most `capacity` values (see Idris2_Channel).
// `channelPut` waits while the channel is full, then adds the value and
// returns without waiting for a receiver; `channelGet` waits while it is
// empty.  The channel of `makeChannel` holds at most one value, like the
// channels of the Chez backend.  Every value added wakes up a waiting
// reader, and every value taken a waiting writer; a woken thread looks
// again, as another one may have come first.  The thread to wake up is
// taken out of its queue under the lock, but made runnable once the lock is
// released, which keeps the lock short when threads on several workers use
// the channel at the same time (this is not possible for a reader that waits
// with a deadline, which the queue of threads.c has to wake up itself).
// ---------------------------------------------------------------------------

// The slots that a buffered channel starts with (it grows as needed).
#define CHANNEL_FIRST_SLOTS 16

static Idris2_Channel *channel_new(int64_t capacity) {
  Idris2_Channel *c =
      (Idris2_Channel *)idris2_newZeroedValue(sizeof(Idris2_Channel));
  c->header.tag = CHANNEL_TAG;
  c->capacity = capacity < 1 ? 1 : capacity;
  c->size = 1;
  c->slots = &c->value;
  return c;
}

void *refc_makeChannel(Idris2_Value *erased) {
  (void)erased;
  return channel_new(1);
}

void *refc_makeBufferedChannel(Idris2_Value *erased, int64_t capacity) {
  (void)erased;
  return channel_new(capacity);
}

void *refc_makeUnboundedChannel(Idris2_Value *erased) {
  (void)erased;
  return channel_new(INT64_MAX);
}

// Make room for one more value in a full ring of a channel that can hold
// more, whose lock is held.
static void channel_grow(Idris2_Channel *c) {
  int64_t size = c->size < CHANNEL_FIRST_SLOTS     ? CHANNEL_FIRST_SLOTS
                 : c->size > INT64_MAX / 2          ? INT64_MAX
                                                    : 2 * c->size;
  if (size > c->capacity)
    size = c->capacity;
  if ((uint64_t)size > SIZE_MAX / sizeof(Idris2_Value *))
    fatal("channelPut: out of memory");
  Idris2_Value **slots =
      (Idris2_Value **)malloc((size_t)size * sizeof(Idris2_Value *));
  if (!slots)
    fatal("channelPut: out of memory");
  for (int64_t i = 0; i < c->count; i++)
    slots[i] = c->slots[(c->head + i) % c->size];
  if (c->slots != &c->value)
    free(c->slots);
  c->slots = slots;
  c->size = size;
  c->head = 0;
}

// Take the lock of a channel.  Threads on several workers that use a channel
// at the same time contend for its lock, which is held for a few
// instructions at a time: a thread that finds it held backs off for longer
// and longer before it looks again, so that fewer threads fight for the
// cache line of the lock each time it is released.
#define CHANNEL_BACKOFF_MAX 256

static void channel_lock_slow(Idris2_Channel *c) {
#if IDRIS2_MULTICORE
  for (unsigned pauses = 1; pauses <= CHANNEL_BACKOFF_MAX; pauses *= 2) {
    for (unsigned i = 0; i < pauses; i++)
      idris2_cpuRelax();
    if (!__atomic_load_n(&c->lock, __ATOMIC_RELAXED) &&
        !__atomic_exchange_n(&c->lock, 1, __ATOMIC_ACQUIRE))
      return;
  }
#endif
  idris2_spinLock(&c->lock);
}

static inline void channel_lock(Idris2_Channel *c) {
#if IDRIS2_MULTICORE
  if (__builtin_expect(__atomic_exchange_n(&c->lock, 1, __ATOMIC_ACQUIRE), 0))
    channel_lock_slow(c);
#endif
}

// Take the first thread out of a wait queue of a channel, whose lock is
// held, for idris2_threadSchedule once the lock is released.  If the queue
// may have threads that wait with a deadline, wake it up now instead.
static Idris2_Thread *channel_wake(Idris2_WaitQueue *queue, int timed) {
  if (!queue->head)
    return NULL;
  if (timed) {
    idris2_threadWakeOne(queue);
    return NULL;
  }
  return idris2_threadTakeWaiter(queue);
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
  channel_lock(c);
  while (c->count >= c->capacity) {
    idris2_threadBlockOn(&c->writers, &c->lock);
    channel_lock(c);
  }
  if (c->count == c->size)
    channel_grow(c);
  int64_t tail = c->head + c->count;
  c->slots[tail >= c->size ? tail - c->size : tail] = value;
  c->count++;
  Idris2_Thread *reader = channel_wake(&c->readers, c->timed_readers > 0);
  idris2_spinUnlock(&c->lock);
  if (reader)
    idris2_threadSchedule(reader);
}

// Take the first value out of a channel that is not empty, whose lock is
// held.  The reference is handed over to the caller, who makes `*writer`
// runnable once the lock is released.
static Idris2_Value *channel_take(Idris2_Channel *c, Idris2_Thread **writer) {
  Idris2_Value *value = c->slots[c->head];
  c->slots[c->head] = NULL;
  c->head = c->head + 1 == c->size ? 0 : c->head + 1;
  c->count--;
  // (the writers never wait with a deadline)
  *writer = channel_wake(&c->writers, 0);
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
  channel_lock(c);
  // Another reader may get the value first, hence the loop.
  while (c->count == 0) {
    idris2_threadBlockOn(&c->readers, &c->lock);
    channel_lock(c);
  }
  Idris2_Thread *writer;
  Idris2_Value *value = channel_take(c, &writer);
  idris2_spinUnlock(&c->lock);
  if (writer)
    idris2_threadSchedule(writer);
  return value;
}

void *refc_channelGetNonBlocking(Idris2_Value *erased, Idris2_Value *channel) {
  (void)erased;
  Idris2_Channel *c = (Idris2_Channel *)channel;
  channel_lock(c);
  int full = c->count > 0;
  Idris2_Thread *writer = NULL;
  Idris2_Value *value = full ? channel_take(c, &writer) : NULL;
  idris2_spinUnlock(&c->lock);
  if (writer)
    idris2_threadSchedule(writer);
  return full ? make_just(value) : NULL;
}

void *refc_channelGetWithTimeout(Idris2_Value *erased, Idris2_Value *channel,
                                 int64_t timeout_ms) {
  (void)erased;
  Idris2_Channel *c = (Idris2_Channel *)channel;
  int64_t deadline = idris2_deadlineAfter(
      timeout_ms > INT64_MAX / 1000 ? INT64_MAX : timeout_ms * 1000);
  channel_lock(c);
  while (c->count == 0) {
    c->timed_readers++;
    int woken = idris2_threadBlockOnUntil(&c->readers, &c->lock, deadline);
    channel_lock(c);
    c->timed_readers--;
    if (!woken) {
      break; // timed out
    }
  }
  int full = c->count > 0;
  Idris2_Thread *writer = NULL;
  Idris2_Value *value = full ? channel_take(c, &writer) : NULL;
  idris2_spinUnlock(&c->lock);
  if (writer)
    idris2_threadSchedule(writer);
  return full ? make_just(value) : NULL;
}

// ---------------------------------------------------------------------------
// Compare-and-swap on IORefs (see Data.IORef)
//
// A ticket is the value that an IORef held when the ticket was read, with a
// reference of its own: the value cannot be freed, so no other value can
// get its address while the ticket lives, and comparing addresses tells
// whether the IORef still holds that very value (or the same unboxed value,
// or the same static one).  A shared IORef is read and written under its
// lock (see prim.h), so the comparison and the write are done under it too.
// ---------------------------------------------------------------------------

void *refc_readForCAS(Idris2_Value *erased, Idris2_Value *ioref) {
  (void)erased;
  return idris2_readIORef(ioref);
}

void *refc_peekTicket(Idris2_Value *erased, Idris2_Value *ticket) {
  (void)erased;
  return idris2_newReference(ticket);
}

int64_t refc_casIORef(Idris2_Value *erased, Idris2_Value *ioref,
                      Idris2_Value *ticket, Idris2_Value *value) {
  (void)erased;
  Idris2_IORef *r = (Idris2_IORef *)ioref;
  Idris2_Value *old;
  if (idris2_isShared(ioref)) {
    // Other threads see the value from now on.  (Marking it before the lock
    // is taken keeps the lock short; it is harmless if the swap fails.)
    idris2_markShared(value);
    idris2_spinLock(&r->lock);
    old = r->v;
    if (old == ticket) {
      // The reference is taken before another thread can read the value.
      idris2_newReference(value);
      r->v = value;
    }
    idris2_spinUnlock(&r->lock);
  } else {
    old = r->v;
    if (old == ticket) {
      idris2_newReference(value);
      r->v = value;
    }
  }
  if (old != ticket)
    return 0;
  // (the ticket still holds a reference to the old value)
  idris2_removeReference(old);
  return 1;
}

// ---------------------------------------------------------------------------
// Futures
//
// Like in the Chez backend, a future is a thread that starts at once to
// compute a value, which `await` waits for and gives, as many times as it is
// called.  It is made of what the runtime already has: a constructor with
// the handle of the thread and an IORef, where the thread stores the value
// before it finishes.  `await` waits for the thread, as `threadWait` does,
// and reads the IORef.  The IORef is captured by the action of the thread,
// so it is shared (see memoryManagement.h) when threads run in parallel,
// and so is the value once it is written there.
//
// On the platforms without green threads the value is computed by
// `refc_makeFuture` itself, before it returns.
// ---------------------------------------------------------------------------

// The action of the thread of a future, a `PrimIO ()` once it has its first
// two arguments: `work` is the `() -> a` function to call, `cell` the IORef
// for its result.  Like the functions of the generated code, it takes its
// arguments over.
static Idris2_Value *future_run(Idris2_Value *work, Idris2_Value *cell,
                                Idris2_Value *world) {
  (void)world;
  // (the unit value is not looked at; this consumes `work`)
  Idris2_Value *result = idris2_apply_closure(work, NULL);
  idris2_Data_IORef_prim__writeIORef(NULL, cell, result, NULL);
  idris2_removeReference(result);
  idris2_removeReference(cell);
  return NULL;
}

void *refc_makeFuture(Idris2_Value *erased, Idris2_Closure *work) {
  (void)erased;
  Idris2_Value *cell = idris2_Data_IORef_prim__newIORef(NULL, NULL, NULL);
  Idris2_Value *handle = NULL;
  idris2_newReference((Idris2_Value *)work);
  idris2_newReference(cell);
#if IDRIS2_GREEN_THREADS
  Idris2_Closure *action =
      idris2_mkClosure((Idris2_Value * (*)()) future_run, 3, 2);
  action->args[0] = (Idris2_Value *)work;
  action->args[1] = cell;
  // The thread gets a reference of its own to the action.
  handle = (Idris2_Value *)refc_fork(action);
  idris2_removeReference((Idris2_Value *)action);
#else
  future_run((Idris2_Value *)work, cell, NULL);
#endif
  Idris2_Constructor *future = idris2_newConstructor(2, 0);
  future->args[0] = handle;
  future->args[1] = cell;
  return future;
}

void *refc_awaitFuture(Idris2_Value *erased, Idris2_Value *future) {
  (void)erased;
  Idris2_Constructor *f = (Idris2_Constructor *)future;
  // (returns at once when the thread is done, or when there is none)
  refc_threadWait(f->args[0]);
  return idris2_readIORef(f->args[1]);
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
