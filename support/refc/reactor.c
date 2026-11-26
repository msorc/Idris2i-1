// ---------------------------------------------------------------------------
// The reactor: green threads waiting for file descriptors (see reactor.h).
//
// Every descriptor that a thread waited for has an entry in a table indexed
// by the descriptor, which is allocated in chunks that never move, so an
// entry can be used without a lock on the table.  An entry holds a spin
// lock, a generation (bumped when the descriptor is closed or forgotten), a
// wait queue per direction (read, write), and the directions that the
// operating system reported ready while no thread waited for them.
//
// A descriptor is registered with the operating system the first time that
// a thread waits for it, for both directions, edge triggered (epoll's
// EPOLLET, kqueue's EV_CLEAR): the operating system reports a direction when
// it becomes ready, and the reactor remembers it until a thread waits.  The
// poll(2) back end (-DIDRIS2I_1_REACTOR_POLL, or a platform with neither epoll
// nor kqueue) is level triggered: it asks about the descriptors that have
// waiters only.
//
// A thread waits by taking the lock of the entry, looking at its ready bit
// and, when it is not set, blocking on the queue with the lock held: the
// scheduler releases it once the thread is off its stack (see threads.c),
// so the poller, which takes the lock to wake the waiters up, cannot miss
// one.  The poller wakes every waiter of a direction up; those that find no
// data wait again.
//
// The scheduler (threads.c) polls: a parked worker blocks in the poller
// instead of sleeping while threads wait for descriptors, and the busy
// workers poll without blocking now and then.  Waiters are only woken up on
// workers, as the scheduler needs; idris2i_1_reactorWakeup (a write to an
// eventfd or a pipe that the poller watches) is the only thing that other OS
// threads do.
// ---------------------------------------------------------------------------

#if defined(__linux__) && !defined(_GNU_SOURCE)
#define _GNU_SOURCE // ppoll
#endif

#include "reactor.h"
#include "threads.h"
#include "worker.h"

#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#if !IDRIS2I_1_GREEN_THREADS

// No other green thread can run: a wait blocks the program.

#ifdef _WIN32
#include <io.h>
#else
#include <poll.h>
#include <unistd.h>
#endif

int64_t idris2i_1_ioPending = 0;
int idris2i_1_reactorFineTimeout = 0;
uint64_t idris2i_1_reactorPolls = 0;

int64_t idris2i_1_ioWait(int64_t fd, int64_t event, int64_t deadline_ns) {
  if (fd < 0) {
    return -EBADF;
  }
  if (event != IDRIS2I_1_IO_READ && event != IDRIS2I_1_IO_WRITE) {
    return -EINVAL;
  }
#ifdef _WIN32
  // The descriptors of the C library cannot be polled on Windows: the read
  // or write that follows blocks.
  (void)deadline_ns;
  return 1;
#else
  struct pollfd p;
  p.fd = (int)fd;
  p.events = event == IDRIS2I_1_IO_READ ? POLLIN : POLLOUT;
  for (;;) {
    int timeout = -1;
    if (deadline_ns >= 0) {
      int64_t remaining = deadline_ns - idris2i_1_monotonicNanoseconds();
      if (remaining <= 0) {
        timeout = 0;
      } else {
        int64_t ms = (remaining + 999999) / 1000000;
        timeout = ms > 0x7fffffff ? 0x7fffffff : (int)ms;
      }
    }
    p.revents = 0;
    int n = poll(&p, 1, timeout);
    if (n < 0) {
      if (errno == EINTR) {
        continue;
      }
      return -errno;
    }
    if (n > 0) {
      return (p.revents & POLLNVAL) ? -EBADF : 1;
    }
    if (timeout == 0) {
      return 0;
    }
  }
#endif
}

int64_t idris2i_1_ioClose(int64_t fd) {
  if (close((int)fd) != 0 && errno != EINTR) {
    return -errno;
  }
  return 0;
}

void idris2i_1_ioForget(int64_t fd) { (void)fd; }

int idris2i_1_reactorPoll(int64_t timeout_ns) {
  (void)timeout_ns;
  return 0;
}

void idris2i_1_reactorWakeup(void) {}

int idris2i_1_blockingCall(void (*fn)(void *), void *arg) {
  fn(arg);
  return 0;
}

#else /* IDRIS2I_1_GREEN_THREADS */

#include <fcntl.h>
#include <pthread.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>

#if defined(IDRIS2I_1_REACTOR_POLL)
#define REACTOR_POLL 1
#elif defined(__linux__)
#define REACTOR_EPOLL 1
#elif defined(__APPLE__) || defined(__FreeBSD__) || defined(__OpenBSD__) ||   \
    defined(__NetBSD__) || defined(__DragonFly__)
