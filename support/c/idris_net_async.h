#pragma once

#include <stdint.h>

// Non-blocking sockets (see Network.Socket.Async in the network library).
//
// The sockets that these functions make are non-blocking and close-on-exec,
// and no function here blocks: a call that cannot go on returns -EAGAIN (an
// EWOULDBLOCK of the system is returned as -EAGAIN too), after which the
// caller waits for the socket with idris2_ioWait (RefC) or
// idris2_fdWaitBlocking (the other back ends), then tries again.  The one
// exception is idrnet_async_resolve, which runs getaddrinfo(3) on a pool
// thread on RefC.
//
// As in idris_fd.h, an Idris `Int` is an `int` here, a `Buffer` is a pointer
// to its bytes, and every function that can fail returns minus the errno
// code, as errno belongs to the OS thread, which a green thread may change
// between two calls.  An interrupted call (EINTR) is made again.
//
// Families are given by small codes of their own, the same on every
// system: 1 Unix, 4 IPv4, 6 IPv6.  Socket types: 1 stream, 2 datagram.
// Addresses are numeric ("127.0.0.1", "::1", "fe80::1%eth0", a path for
// Unix sockets); the empty string is the wildcard address for bind.

// The size of a buffer that holds any socket address (for
// idrnet_async_accept_addr, idrnet_async_recvfrom, idrnet_async_getname).
#define IDRNET_ASYNC_ADDR_SIZE 128

// A non-blocking, close-on-exec socket; writes to it do not raise SIGPIPE.
// Returns the descriptor or -errno.
int idrnet_async_socket(int family, int type);

// bind(2) to a numeric address.  Returns 0 or -errno (-EINVAL for an
// address that is not numeric).
int idrnet_async_bind(int fd, int family, const char *host, int port);

// listen(2).  Returns 0 or -errno.
int idrnet_async_listen(int fd, int backlog);

// Start connect(2) to a numeric address: returns 0 when connected, or
// -EINPROGRESS when the connection goes on in the background (wait until
// the socket is writable, then call idrnet_async_connect_result), or -errno.
int idrnet_async_connect(int fd, int family, const char *host, int port);

// The result of a connection started by idrnet_async_connect (SO_ERROR):
// 0 when it is connected, -EINPROGRESS while it goes on, or -errno.
int idrnet_async_connect_result(int fd);

// accept(2): a non-blocking, close-on-exec socket, or -errno.  A connection
// that was aborted before it was accepted is skipped.
int idrnet_async_accept(int fd);

// Like idrnet_async_accept, and writes the address of the peer into `addr`
// (IDRNET_ASYNC_ADDR_SIZE bytes).
int idrnet_async_accept_addr(int fd, char *addr);

// recv(2) into `buf + offset`, at most `len` bytes: the number of bytes
// (0 at the end of the stream) or -errno.
int idrnet_async_recv(int fd, char *buf, int offset, int len);

// send(2) from `buf + offset`, at most `len` bytes, without SIGPIPE: the
// number of bytes sent or -errno (-EPIPE once the peer is gone).
int idrnet_async_send(int fd, const char *buf, int offset, int len);

// Send `len1` bytes of `buf1` from `off1`, then `len2` bytes of `buf2` from
// `off2`, in one call (sendmsg(2) with two parts): the number of bytes
// sent, which may end in either part, or -errno.
int idrnet_async_send2(int fd, const char *buf1, int off1, int len1,
                       const char *buf2, int off2, int len2);

// recvfrom(2) into `buf + offset`: the number of bytes or -errno.  The
// address of the sender goes into `addr` (IDRNET_ASYNC_ADDR_SIZE bytes).
int idrnet_async_recvfrom(int fd, char *buf, int offset, int len, char *addr);

// sendto(2) from `buf + offset` to a numeric address: the number of bytes
// or -errno.
int idrnet_async_sendto(int fd, const char *buf, int offset, int len,
                        int family, const char *host, int port);

// shutdown(2): `how` 0 reading, 1 writing, 2 both.  Returns 0 or -errno.
int idrnet_async_shutdown(int fd, int how);

// Socket options, by codes of their own: 1 SO_REUSEADDR, 2 SO_REUSEPORT,
// 3 TCP_NODELAY, 4 SO_KEEPALIVE, 5 SO_RCVBUF, 6 SO_SNDBUF, 7 SO_LINGER,
// 8 IPV6_V6ONLY, 9 SO_BROADCAST.  For SO_LINGER, `value` is the time in
// seconds, a negative one turning lingering off.  Returns 0 or -errno
// (-ENOPROTOOPT for an option that the system does not have).
int idrnet_async_setopt(int fd, int option, int value);

// The value of an option, or -errno.  SO_LINGER gives 0 when lingering is
// off, and 1 + the time in seconds when it is on.
int idrnet_async_getopt(int fd, int option);

// getsockname(2) (`peer` 0) or getpeername(2) (`peer` 1) into `addr`
// (IDRNET_ASYNC_ADDR_SIZE bytes).  Returns 0 or -errno.
int idrnet_async_getname(int fd, int peer, char *addr);

// The parts of an address that one of the functions above wrote: its
// family code (0 when it is of another family), its port (0 for Unix
// sockets) and its numeric host (the path of a Unix socket), which is valid
// until the next call of the same thread.
int idrnet_async_addr_family(const char *addr);
int idrnet_async_addr_port(const char *addr);
const char *idrnet_async_addr_host(const char *addr);

// Restore the blocking mode of `fd` and make the RefC reactor forget it,
// before handing it over to code that blocks (fdopen(3), say).  Returns 0
// or -errno.
int idrnet_async_make_blocking(int fd);

// strerror(3), valid until the next call of the same thread.
const char *idrnet_async_strerror(int err);

// Name resolution.  idrnet_async_strdup copies an Idris string into
// memory of C (for a call that must not hold on to Idris values); the
// copy is freed by idrnet_async_resolve.  idrnet_async_resolve runs
// getaddrinfo(3) for `host` (taken over and freed) and the numeric `port`,
// limited to `family` (0 any, 4, 6), on a pool thread on RefC, and returns
// its result (NULL when out of memory, which the accessors accept): the status (0, or a code of getaddrinfo),
// the message of an error, and the numeric addresses found, in the order of
// getaddrinfo.  Free it with idrnet_async_resolve_free.
void *idrnet_async_strdup(const char *s);
void *idrnet_async_resolve(void *host, int port, int family);
int idrnet_async_resolve_status(void *res);
const char *idrnet_async_resolve_error(void *res);
int idrnet_async_resolve_count(void *res);
int idrnet_async_resolve_family(void *res, int i);
int idrnet_async_resolve_port(void *res, int i);
const char *idrnet_async_resolve_host(void *res, int i);
void idrnet_async_resolve_free(void *res);

// errno codes
int idrnet_async_EINPROGRESS(void);
int idrnet_async_ETIMEDOUT(void);
int idrnet_async_EPIPE(void);
int idrnet_async_ECONNRESET(void);
int idrnet_async_ECONNREFUSED(void);
int idrnet_async_ENOTCONN(void);
