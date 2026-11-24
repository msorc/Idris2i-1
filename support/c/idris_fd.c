#include "idris_fd.h"

#include <errno.h>
#include <time.h>

#ifdef _WIN32
#include <fcntl.h>
#include <io.h>
#include <windows.h>
#else
#include <fcntl.h>
#include <poll.h>
#include <pthread.h>
#include <signal.h>
#include <unistd.h>
#endif

int idris2i_1_fdSetNonBlocking(int fd) {
#ifdef _WIN32
  (void)fd;
  return -ENOSYS;
#else
  int flags = fcntl((int)fd, F_GETFL);
  if (flags < 0 || fcntl((int)fd, F_SETFL, flags | O_NONBLOCK) < 0) {
    return -errno;
  }
  return 0;
#endif
}

int idris2i_1_fdRead(int fd, char *buffer, int offset, int max) {
  for (;;) {
#ifdef _WIN32
    int n = _read(fd, buffer + offset,
                  max > 0x7fffffff ? 0x7fffffff : (unsigned)max);
#else
    ssize_t n = read((int)fd, buffer + offset, (size_t)max);
#endif
    if (n >= 0) {
      return (int64_t)n;
    }
    if (errno != EINTR) {
      return -errno;
    }
  }
}

#ifndef _WIN32
// write(2) with SIGPIPE blocked in the calling thread: a write to a pipe or
// a socket whose reader is gone fails with EPIPE instead of killing the
// program, and the SIGPIPE that it raised is taken out of the pending
// signals of the thread before the mask is restored.  The disposition of
// SIGPIPE in the process is left alone (`prog | head` still ends `prog`
// quietly when it writes with the C library).  When the thread blocks
// SIGPIPE already, it is left pending, as the program asked.
static ssize_t write_no_sigpipe(int fd, const char *buf, size_t len) {
  sigset_t pipe_set, old;
  sigemptyset(&pipe_set);
  sigaddset(&pipe_set, SIGPIPE);
  if (pthread_sigmask(SIG_BLOCK, &pipe_set, &old) != 0) {
    return write(fd, buf, len);
  }
  ssize_t n = write(fd, buf, len);
  int err = errno;
  if (n < 0 && err == EPIPE && !sigismember(&old, SIGPIPE)) {
    // (a SIGPIPE that was pending before is not possible: it was not
    // blocked, so it was delivered)
    struct timespec zero = {0, 0};
    while (sigtimedwait(&pipe_set, NULL, &zero) < 0 && errno == EINTR) {
    }
  }
  pthread_sigmask(SIG_SETMASK, &old, NULL);
  errno = err;
  return n;
}
#endif

int idris2i_1_fdWrite(int fd, const char *buffer, int offset, int len) {
  for (;;) {
#ifdef _WIN32
    int n = _write(fd, buffer + offset,
                   len > 0x7fffffff ? 0x7fffffff : (unsigned)len);
#else
    ssize_t n = write_no_sigpipe(fd, buffer + offset, (size_t)len);
#endif
    if (n >= 0) {
      return (int64_t)n;
    }
    if (errno != EINTR) {
      return -errno;
    }
  }
}

int64_t idris2i_1_fdPipe(void) {
  int fds[2];
#ifdef _WIN32
  if (_pipe(fds, 65536, _O_BINARY | _O_NOINHERIT) != 0) {
    return -errno;
  }
#else
  if (pipe(fds) != 0) {
    return -errno;
  }
  // (the runtimes fork to run commands: the child must not keep the pipe)
  (void)fcntl(fds[0], F_SETFD, FD_CLOEXEC);
  (void)fcntl(fds[1], F_SETFD, FD_CLOEXEC);
#endif
  return (int64_t)(uint32_t)fds[0] | ((int64_t)fds[1] << 32);
}

int idris2i_1_fdClose(int fd) {
#ifdef _WIN32
  if (_close((int)fd) != 0) {
    return -errno;
  }
#else
  // (not again on EINTR: the number may have been reused)
  if (close((int)fd) != 0 && errno != EINTR) {
    return -errno;
  }
#endif
  return 0;
}

int64_t idris2i_1_fdMonotonicNanoseconds(void) {
#ifdef _WIN32
  static LARGE_INTEGER frequency;
  LARGE_INTEGER counter;
  if (frequency.QuadPart == 0) {
    QueryPerformanceFrequency(&frequency);
  }
  QueryPerformanceCounter(&counter);
  return (int64_t)((double)counter.QuadPart * 1e9 / (double)frequency.QuadPart);
#else
  struct timespec now;
  clock_gettime(CLOCK_MONOTONIC, &now);
  return (int64_t)now.tv_sec * 1000000000 + (int64_t)now.tv_nsec;
#endif
}

int idris2i_1_fdWaitBlocking(int fd, int event, int64_t deadline_ns) {
  if (fd < 0) {
    return -EBADF;
  }
  if (event != 1 && event != 2) {
    return -EINVAL;
  }
#ifdef _WIN32
  (void)deadline_ns;
  return 1;
#else
  struct pollfd p;
  p.fd = (int)fd;
  p.events = event == 1 ? POLLIN : POLLOUT;
  for (;;) {
    int timeout = -1;
    if (deadline_ns >= 0) {
      int64_t remaining = deadline_ns - idris2i_1_fdMonotonicNanoseconds();
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

void idris2i_1_fdForget(int fd) { (void)fd; }

int idris2i_1_fdEAGAIN(void) { return EAGAIN; }
int idris2i_1_fdEWOULDBLOCK(void) { return EWOULDBLOCK; }
int idris2i_1_fdEINTR(void) { return EINTR; }
int idris2i_1_fdEBADF(void) { return EBADF; }
int idris2i_1_fdEINVAL(void) { return EINVAL; }