#define REACTOR_KQUEUE 1
#else
#define REACTOR_POLL 1
#endif

#if REACTOR_EPOLL
#include <sys/epoll.h>
#include <sys/eventfd.h>
#include <sys/syscall.h>
#elif REACTOR_KQUEUE
#include <sys/event.h>
#include <sys/types.h>
#else
#include <poll.h>
#endif

// The threads.c side (see threads.h).
int idris2i_1_threadStopping(void);

// Read by the scheduler at every switch while it is 0 (see threads.c): on a
// cache line of its own, as the waiters write it.
__attribute__((aligned(64))) int64_t idris2i_1_ioPending = 0;
__attribute__((aligned(64))) uint64_t idris2i_1_reactorPolls = 0;
int idris2i_1_reactorFineTimeout = 0;

typedef struct {
  Idris2i_1_SpinLock lock;
  uint32_t gen;         // bumped by idris2i_1_ioClose and idris2i_1_ioForget
  uint8_t registered;   // with the operating system
  uint8_t always_ready; // a regular file
  uint8_t ready;        // the directions reported ready that nobody took
  int32_t waiters[2];   // the threads waiting, per direction
  int32_t pslot;        // poll(2) back end: index + 1 in poll_fds, or 0
  Idris2i_1_WaitQueue queue[2];
} IoEntry;

#define CHUNK_BITS 10
#define CHUNK_SIZE (1 << CHUNK_BITS)
#define MAX_CHUNKS 4096 // descriptors up to 4M

static IoEntry *chunks[MAX_CHUNKS];

// The entry of `fd`, made if `make` is set (NULL if it cannot be).
static IoEntry *entry_of(int64_t fd, int make) {
  if (fd < 0 || fd >= (int64_t)MAX_CHUNKS * CHUNK_SIZE) {
    return NULL;
  }
  IoEntry **slot = &chunks[fd >> CHUNK_BITS];
  IoEntry *chunk = __atomic_load_n(slot, __ATOMIC_ACQUIRE);
  if (!chunk) {
    if (!make) {
      return NULL;
    }
    IoEntry *fresh = calloc(CHUNK_SIZE, sizeof(IoEntry));
    if (!fresh) {
      return NULL;
    }
    IoEntry *expected = NULL;
    if (__atomic_compare_exchange_n(slot, &expected, fresh, 0,
                                    __ATOMIC_ACQ_REL, __ATOMIC_ACQUIRE)) {
      chunk = fresh;
    } else {
      free(fresh); // made by another thread at the same time
      chunk = expected;
    }
  }
  return &chunk[fd & (CHUNK_SIZE - 1)];
}

// ---------------------------------------------------------------------------
// The poller of the operating system
// ---------------------------------------------------------------------------

static pthread_once_t reactor_once = PTHREAD_ONCE_INIT;
static int reactor_error = 0; // errno of a failed creation
static int reactor_ready = 0;
// idris2i_1_reactorWakeup writes to wake_fds[1]; the poller watches wake_fds[0]
// (the same eventfd on Linux).
static int wake_fds[2] = {-1, -1};
static int wake_pending = 0;

#define WAKE_TOKEN UINT64_MAX

#if !REACTOR_EPOLL
static int set_cloexec_nonblock(int fd) {
  int flags = fcntl(fd, F_GETFD);
  if (flags < 0 || fcntl(fd, F_SETFD, flags | FD_CLOEXEC) < 0) {
    return -1;
  }
  flags = fcntl(fd, F_GETFL);
  if (flags < 0 || fcntl(fd, F_SETFL, flags | O_NONBLOCK) < 0) {
    return -1;
  }
  return 0;
}

static int make_wake_pipe(void) {
  if (pipe(wake_fds) != 0) {
    return -1;
  }
  if (set_cloexec_nonblock(wake_fds[0]) != 0 ||
      set_cloexec_nonblock(wake_fds[1]) != 0) {
    return -1;
  }
  return 0;
}
#endif

// The wakeups are for the thread that blocks in the poller (there is one at
// most, see park in threads.c): only it drains them.  A thread that polls
// without blocking leaves them, or the blocked one could miss its wakeup:
// woken up by the write, it would find nothing to report and wait again.
static void drain_wakeup(void) {
  char buf[64];
  while (read(wake_fds[0], buf, sizeof buf) > 0) {
  }
  // (after the read: a wakeup that comes in between is not lost, as this
  // poll returns anyway)
  __atomic_store_n(&wake_pending, 0, __ATOMIC_RELEASE);
}

