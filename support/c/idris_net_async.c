// Non-blocking sockets for Network.Socket.Async (see idris_net_async.h).

#if defined(__linux__) && !defined(_GNU_SOURCE)
#define _GNU_SOURCE // accept4
#endif

#include "idris_net_async.h"

#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifdef _WIN32

// Not supported on Windows yet: every function fails with ENOSYS.

int idrnet_async_socket(int family, int type) {
  (void)family;
  (void)type;
  return -ENOSYS;
}
int idrnet_async_bind(int fd, int family, const char *host, int port) {
  (void)fd, (void)family, (void)host, (void)port;
  return -ENOSYS;
}
int idrnet_async_listen(int fd, int backlog) {
  (void)fd, (void)backlog;
  return -ENOSYS;
}
int idrnet_async_connect(int fd, int family, const char *host, int port) {
  (void)fd, (void)family, (void)host, (void)port;
  return -ENOSYS;
}
int idrnet_async_connect_result(int fd) {
  (void)fd;
  return -ENOSYS;
}
int idrnet_async_accept(int fd) {
  (void)fd;
  return -ENOSYS;
}
int idrnet_async_accept_addr(int fd, char *addr) {
  (void)fd, (void)addr;
  return -ENOSYS;
}
int idrnet_async_recv(int fd, char *buf, int offset, int len) {
  (void)fd, (void)buf, (void)offset, (void)len;
  return -ENOSYS;
}
int idrnet_async_send(int fd, const char *buf, int offset, int len) {
  (void)fd, (void)buf, (void)offset, (void)len;
  return -ENOSYS;
}
int idrnet_async_send2(int fd, const char *buf1, int off1, int len1,
                       const char *buf2, int off2, int len2) {
  (void)fd, (void)buf1, (void)off1, (void)len1, (void)buf2, (void)off2,
      (void)len2;
  return -ENOSYS;
}
int idrnet_async_recvfrom(int fd, char *buf, int offset, int len, char *addr) {
  (void)fd, (void)buf, (void)offset, (void)len, (void)addr;
  return -ENOSYS;
}
int idrnet_async_sendto(int fd, const char *buf, int offset, int len,
                        int family, const char *host, int port) {
  (void)fd, (void)buf, (void)offset, (void)len, (void)family, (void)host,
      (void)port;
  return -ENOSYS;
}
int idrnet_async_shutdown(int fd, int how) {
  (void)fd, (void)how;
  return -ENOSYS;
}
int idrnet_async_setopt(int fd, int option, int value) {
  (void)fd, (void)option, (void)value;
  return -ENOSYS;
}
int idrnet_async_getopt(int fd, int option) {
  (void)fd, (void)option;
  return -ENOSYS;
}
int idrnet_async_getname(int fd, int peer, char *addr) {
  (void)fd, (void)peer, (void)addr;
  return -ENOSYS;
}
int idrnet_async_addr_family(const char *addr) {
  (void)addr;
  return 0;
}
int idrnet_async_addr_port(const char *addr) {
  (void)addr;
  return 0;
}
const char *idrnet_async_addr_host(const char *addr) {
  (void)addr;
  return "";
}
int idrnet_async_make_blocking(int fd) {
  (void)fd;
  return 0;
}
const char *idrnet_async_strerror(int err) { return strerror(err); }

void *idrnet_async_strdup(const char *s) { return strdup(s); }
void *idrnet_async_resolve(void *host, int port, int family) {
  (void)port, (void)family;
  free(host);
  return NULL;
}
int idrnet_async_resolve_status(void *res) {
  (void)res;
  return -1;
}
const char *idrnet_async_resolve_error(void *res) {
  (void)res;
  return "name resolution is not supported on Windows yet";
}
int idrnet_async_resolve_count(void *res) {
  (void)res;
  return 0;
}
int idrnet_async_resolve_family(void *res, int i) {
  (void)res, (void)i;
  return 0;
}
int idrnet_async_resolve_port(void *res, int i) {
  (void)res, (void)i;
  return 0;
}
const char *idrnet_async_resolve_host(void *res, int i) {
  (void)res, (void)i;
  return "";
}
void idrnet_async_resolve_free(void *res) { (void)res; }

