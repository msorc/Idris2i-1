#pragma once

#include <stdint.h>

// ---------------------------------------------------------------------------
// Waiting for file descriptors
//
// A green thread that waits for a file descriptor to become readable or
// writable parks in the scheduler instead of blocking its worker: the
// reactor (reactor.c) asks the operating system which descriptors are ready
// (epoll on Linux, kqueue on macOS and the BSDs, poll(2) elsewhere or with
// -DIDRIS2I_1_REACTOR_POLL) and wakes their waiters up.
//
// The readiness is edge triggered: wait only after a read or a write failed
// with EAGAIN (or EWOULDBLOCK) on a non-blocking descriptor.  A wait may
// return "ready" while the descriptor is not ready (another thread took the
// data first, say): the caller tries again, and waits again on EAGAIN.
//
// On the platforms without green threads (Windows, WebAssembly), a wait
// blocks the program, as there is nothing else to run.
// ---------------------------------------------------------------------------

#define IDRIS2I_1_IO_READ 1
#define IDRIS2I_1_IO_WRITE 2

// Wait until `fd` is ready for `event` (IDRIS2I_1_IO_READ or IDRIS2I_1_IO_WRITE),
// or until the monotonic clock of the scheduler (idris2i_1_monotonicNanoseconds)
// reaches `deadline_ns` (a negative deadline means none).  Returns 1 when it
// is ready, 0 when the deadline expired, and minus an errno code on error:
// -EBADF when the descriptor was closed by idris2i_1_ioClose while waiting.
// A regular file is always ready.
int64_t idris2i_1_ioWait(int64_t fd, int64_t event, int64_t deadline_ns);

// Close `fd`: the threads that wait for it are woken up (their wait returns
// -EBADF), the reactor forgets it, then it is closed.  Returns 0, or minus
// the errno code of close(2).  Descriptors that a thread may have waited for
// must be closed this way (or forgotten first): the reactor keeps them
// registered with the operating system otherwise, and a new descriptor with
// the same number would never be reported ready.
int64_t idris2i_1_ioClose(int64_t fd);

// Make the reactor forget `fd` without closing it (before handing it over to
// C code, or to fdopen(3)).  Threads that wait for it are woken up as by
// idris2i_1_ioClose.
void idris2i_1_ioForget(int64_t fd);

// For the scheduler: wait up to `timeout_ns` nanoseconds (0: do not block,
// negative: no limit) for descriptors to become ready, and wake up their
// waiters.  Returns the number of threads woken up.  Called on workers only.
int idris2i_1_reactorPoll(int64_t timeout_ns);

// Make a call of idris2i_1_reactorPoll that blocks, in any thread, return
// early.  Safe to call from any OS thread.
void idris2i_1_reactorWakeup(void);

// The number of threads that wait for a descriptor, plus the blocking calls
// in progress (see idris2i_1_blockingCall).  The scheduler polls while it is
// not 0, and does not report a deadlock then.
extern int64_t idris2i_1_ioPending;

// Can idris2i_1_reactorPoll wait for less than a millisecond?  Set once the
// reactor exists.
extern int idris2i_1_reactorFineTimeout;

// How many times the reactor polled (for the monitor, see threads.c).
extern uint64_t idris2i_1_reactorPolls;

// Run `fn(arg)` on another OS thread, from a pool, and park the calling green
// thread until it is done, so that a call that blocks (a DNS lookup, say)
// does not block its worker.  `fn` must not touch Idris values nor call the
// runtime.  For C code, on a green thread.  The pool starts its threads as
// calls need them, up to IDRIS2I_1_BLOCKING_THREADS (default 64); the calls
// beyond that wait for a thread.  Returns 0, or -1 when no thread could be
// started (`fn` ran in the calling thread then).  Without several workers
// (-DIDRIS2I_1_SINGLE_WORKER, or no green threads), `fn` runs in the calling
// thread.
int idris2i_1_blockingCall(void (*fn)(void *), void *arg);