void idris2i_1_reactorWakeup(void) {
  if (!__atomic_load_n(&reactor_ready, __ATOMIC_ACQUIRE)) {
    return;
  }
  if (__atomic_exchange_n(&wake_pending, 1, __ATOMIC_ACQ_REL)) {
    return; // the poller has not seen the previous one yet
  }
#if REACTOR_EPOLL
  uint64_t one = 1;
#else
  char one = 1;
#endif
  while (write(wake_fds[1], &one, sizeof one) < 0 && errno == EINTR) {
  }
}

// The reactor exists: the scheduler may poll it and wake its poller up from
// now on.  The scheduler calls them through the hooks of reactor.h, so that
// a program that never waits for a descriptor does not link the poller.  And
// threads will block in idris2i_1_ioWait and idris2i_1_blockingCall, which
// make the reactor first.
static void reactor_publish(void) {
  idris2i_1_threadsMayBlock();
  __atomic_store_n(&idris2i_1_reactorPollHook, idris2i_1_reactorPoll,
                   __ATOMIC_RELEASE);
  __atomic_store_n(&idris2i_1_reactorWakeupHook, idris2i_1_reactorWakeup,
                   __ATOMIC_RELEASE);
  __atomic_store_n(&reactor_ready, 1, __ATOMIC_RELEASE);
}

#if REACTOR_EPOLL

static int epfd = -1;

#if defined(SYS_epoll_pwait2) && defined(__LP64__)
#define HAVE_EPOLL_PWAIT2 1
#endif

static void reactor_create(void) {
  epfd = epoll_create1(EPOLL_CLOEXEC);
  if (epfd < 0) {
    reactor_error = errno;
    return;
  }
  int efd = eventfd(0, EFD_CLOEXEC | EFD_NONBLOCK);
  if (efd < 0) {
    reactor_error = errno;
    return;
  }
  wake_fds[0] = wake_fds[1] = efd;
  struct epoll_event ev;
  memset(&ev, 0, sizeof ev);
  ev.events = EPOLLIN;
  ev.data.u64 = WAKE_TOKEN;
  if (epoll_ctl(epfd, EPOLL_CTL_ADD, efd, &ev) != 0) {
    reactor_error = errno;
    return;
  }
#if HAVE_EPOLL_PWAIT2
  // epoll_pwait2 (Linux 5.11) takes a timeout in nanoseconds.
  struct timespec zero = {0, 0};
  struct epoll_event dummy;
  if (syscall(SYS_epoll_pwait2, epfd, &dummy, 1, &zero, NULL, 0) >= 0) {
    idris2i_1_reactorFineTimeout = 1;
    // (the wake up descriptor cannot be ready yet: nothing is lost)
  }
#endif
  reactor_publish();
}

// Register `fd` (its entry is locked).  Returns 0 or -errno.
static int os_register(int fd, IoEntry *e) {
  struct epoll_event ev;
  memset(&ev, 0, sizeof ev);
  ev.events = EPOLLIN | EPOLLOUT | EPOLLRDHUP | EPOLLET;
  ev.data.u64 = (uint64_t)(uint32_t)fd | ((uint64_t)e->gen << 32);
  if (epoll_ctl(epfd, EPOLL_CTL_ADD, fd, &ev) != 0) {
    if (errno == EPERM) {
      e->always_ready = 1; // a regular file, or a directory
      return 0;
    }
    if (errno != EEXIST || epoll_ctl(epfd, EPOLL_CTL_MOD, fd, &ev) != 0) {
      return -errno;
    }
  }
  e->registered = 1;
  return 0;
}

static void os_deregister(int fd) {
  struct epoll_event ev;
  memset(&ev, 0, sizeof ev);
  (void)epoll_ctl(epfd, EPOLL_CTL_DEL, fd, &ev);
}

#elif REACTOR_KQUEUE

static int kqfd = -1;

static void reactor_create(void) {
  kqfd = kqueue();
  if (kqfd < 0 || set_cloexec_nonblock(kqfd) != 0) {
    reactor_error = errno;
    return;
  }
  if (make_wake_pipe() != 0) {
    reactor_error = errno;
    return;
  }
  struct kevent kev;
  EV_SET(&kev, wake_fds[0], EVFILT_READ, EV_ADD, 0, 0, 0);
  if (kevent(kqfd, &kev, 1, NULL, 0, NULL) != 0) {
    reactor_error = errno;
    return;
  }
  idris2i_1_reactorFineTimeout = 1; // kevent takes a timespec
  reactor_publish();
}

static void os_deregister(int fd) {
  struct kevent del[2];
  EV_SET(&del[0], fd, EVFILT_READ, EV_DELETE, 0, 0, 0);
  EV_SET(&del[1], fd, EVFILT_WRITE, EV_DELETE, 0, 0, 0);
  // (one of them may fail; the other is deleted anyway)
  (void)kevent(kqfd, del, 2, NULL, 0, NULL);
}