#else /* not _WIN32 */

#include <arpa/inet.h>
#include <fcntl.h>
#include <net/if.h>
#include <netdb.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <sys/socket.h>
#include <sys/types.h>
#include <sys/uio.h>
#include <sys/un.h>
#include <unistd.h>

#if defined(__APPLE__)
#include <dlfcn.h>
#endif

// ---------------------------------------------------------------------------
// The RefC runtime
//
// This library is linked into the programs of every back end, but only the
// programs of RefC have the reactor (support/refc/reactor.c).  Its functions
// are weak references on ELF systems (NULL elsewhere), and looked up with
// dlsym on macOS, whose linker wants the symbols of a library to exist.
// ---------------------------------------------------------------------------

typedef int (*BlockingCallFn)(void (*)(void *), void *);
typedef void (*ForgetFn)(int64_t);

#if defined(__ELF__)

extern int idris2i_1_blockingCall(void (*fn)(void *), void *arg)
    __attribute__((weak));
extern void idris2i_1_ioForget(int64_t fd) __attribute__((weak));

static BlockingCallFn blocking_call_fn(void) { return idris2i_1_blockingCall; }
static ForgetFn forget_fn(void) { return idris2i_1_ioForget; }

#elif defined(__APPLE__)

static BlockingCallFn blocking_call_fn(void) {
  return (BlockingCallFn)dlsym(RTLD_DEFAULT, "idris2i_1_blockingCall");
}
static ForgetFn forget_fn(void) {
  return (ForgetFn)dlsym(RTLD_DEFAULT, "idris2i_1_ioForget");
}

#else

static BlockingCallFn blocking_call_fn(void) { return NULL; }
static ForgetFn forget_fn(void) { return NULL; }

#endif

// ---------------------------------------------------------------------------
// Descriptors and addresses
// ---------------------------------------------------------------------------

#ifndef MSG_NOSIGNAL
#define MSG_NOSIGNAL 0 // macOS: SO_NOSIGPIPE is set on every socket instead
#endif

// -errno, with EWOULDBLOCK as EAGAIN.
static int neg_errno(void) {
  int e = errno;
#if EWOULDBLOCK != EAGAIN
  if (e == EWOULDBLOCK) {
    e = EAGAIN;
  }
#endif
  return -e;
}

static int set_flags(int fd) {
  int fl = fcntl(fd, F_GETFL);
  if (fl < 0 || fcntl(fd, F_SETFL, fl | O_NONBLOCK) < 0) {
    return -1;
  }
  int fd_fl = fcntl(fd, F_GETFD);
  if (fd_fl < 0 || fcntl(fd, F_SETFD, fd_fl | FD_CLOEXEC) < 0) {
    return -1;
  }
  return 0;
}

// What every new socket needs beyond SOCK_NONBLOCK | SOCK_CLOEXEC.
static int prepare(int fd, int flags_set) {
  if (!flags_set && set_flags(fd) != 0) {
    return -1;
  }
#ifdef SO_NOSIGPIPE
  int one = 1;
  (void)setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, sizeof one);
#endif
  return 0;
}

static int os_family(int family) {
  switch (family) {
  case 1:
    return AF_UNIX;
  case 4:
    return AF_INET;
  case 6:
    return AF_INET6;
  default:
    return -1;
  }
}

