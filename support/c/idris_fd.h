#pragma once

#include <stdint.h>

// Raw file descriptors (see System.IO.Fd and System.IO.Wait in base).  The
// parameters that are an `Int` in Idris are an `int` here, as the Chez back
// end passes them so (an `Int64` is an `int64_t`).  The
// functions that can fail return minus the errno code, so that the caller
// does not need errno, which belongs to the OS thread that made the call.

// Make `fd` non-blocking.  Returns 0 or -errno.
int idris2_fdSetNonBlocking(int fd);

// read(2) into `buffer + offset`, at most `max` bytes.  Returns the number
// of bytes read (0 at the end of the file) or -errno.
int idris2_fdRead(int fd, char *buffer, int offset, int max);

// write(2) from `buffer + offset`, at most `len` bytes.  Returns the number
// of bytes written or -errno.  A write to a pipe or a socket whose reader
// is gone returns -EPIPE: SIGPIPE is blocked in the calling thread for the
// call (and the one that it raised is discarded), so it does not kill the
// program.
int idris2_fdWrite(int fd, const char *buffer, int offset, int len);

// pipe(2), close-on-exec: returns `read_end | (write_end << 32)`, or -errno.
int64_t idris2_fdPipe(void);

// close(2): returns 0 or -errno.
int idris2_fdClose(int fd);

// The time on a monotonic clock, in nanoseconds.
int64_t idris2_fdMonotonicNanoseconds(void);

// Wait until `fd` is ready for reading (`event` 1) or writing (2), or the
// monotonic clock above reaches `deadline_ns` (none when negative), blocking
// the calling OS thread (for the back ends whose threads are OS threads; the
// RefC back end has idris2_ioWait).  Returns 1 when ready, 0 on timeout,
// -errno on error.  On Windows it returns 1 at once.
int idris2_fdWaitBlocking(int fd, int event, int64_t deadline_ns);

// Does nothing (the back ends that use idris2_fdWaitBlocking remember
// nothing about descriptors).
void idris2_fdForget(int fd);

// errno codes
int idris2_fdEAGAIN(void);
int idris2_fdEWOULDBLOCK(void);
int idris2_fdEINTR(void);
int idris2_fdEBADF(void);
int idris2_fdEINVAL(void);