static int os_register(int fd, IoEntry *e) {
  struct kevent changes[2], results[2];
  // EV_RECEIPT: a result for every change, error or not.
  EV_SET(&changes[0], fd, EVFILT_READ, EV_ADD | EV_CLEAR | EV_RECEIPT, 0, 0,
         (void *)(uintptr_t)e->gen);
  EV_SET(&changes[1], fd, EVFILT_WRITE, EV_ADD | EV_CLEAR | EV_RECEIPT, 0, 0,
         (void *)(uintptr_t)e->gen);
  int n;
  while ((n = kevent(kqfd, changes, 2, results, 2, NULL)) < 0 &&
         errno == EINTR) {
  }
  if (n < 0) {
    return -errno;
  }
  for (int i = 0; i < n; i++) {
    if ((results[i].flags & EV_ERROR) && results[i].data != 0) {
      os_deregister(fd);
      return -(int)results[i].data;
    }
  }
  e->registered = 1;
  return 0;
}

#else /* REACTOR_POLL */

// The descriptors that have waiters, guarded by pset_lock.
static Idris2i_1_SpinLock pset_lock = 0;
static int *pset = NULL;
static int pset_count = 0, pset_capacity = 0;
// A poller blocks in poll(2): a descriptor that gets its first waiter must
// wake it up, so that it polls that one too.
static int poll_blocking = 0;
// Only one thread polls at a time (it owns poll_buf).
static int poll_busy = 0;
static struct pollfd *poll_buf = NULL;
static int poll_buf_capacity = 0;

static void reactor_create(void) {
  if (make_wake_pipe() != 0) {
    reactor_error = errno;
    return;
  }
#if defined(__linux__) || defined(__FreeBSD__) || defined(__NetBSD__) ||      \
    defined(__OpenBSD__) || defined(__DragonFly__)
  idris2i_1_reactorFineTimeout = 1; // ppoll takes a timespec
#endif
  reactor_publish();
}

static int os_register(int fd, IoEntry *e) {
  (void)fd;
  e->registered = 1;
  return 0;
}

static void os_deregister(int fd) { (void)fd; }

// The entry of `fd` (locked) gets its first waiter, or loses its last one.
static void pset_add(int fd, IoEntry *e) {
  idris2i_1_spinLock(&pset_lock);
  if (pset_count == pset_capacity) {
    int capacity = pset_capacity ? pset_capacity * 2 : 64;
    int *bigger = realloc(pset, (size_t)capacity * sizeof(int));
    if (!bigger) {
      idris2i_1_spinUnlock(&pset_lock);
      fprintf(stderr, "RefC: out of memory in the reactor\n");
      exit(1);
    }
    pset = bigger;
    pset_capacity = capacity;
  }
  pset[pset_count++] = fd;
  e->pslot = pset_count;
  idris2i_1_spinUnlock(&pset_lock);
  if (__atomic_load_n(&poll_blocking, __ATOMIC_SEQ_CST)) {
    idris2i_1_reactorWakeup();
  }
}

static void pset_remove(IoEntry *e) {
  idris2i_1_spinLock(&pset_lock);
  int i = e->pslot - 1;
  int last = pset[--pset_count];
  pset[i] = last;
  if (i != pset_count) {
    IoEntry *moved = entry_of(last, 0);
    moved->pslot = i + 1;
  }
  e->pslot = 0;
  idris2i_1_spinUnlock(&pset_lock);
}

#endif

// Make the reactor on first use.  Returns 0 or -errno.
static int reactor_init(void) {
  if (__atomic_load_n(&reactor_ready, __ATOMIC_ACQUIRE)) {
    return 0;
  }
  pthread_once(&reactor_once, reactor_create);
  if (!__atomic_load_n(&reactor_ready, __ATOMIC_ACQUIRE)) {
    return -(reactor_error ? reactor_error : ENOSYS);
  }
  return 0;
}

// ---------------------------------------------------------------------------
// Waiting and waking up
// ---------------------------------------------------------------------------

// The operating system says that `fd` is ready for the directions `bits`
// (for the generation `gen`, when `check_gen` is set).  Wakes up their
// waiters, or remembers it.  Returns the number of threads woken up.
static int dispatch(int fd, uint32_t gen, int check_gen, int bits) {
  IoEntry *e = entry_of(fd, 0);
  if (!e) {
    return 0;
  }
  int woken = 0;
  idris2i_1_spinLock(&e->lock);
  if (e->registered && (!check_gen || e->gen == gen)) {
    for (int d = 0; d < 2; d++) {
      int bit = d + 1;
      if (bits & bit) {
        int n = 0;
        while (idris2i_1_threadWakeOne(&e->queue[d])) {
          n++;
        }
        // The threads woken up take the event; otherwise the next waiter
        // does.
        if (n) {
          e->ready &= (uint8_t)~bit;
        } else {
          e->ready |= (uint8_t)bit;
        }
        woken += n;
      }
    }
  }
  idris2i_1_spinUnlock(&e->lock);
  return woken;
}