// Fill `ss` with a numeric address.  Returns its length, or -errno.
static int make_addr(int family, const char *host, int port,
                     struct sockaddr_storage *ss) {
  memset(ss, 0, sizeof *ss);
  if (port < 0 || port > 65535) {
    return -EINVAL;
  }
  switch (family) {
  case 1: {
    struct sockaddr_un *un = (struct sockaddr_un *)ss;
    size_t n = strlen(host);
    if (n == 0 || n >= sizeof un->sun_path) {
      return -ENAMETOOLONG;
    }
    un->sun_family = AF_UNIX;
    memcpy(un->sun_path, host, n + 1);
    return (int)sizeof *un;
  }
  case 4: {
    struct sockaddr_in *in = (struct sockaddr_in *)ss;
    in->sin_family = AF_INET;
    in->sin_port = htons((uint16_t)port);
    if (host[0] == '\0') {
      in->sin_addr.s_addr = htonl(INADDR_ANY);
    } else if (inet_pton(AF_INET, host, &in->sin_addr) != 1) {
      return -EINVAL;
    }
    return (int)sizeof *in;
  }
  case 6: {
    struct sockaddr_in6 *in6 = (struct sockaddr_in6 *)ss;
    in6->sin6_family = AF_INET6;
    in6->sin6_port = htons((uint16_t)port);
    if (host[0] == '\0') {
      in6->sin6_addr = in6addr_any;
      return (int)sizeof *in6;
    }
    char text[INET6_ADDRSTRLEN + IF_NAMESIZE + 2];
    size_t n = strlen(host);
    if (n >= sizeof text) {
      return -EINVAL;
    }
    memcpy(text, host, n + 1);
    char *scope = strchr(text, '%');
    if (scope) {
      *scope++ = '\0';
      char *end = NULL;
      unsigned long id = strtoul(scope, &end, 10);
      if (*scope == '\0' || *end != '\0') {
        id = if_nametoindex(scope);
        if (id == 0) {
          return -EINVAL;
        }
      }
      in6->sin6_scope_id = (uint32_t)id;
    }
    if (inet_pton(AF_INET6, text, &in6->sin6_addr) != 1) {
      return -EINVAL;
    }
    return (int)sizeof *in6;
  }
  default:
    return -EAFNOSUPPORT;
  }
}

int idrnet_async_socket(int family, int type) {
  int fam = os_family(family);
  if (fam < 0) {
    return -EAFNOSUPPORT;
  }
  int ty = type == 1 ? SOCK_STREAM : type == 2 ? SOCK_DGRAM : -1;
  if (ty < 0) {
    return -EINVAL;
  }
#if defined(SOCK_NONBLOCK) && defined(SOCK_CLOEXEC)
  int fd = socket(fam, ty | SOCK_NONBLOCK | SOCK_CLOEXEC, 0);
  int flags_set = 1;
#else
  int fd = socket(fam, ty, 0);
  int flags_set = 0;
#endif
  if (fd < 0) {
    return neg_errno();
  }
  if (prepare(fd, flags_set) != 0) {
    int e = neg_errno();
    close(fd);
    return e;
  }
  return fd;
}

int idrnet_async_bind(int fd, int family, const char *host, int port) {
  struct sockaddr_storage ss;
  int len = make_addr(family, host, port, &ss);
  if (len < 0) {
    return len;
  }
  if (bind(fd, (struct sockaddr *)&ss, (socklen_t)len) != 0) {
    return neg_errno();
  }
  return 0;
}

int idrnet_async_listen(int fd, int backlog) {
  if (listen(fd, backlog) != 0) {
    return neg_errno();
  }
  return 0;
}

int idrnet_async_connect(int fd, int family, const char *host, int port) {
  struct sockaddr_storage ss;
  int len = make_addr(family, host, port, &ss);
  if (len < 0) {
    return len;
  }
  if (connect(fd, (struct sockaddr *)&ss, (socklen_t)len) == 0) {
    return 0;
  }
  // (an interrupted connect goes on in the background)
  if (errno == EINTR) {
    return -EINPROGRESS;
  }
  return neg_errno();
}

int idrnet_async_connect_result(int fd) {
  int err = 0;
  socklen_t len = sizeof err;
  if (getsockopt(fd, SOL_SOCKET, SO_ERROR, &err, &len) != 0) {
    return neg_errno();
  }
  if (err != 0) {
    return -err;
  }
  // No error: connected, unless it is still going on.
  struct sockaddr_storage ss;
  socklen_t sl = sizeof ss;
  if (getpeername(fd, (struct sockaddr *)&ss, &sl) != 0) {
    return errno == ENOTCONN ? -EINPROGRESS : neg_errno();
  }
  return 0;
}