int64_t idris2i_1_ioWait(int64_t fd, int64_t event, int64_t deadline_ns) {
  if (fd < 0) {
    return -EBADF;
  }
  if (event != IDRIS2I_1_IO_READ && event != IDRIS2I_1_IO_WRITE) {
    return -EINVAL;
  }
  int r = reactor_init();
  if (r < 0) {
    return r;
  }
  IoEntry *e = entry_of(fd, 1);
  if (!e) {
    return fd >= (int64_t)MAX_CHUNKS * CHUNK_SIZE ? -EINVAL : -ENOMEM;
  }
  int d = (int)event - 1;
  int bit = (int)event;
  idris2i_1_spinLock(&e->lock);
  if (!e->registered && !e->always_ready) {
    struct stat st;
    if (fstat((int)fd, &st) != 0) {
      r = -errno;
    } else if (S_ISREG(st.st_mode) || S_ISDIR(st.st_mode)) {
      e->always_ready = 1; // never "not ready" (poll(2) says so too)
    } else {
      r = os_register((int)fd, e);
    }
    if (r < 0) {
      idris2i_1_spinUnlock(&e->lock);
      return r;
    }
  }
  if (e->always_ready) {
    idris2i_1_spinUnlock(&e->lock);
    return 1;
  }
  if (e->ready & bit) {
    e->ready &= (uint8_t)~bit;
    idris2i_1_spinUnlock(&e->lock);
    return 1;
  }
  if (deadline_ns >= 0 && deadline_ns <= idris2i_1_monotonicNanoseconds()) {
    idris2i_1_spinUnlock(&e->lock);
    return 0;
  }
  uint32_t gen = e->gen;
  e->waiters[d]++;
#if REACTOR_POLL
  if (e->waiters[0] + e->waiters[1] == 1) {
    pset_add((int)fd, e);
  }
#endif
  if (__atomic_fetch_add(&idris2i_1_ioPending, 1, __ATOMIC_SEQ_CST) == 0) {
    // (the lock of the entry is held: the kick takes idle_lock, which is
    // never held while taking an entry lock)
    idris2i_1_threadKickWatcher();
  }
  int woken = 1;
  if (deadline_ns < 0) {
    idris2i_1_threadBlockOn(&e->queue[d], &e->lock);
  } else {
    woken = idris2i_1_threadBlockOnUntil(&e->queue[d], &e->lock, deadline_ns);
  }
  __atomic_fetch_sub(&idris2i_1_ioPending, 1, __ATOMIC_SEQ_CST);
  idris2i_1_spinLock(&e->lock);
  e->waiters[d]--;
#if REACTOR_POLL
  if (e->waiters[0] + e->waiters[1] == 0 && e->pslot) {
    pset_remove(e);
  }
#endif
  int closed = e->gen != gen;
  idris2i_1_spinUnlock(&e->lock);
  if (closed) {
    return -EBADF;
  }
  return woken ? 1 : 0;
}

// Forget `fd`: its waiters wake up and see that the generation changed.
static void forget(int64_t fd) {
  if (!__atomic_load_n(&reactor_ready, __ATOMIC_ACQUIRE)) {
    return;
  }
  IoEntry *e = entry_of(fd, 0);
  if (!e) {
    return;
  }
  idris2i_1_spinLock(&e->lock);
  e->gen++;
  e->ready = 0;
  e->always_ready = 0;
  idris2i_1_threadWakeAll(&e->queue[0]);
  idris2i_1_threadWakeAll(&e->queue[1]);
  if (e->registered) {
    os_deregister((int)fd);
    e->registered = 0;
  }
  idris2i_1_spinUnlock(&e->lock);
}

int64_t idris2i_1_ioClose(int64_t fd) {
  if (fd < 0) {
    return -EBADF;
  }
  forget(fd);
  // (on EINTR the descriptor is closed anyway on Linux, and its state is
  // unspecified elsewhere: it must not be closed again, as its number may
  // have been reused)
  if (close((int)fd) != 0 && errno != EINTR) {
    return -errno;
  }
  return 0;
}

void idris2i_1_ioForget(int64_t fd) {
  if (fd >= 0) {
    forget(fd);
  }
}

static void count_poll(void) {
  __atomic_store_n(&idris2i_1_reactorPolls,
                   __atomic_load_n(&idris2i_1_reactorPolls, __ATOMIC_RELAXED) + 1,
                   __ATOMIC_RELAXED);
}

#define MAX_EVENTS 64

#if REACTOR_EPOLL

static int os_poll(int64_t timeout_ns) {
  if (!__atomic_load_n(&reactor_ready, __ATOMIC_ACQUIRE)) {
    return 0;
  }
  struct epoll_event events[MAX_EVENTS];
  int n;
  if (timeout_ns == 0) {
    n = epoll_wait(epfd, events, MAX_EVENTS, 0);
  } else if (timeout_ns < 0) {
    n = epoll_wait(epfd, events, MAX_EVENTS, -1);
  }
#if HAVE_EPOLL_PWAIT2
  else if (idris2i_1_reactorFineTimeout) {
    struct timespec ts;
    ts.tv_sec = (time_t)(timeout_ns / 1000000000);
    ts.tv_nsec = (long)(timeout_ns % 1000000000);
    n = (int)syscall(SYS_epoll_pwait2, epfd, events, MAX_EVENTS, &ts, NULL, 0);
  }
#endif
  else {
    int64_t ms = (timeout_ns + 999999) / 1000000;
    n = epoll_wait(epfd, events, MAX_EVENTS, ms > 0x7fffffff ? 0x7fffffff
                                                              : (int)ms);
  }
  count_poll();
  if (n <= 0 || idris2i_1_threadStopping()) {
    return 0; // (EINTR: the scheduler polls again soon)
  }
  int woken = 0;
  for (int i = 0; i < n; i++) {
    uint64_t token = events[i].data.u64;
    if (token == WAKE_TOKEN) {
      if (timeout_ns != 0) {
        drain_wakeup();
      }
      continue;
    }
    uint32_t ev = events[i].events;
    int bits = 0;
    if (ev & (EPOLLIN | EPOLLRDHUP | EPOLLHUP | EPOLLERR)) {
      bits |= IDRIS2I_1_IO_READ;
    }
    if (ev & (EPOLLOUT | EPOLLHUP | EPOLLERR)) {
      bits |= IDRIS2I_1_IO_WRITE;
    }
    woken += dispatch((int)(uint32_t)token, (uint32_t)(token >> 32), 1, bits);
  }
  return woken;
}

#elif REACTOR_KQUEUE

static int os_poll(int64_t timeout_ns) {
  if (!__atomic_load_n(&reactor_ready, __ATOMIC_ACQUIRE)) {
    return 0;
  }
  struct kevent events[MAX_EVENTS];
  struct timespec ts, *tsp = NULL;
  if (timeout_ns >= 0) {
    ts.tv_sec = (time_t)(timeout_ns / 1000000000);
    ts.tv_nsec = (long)(timeout_ns % 1000000000);
    tsp = &ts;
  }
  int n = kevent(kqfd, NULL, 0, events, MAX_EVENTS, tsp);
  count_poll();
  if (n <= 0 || idris2i_1_threadStopping()) {
    return 0;
  }
  int woken = 0;
  for (int i = 0; i < n; i++) {
    int fd = (int)events[i].ident;
    if (fd == wake_fds[0] && events[i].filter == EVFILT_READ) {
      if (timeout_ns != 0) {
        drain_wakeup();
      }
      continue;
    }
    int bits = 0;
    if (events[i].flags & EV_ERROR) {
      bits = IDRIS2I_1_IO_READ | IDRIS2I_1_IO_WRITE;
    } else if (events[i].filter == EVFILT_READ) {
      bits = IDRIS2I_1_IO_READ;
    } else if (events[i].filter == EVFILT_WRITE) {
      bits = IDRIS2I_1_IO_WRITE;
    }
    woken += dispatch(fd, (uint32_t)(uintptr_t)events[i].udata, 1, bits);
  }
  return woken;
}

#else /* REACTOR_POLL */