static int accept_into(int fd, struct sockaddr *addr, socklen_t *len) {
  for (;;) {
#if defined(__linux__) || defined(__FreeBSD__) || defined(__NetBSD__) ||      \
    defined(__OpenBSD__) || defined(__DragonFly__)
    int c = accept4(fd, addr, len, SOCK_NONBLOCK | SOCK_CLOEXEC);
    int flags_set = 1;
#else
    int c = accept(fd, addr, len);
    int flags_set = 0;
#endif
    if (c >= 0) {
      if (prepare(c, flags_set) != 0) {
        int e = neg_errno();
        close(c);
        return e;
      }
      return c;
    }
    if (errno != EINTR && errno != ECONNABORTED) {
      return neg_errno();
    }
  }
}

int idrnet_async_accept(int fd) { return accept_into(fd, NULL, NULL); }

int idrnet_async_accept_addr(int fd, char *addr) {
  memset(addr, 0, IDRNET_ASYNC_ADDR_SIZE);
  socklen_t len = IDRNET_ASYNC_ADDR_SIZE;
  return accept_into(fd, (struct sockaddr *)addr, &len);
}

int idrnet_async_recv(int fd, char *buf, int offset, int len) {
  for (;;) {
    ssize_t n = recv(fd, buf + offset, (size_t)len, 0);
    if (n >= 0) {
      return (int)n;
    }
    if (errno != EINTR) {
      return neg_errno();
    }
  }
}

int idrnet_async_send(int fd, const char *buf, int offset, int len) {
  for (;;) {
    ssize_t n = send(fd, buf + offset, (size_t)len, MSG_NOSIGNAL);
    if (n >= 0) {
      return (int)n;
    }
    if (errno != EINTR) {
      return neg_errno();
    }
  }
}

int idrnet_async_send2(int fd, const char *buf1, int off1, int len1,
                       const char *buf2, int off2, int len2) {
  struct iovec iov[2];
  iov[0].iov_base = (void *)(buf1 + off1);
  iov[0].iov_len = (size_t)len1;
  iov[1].iov_base = (void *)(buf2 + off2);
  iov[1].iov_len = (size_t)len2;
  struct msghdr msg;
  memset(&msg, 0, sizeof msg);
  msg.msg_iov = iov;
  msg.msg_iovlen = 2;
  for (;;) {
    ssize_t n = sendmsg(fd, &msg, MSG_NOSIGNAL);
    if (n >= 0) {
      return (int)n;
    }
    if (errno != EINTR) {
      return neg_errno();
    }
  }
}

int idrnet_async_recvfrom(int fd, char *buf, int offset, int len, char *addr) {
  memset(addr, 0, IDRNET_ASYNC_ADDR_SIZE);
  for (;;) {
    socklen_t al = IDRNET_ASYNC_ADDR_SIZE;
    ssize_t n = recvfrom(fd, buf + offset, (size_t)len, 0,
                         (struct sockaddr *)addr, &al);
    if (n >= 0) {
      return (int)n;
    }
    if (errno != EINTR) {
      return neg_errno();
    }
  }
}

int idrnet_async_sendto(int fd, const char *buf, int offset, int len,
                        int family, const char *host, int port) {
  struct sockaddr_storage ss;
  int al = make_addr(family, host, port, &ss);
  if (al < 0) {
    return al;
  }
  for (;;) {
    ssize_t n = sendto(fd, buf + offset, (size_t)len, MSG_NOSIGNAL,
                       (struct sockaddr *)&ss, (socklen_t)al);
    if (n >= 0) {
      return (int)n;
    }
    if (errno != EINTR) {
      return neg_errno();
    }
  }
}

int idrnet_async_shutdown(int fd, int how) {
  int h = how == 0 ? SHUT_RD : how == 1 ? SHUT_WR : SHUT_RDWR;
  if (shutdown(fd, h) != 0) {
    return neg_errno();
  }
  return 0;
}

// The level and name of an option code, or 0 when the system lacks it.
static int option_of(int option, int *level, int *name) {
  switch (option) {
  case 1:
    *level = SOL_SOCKET;
    *name = SO_REUSEADDR;
    return 1;
  case 2:
#ifdef SO_REUSEPORT
    *level = SOL_SOCKET;
    *name = SO_REUSEPORT;
    return 1;
#else
    return 0;
#endif
  case 3:
    *level = IPPROTO_TCP;
    *name = TCP_NODELAY;
    return 1;
  case 4:
    *level = SOL_SOCKET;
    *name = SO_KEEPALIVE;
    return 1;
  case 5:
    *level = SOL_SOCKET;
    *name = SO_RCVBUF;
    return 1;
  case 6:
    *level = SOL_SOCKET;
    *name = SO_SNDBUF;
    return 1;
  case 7:
    *level = SOL_SOCKET;
    *name = SO_LINGER;
    return 1;
  case 8:
    *level = IPPROTO_IPV6;
    *name = IPV6_V6ONLY;
    return 1;
  case 9:
    *level = SOL_SOCKET;
    *name = SO_BROADCAST;
    return 1;
  default:
    return 0;
  }
}

int idrnet_async_setopt(int fd, int option, int value) {
  int level, name;
  if (!option_of(option, &level, &name)) {
    return -ENOPROTOOPT;
  }
  int r;
  if (name == SO_LINGER && level == SOL_SOCKET) {
    struct linger l;
    l.l_onoff = value >= 0;
    l.l_linger = value >= 0 ? value : 0;
    r = setsockopt(fd, level, name, &l, sizeof l);
  } else {
    r = setsockopt(fd, level, name, &value, sizeof value);
  }
  return r == 0 ? 0 : neg_errno();
}

int idrnet_async_getopt(int fd, int option) {
  int level, name;
  if (!option_of(option, &level, &name)) {
    return -ENOPROTOOPT;
  }
  if (name == SO_LINGER && level == SOL_SOCKET) {
    struct linger l;
    socklen_t len = sizeof l;
    memset(&l, 0, sizeof l);
    if (getsockopt(fd, level, name, &l, &len) != 0) {
      return neg_errno();
    }
    return l.l_onoff ? 1 + l.l_linger : 0;
  }
  int value = 0;
  socklen_t len = sizeof value;
  if (getsockopt(fd, level, name, &value, &len) != 0) {
    return neg_errno();
  }
  // (a boolean option may be any non-zero value)
  if (option != 5 && option != 6) {
    value = value != 0;
  }
  return value;
}

int idrnet_async_getname(int fd, int peer, char *addr) {
  memset(addr, 0, IDRNET_ASYNC_ADDR_SIZE);
  socklen_t len = IDRNET_ASYNC_ADDR_SIZE;
  int r = peer ? getpeername(fd, (struct sockaddr *)addr, &len)
               : getsockname(fd, (struct sockaddr *)addr, &len);
  return r == 0 ? 0 : neg_errno();
}

int idrnet_async_addr_family(const char *addr) {
  switch (((const struct sockaddr *)addr)->sa_family) {
  case AF_UNIX:
    return 1;
  case AF_INET:
    return 4;
  case AF_INET6:
    return 6;
  default:
    return 0;
  }
}

int idrnet_async_addr_port(const char *addr) {
  switch (((const struct sockaddr *)addr)->sa_family) {
  case AF_INET:
    return ntohs(((const struct sockaddr_in *)addr)->sin_port);
  case AF_INET6:
    return ntohs(((const struct sockaddr_in6 *)addr)->sin6_port);
  default:
    return 0;
  }
}