static int os_poll(int64_t timeout_ns) {
  if (!__atomic_load_n(&reactor_ready, __ATOMIC_ACQUIRE)) {
    return 0;
  }
  int zero = 0;
  if (!__atomic_compare_exchange_n(&poll_busy, &zero, 1, 0, __ATOMIC_ACQUIRE,
                                   __ATOMIC_RELAXED)) {
    return 0; // another thread polls
  }
  if (timeout_ns != 0) {
    __atomic_store_n(&poll_blocking, 1, __ATOMIC_SEQ_CST);
  }
  // The descriptors to look at: the wake up pipe, and those with waiters.
  idris2i_1_spinLock(&pset_lock);
  int count = pset_count + 1;
  if (count > poll_buf_capacity) {
    int capacity = count * 2;
    struct pollfd *bigger =
        realloc(poll_buf, (size_t)capacity * sizeof(struct pollfd));
    if (!bigger) {
      idris2i_1_spinUnlock(&pset_lock);
      fprintf(stderr, "RefC: out of memory in the reactor\n");
      exit(1);
    }
    poll_buf = bigger;
    poll_buf_capacity = capacity;
  }
  poll_buf[0].fd = wake_fds[0];
  poll_buf[0].events = POLLIN;
  for (int i = 0; i < pset_count; i++) {
    poll_buf[i + 1].fd = pset[i];
    poll_buf[i + 1].events = 0;
  }
  idris2i_1_spinUnlock(&pset_lock);
  // (the directions with waiters, read without the lock of the pset: an
  // entry is in it while it has waiters)
  for (int i = 1; i < count; i++) {
    IoEntry *e = entry_of(poll_buf[i].fd, 0);
    short events = 0;
    if (e) {
      idris2i_1_spinLock(&e->lock);
      if (e->waiters[0]) {
        events |= POLLIN;
      }
      if (e->waiters[1]) {
        events |= POLLOUT;
      }
      idris2i_1_spinUnlock(&e->lock);
    }
    poll_buf[i].events = events;
    poll_buf[i].revents = 0;
  }
  poll_buf[0].revents = 0;
  int n;
#if defined(__linux__) || defined(__FreeBSD__) || defined(__NetBSD__) ||      \
    defined(__OpenBSD__) || defined(__DragonFly__)
  struct timespec ts, *tsp = NULL;
  if (timeout_ns >= 0) {
    ts.tv_sec = (time_t)(timeout_ns / 1000000000);
    ts.tv_nsec = (long)(timeout_ns % 1000000000);
    tsp = &ts;
  }
  n = ppoll(poll_buf, (nfds_t)count, tsp, NULL);
#else
  int ms = -1;
  if (timeout_ns >= 0) {
    int64_t m = (timeout_ns + 999999) / 1000000;
    ms = m > 0x7fffffff ? 0x7fffffff : (int)m;
  }
  n = poll(poll_buf, (nfds_t)count, ms);
#endif
  __atomic_store_n(&poll_blocking, 0, __ATOMIC_SEQ_CST);
  count_poll();
  int woken = 0;
  if (n > 0 && !idris2i_1_threadStopping()) {
    if (poll_buf[0].revents && timeout_ns != 0) {
      drain_wakeup();
    }
    for (int i = 1; i < count; i++) {
      short re = poll_buf[i].revents;
      if (!re) {
        continue;
      }
      int bits = 0;
      if (re & (POLLIN | POLLHUP | POLLERR | POLLNVAL)) {
        bits |= IDRIS2I_1_IO_READ;
      }
      if (re & (POLLOUT | POLLHUP | POLLERR | POLLNVAL)) {
        bits |= IDRIS2I_1_IO_WRITE;
      }
      // (only the directions that have waiters: the others were not asked)
      int asked = (poll_buf[i].events & POLLIN ? IDRIS2I_1_IO_READ : 0) |
                  (poll_buf[i].events & POLLOUT ? IDRIS2I_1_IO_WRITE : 0);
      woken += dispatch(poll_buf[i].fd, 0, 0, bits & asked);
    }
  }
  __atomic_store_n(&poll_busy, 0, __ATOMIC_RELEASE);
  return woken;
}

#endif

// ---------------------------------------------------------------------------
// Blocking calls (see idris2i_1_blockingCall)
//
// A call runs on one of a pool of plain OS threads, which never touch the
// Idris runtime.  When it is done, the pool thread pushes it onto the list
// of completed calls and wakes the poller up (idris2i_1_reactorWakeup); the
// worker that polls next wakes the caller up, so that, as the scheduler
// needs, green threads are only woken up on workers.
// ---------------------------------------------------------------------------

typedef struct BlockingCall {
  void (*fn)(void *);
  void *arg;
  Idris2i_1_SpinLock lock;
  int done;
  Idris2i_1_WaitQueue waiter;
  struct BlockingCall *next; // in the queue of the pool, then in `completed`
} BlockingCall;

// The completed calls, pushed by the pool threads (a lock-free stack).
static BlockingCall *completed = NULL;

// Wake up the callers of the completed calls.  Returns how many.
static int finish_blocking_calls(void) {
  BlockingCall *call = __atomic_exchange_n(&completed, NULL, __ATOMIC_ACQUIRE);
  int woken = 0;
  while (call) {
    BlockingCall *next = call->next;
    idris2i_1_spinLock(&call->lock);
    call->done = 1;
    woken += idris2i_1_threadWakeOne(&call->waiter);
    // (the caller takes the lock before it returns: the call, which is on
    // its stack, is not touched after this)
    idris2i_1_spinUnlock(&call->lock);
    call = next;
  }
  return woken;
}