const char *idrnet_async_addr_host(const char *addr) {
  static _Thread_local char text[IDRNET_ASYNC_ADDR_SIZE];
  text[0] = '\0';
  switch (((const struct sockaddr *)addr)->sa_family) {
  case AF_UNIX: {
    const struct sockaddr_un *un = (const struct sockaddr_un *)addr;
    size_t n = strnlen(un->sun_path, sizeof un->sun_path);
    memcpy(text, un->sun_path, n);
    text[n] = '\0';
    break;
  }
  case AF_INET:
    if (!inet_ntop(AF_INET, &((const struct sockaddr_in *)addr)->sin_addr,
                   text, sizeof text)) {
      text[0] = '\0';
    }
    break;
  case AF_INET6: {
    const struct sockaddr_in6 *in6 = (const struct sockaddr_in6 *)addr;
    if (!inet_ntop(AF_INET6, &in6->sin6_addr, text, sizeof text)) {
      text[0] = '\0';
    } else if (in6->sin6_scope_id != 0) {
      size_t n = strlen(text);
      snprintf(text + n, sizeof text - n, "%%%u",
               (unsigned)in6->sin6_scope_id);
    }
    break;
  }
  default:
    break;
  }
  return text;
}

int idrnet_async_make_blocking(int fd) {
  ForgetFn forget = forget_fn();
  if (forget) {
    forget(fd);
  }
  int fl = fcntl(fd, F_GETFL);
  if (fl < 0) {
    return neg_errno();
  }
  if ((fl & O_NONBLOCK) && fcntl(fd, F_SETFL, fl & ~O_NONBLOCK) < 0) {
    return neg_errno();
  }
  return 0;
}

const char *idrnet_async_strerror(int err) {
  // (glibc and the BSDs give a constant string for the known codes)
  return strerror(err);
}

// ---------------------------------------------------------------------------
// Name resolution
// ---------------------------------------------------------------------------

typedef struct {
  int family; // 4 or 6
  int port;
  char host[INET6_ADDRSTRLEN + 16];
} ResolvedAddr;

typedef struct {
  // in
  char *host;
  int port;
  int family;
  // out
  int status;  // 0 or an EAI_ code
  int sys_err; // errno, for EAI_SYSTEM
  char message[160];
  int count;
  ResolvedAddr *addrs;
} Resolve;

void *idrnet_async_strdup(const char *s) { return strdup(s); }

// Runs on a thread of the pool on RefC: touches nothing of Idris.
static void run_resolve(void *arg) {
  Resolve *r = (Resolve *)arg;
  struct addrinfo hints;
  memset(&hints, 0, sizeof hints);
  hints.ai_family = r->family == 4   ? AF_INET
                    : r->family == 6 ? AF_INET6
                                     : AF_UNSPEC;
  // (one entry per address, not one per protocol)
  hints.ai_socktype = SOCK_STREAM;
  hints.ai_flags = AI_NUMERICSERV;
#ifdef AI_ADDRCONFIG
  if (r->family == 0) {
    hints.ai_flags |= AI_ADDRCONFIG;
  }
#endif
  char service[16];
  snprintf(service, sizeof service, "%d", r->port);
  struct addrinfo *res = NULL;
  int status = getaddrinfo(r->host, service, &hints, &res);
#ifdef AI_ADDRCONFIG
  // AI_ADDRCONFIG gives nothing for "localhost" on a machine whose only
  // addresses are loopback ones on some systems: try again without it.
  if ((status == EAI_NONAME
#ifdef EAI_ADDRFAMILY
       || status == EAI_ADDRFAMILY
#endif
       ) &&
      r->family == 0) {
    hints.ai_flags &= ~AI_ADDRCONFIG;
    status = getaddrinfo(r->host, service, &hints, &res);
  }
#endif
  r->status = status;
  if (status != 0) {
    r->sys_err = status == EAI_SYSTEM ? errno : 0;
    if (status == EAI_SYSTEM) {
      snprintf(r->message, sizeof r->message, "%s", strerror(r->sys_err));
    } else {
      snprintf(r->message, sizeof r->message, "%s", gai_strerror(status));
    }
    return;
  }
  int n = 0;
  for (struct addrinfo *a = res; a; a = a->ai_next) {
    if (a->ai_family == AF_INET || a->ai_family == AF_INET6) {
      n++;
    }
  }
  r->addrs = n ? calloc((size_t)n, sizeof(ResolvedAddr)) : NULL;
  if (n && !r->addrs) {
    r->status = EAI_MEMORY;
    snprintf(r->message, sizeof r->message, "%s", gai_strerror(EAI_MEMORY));
    freeaddrinfo(res);
    return;
  }
  int i = 0;
  for (struct addrinfo *a = res; a; a = a->ai_next) {
    if (a->ai_family != AF_INET && a->ai_family != AF_INET6) {
      continue;
    }
    ResolvedAddr *out = &r->addrs[i++];
    out->family = a->ai_family == AF_INET ? 4 : 6;
    out->port = idrnet_async_addr_port((const char *)a->ai_addr);
    // (the same text as for an accepted peer, with its scope)
    struct sockaddr_storage ss;
    memset(&ss, 0, sizeof ss);
    memcpy(&ss, a->ai_addr,
           a->ai_addrlen < sizeof ss ? a->ai_addrlen : sizeof ss);
    const char *text = idrnet_async_addr_host((const char *)&ss);
    snprintf(out->host, sizeof out->host, "%s", text);
  }
  r->count = i;
  freeaddrinfo(res);
}

void *idrnet_async_resolve(void *host, int port, int family) {
  Resolve *r = calloc(1, sizeof *r);
  if (!r) {
    free(host);
    return NULL;
  }
  r->host = (char *)host;
  r->port = port;
  r->family = family;
  if (!host) {
    r->status = EAI_MEMORY;
    snprintf(r->message, sizeof r->message, "%s", gai_strerror(EAI_MEMORY));
    return r;
  }
  // (a numeric address needs no lookup: not worth a trip to the pool)
  unsigned char probe[sizeof(struct in6_addr)];
  int numeric = inet_pton(AF_INET, r->host, probe) == 1 ||
                inet_pton(AF_INET6, r->host, probe) == 1;
  BlockingCallFn call = numeric ? NULL : blocking_call_fn();
  if (call) {
    call(run_resolve, r);
  } else {
    run_resolve(r);
  }
  free(r->host);
  r->host = NULL;
  return r;
}

int idrnet_async_resolve_status(void *res) {
  return res ? ((Resolve *)res)->status : EAI_MEMORY;
}

const char *idrnet_async_resolve_error(void *res) {
  return res ? ((Resolve *)res)->message : "out of memory";
}

int idrnet_async_resolve_count(void *res) {
  return res ? ((Resolve *)res)->count : 0;
}

int idrnet_async_resolve_family(void *res, int i) {
  Resolve *r = (Resolve *)res;
  return r && i >= 0 && i < r->count ? r->addrs[i].family : 0;
}

int idrnet_async_resolve_port(void *res, int i) {
  Resolve *r = (Resolve *)res;
  return r && i >= 0 && i < r->count ? r->addrs[i].port : 0;
}

const char *idrnet_async_resolve_host(void *res, int i) {
  Resolve *r = (Resolve *)res;
  return r && i >= 0 && i < r->count ? r->addrs[i].host : "";
}

void idrnet_async_resolve_free(void *res) {
  Resolve *r = (Resolve *)res;
  if (r) {
    free(r->addrs);
    free(r);
  }
}

#endif /* not _WIN32 */

int idrnet_async_EINPROGRESS(void) { return EINPROGRESS; }
int idrnet_async_ETIMEDOUT(void) { return ETIMEDOUT; }
int idrnet_async_EPIPE(void) { return EPIPE; }
int idrnet_async_ECONNRESET(void) { return ECONNRESET; }
int idrnet_async_ECONNREFUSED(void) { return ECONNREFUSED; }
int idrnet_async_ENOTCONN(void) { return ENOTCONN; }