// (called through idris2i_1_reactorPollHook, which is set once the reactor
// exists: it need not look whether it does)
int idris2i_1_reactorPoll(int64_t timeout_ns) {
  int woken = os_poll(timeout_ns);
  if (__atomic_load_n(&completed, __ATOMIC_RELAXED) &&
      !idris2i_1_threadStopping()) {
    woken += finish_blocking_calls();
  }
  return woken;
}

#if IDRIS2I_1_MULTICORE

static pthread_mutex_t pool_lock = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t pool_cond = PTHREAD_COND_INITIALIZER;
static BlockingCall *pool_head = NULL, *pool_tail = NULL;
static int pool_threads = 0; // started so far
static int pool_idle = 0;    // waiting for a call
static int pool_max = 0;     // IDRIS2I_1_BLOCKING_THREADS

#define DEFAULT_BLOCKING_THREADS 64

static int configured_blocking_threads(void) {
  const char *env = getenv("IDRIS2I_1_BLOCKING_THREADS");
  if (env && *env) {
    char *end = NULL;
    long n = strtol(env, &end, 10);
    if (*end == '\0' && n >= 1 && n <= 4096) {
      return (int)n;
    }
    fprintf(stderr,
            "RefC: ignoring IDRIS2I_1_BLOCKING_THREADS=%s (expected a number of "
            "threads from 1 to 4096)\n",
            env);
  }
  return DEFAULT_BLOCKING_THREADS;
}

static void *pool_main(void *unused) {
  (void)unused;
  pthread_mutex_lock(&pool_lock);
  for (;;) {
    while (!pool_head) {
      pool_idle++;
      pthread_cond_wait(&pool_cond, &pool_lock);
      pool_idle--;
    }
    BlockingCall *call = pool_head;
    pool_head = call->next;
    if (!pool_head) {
      pool_tail = NULL;
    }
    pthread_mutex_unlock(&pool_lock);
    call->fn(call->arg);
    BlockingCall *top = __atomic_load_n(&completed, __ATOMIC_RELAXED);
    do {
      call->next = top;
    } while (!__atomic_compare_exchange_n(&completed, &top, call, 1,
                                          __ATOMIC_RELEASE, __ATOMIC_RELAXED));
    idris2i_1_reactorWakeup();
    pthread_mutex_lock(&pool_lock);
  }
  return NULL;
}

// Queue `call` for the pool, starting a thread if none is idle and there
// are fewer than pool_max.  Returns 0, or -1 when there is no thread to run
// it.
static int pool_submit(BlockingCall *call) {
  pthread_mutex_lock(&pool_lock);
  if (pool_max == 0) {
    pool_max = configured_blocking_threads();
  }
  if (pool_idle == 0 && pool_threads < pool_max) {
    pthread_attr_t attr;
    pthread_attr_init(&attr);
    pthread_attr_setdetachstate(&attr, PTHREAD_CREATE_DETACHED);
    pthread_t thread;
    if (pthread_create(&thread, &attr, pool_main, NULL) == 0) {
      pool_threads++;
    }
    pthread_attr_destroy(&attr);
    if (pool_threads == 0) {
      pthread_mutex_unlock(&pool_lock);
      return -1;
    }
  }
  call->next = NULL;
  if (pool_tail) {
    pool_tail->next = call;
  } else {
    pool_head = call;
  }
  pool_tail = call;
  pthread_cond_signal(&pool_cond);
  pthread_mutex_unlock(&pool_lock);
  return 0;
}

int idris2i_1_blockingCall(void (*fn)(void *), void *arg) {
  if (reactor_init() < 0) {
    fn(arg);
    return -1;
  }
  BlockingCall call;
  memset(&call, 0, sizeof call);
  call.fn = fn;
  call.arg = arg;
  // (counted from now on, so that the workers poll and do not report a
  // deadlock while it runs)
  if (__atomic_fetch_add(&idris2i_1_ioPending, 1, __ATOMIC_SEQ_CST) == 0) {
    idris2i_1_threadKickWatcher();
  }
  if (pool_submit(&call) != 0) {
    __atomic_fetch_sub(&idris2i_1_ioPending, 1, __ATOMIC_SEQ_CST);
    fn(arg);
    return -1;
  }
  idris2i_1_spinLock(&call.lock);
  if (!call.done) {
    idris2i_1_threadBlockOn(&call.waiter, &call.lock);
    idris2i_1_spinLock(&call.lock);
  }
  idris2i_1_spinUnlock(&call.lock);
  __atomic_fetch_sub(&idris2i_1_ioPending, 1, __ATOMIC_SEQ_CST);
  return 0;
}

#else

// A single worker: nothing else could run while the call blocks.
int idris2i_1_blockingCall(void (*fn)(void *), void *arg) {
  fn(arg);
  return 0;
}

#endif

#endif /* IDRIS2I_1_GREEN_THREADS */
