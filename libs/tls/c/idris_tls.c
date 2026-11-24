// TLS connections over non-blocking sockets, with OpenSSL 3: see
// idris_tls.h.

#include "idris_tls.h"

#include <arpa/inet.h>
#include <errno.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <sys/socket.h>
#include <sys/types.h>

#include <openssl/bio.h>
#include <openssl/err.h>
#include <openssl/pem.h>
#include <openssl/ssl.h>
#include <openssl/x509.h>
#include <openssl/x509v3.h>

#if OPENSSL_VERSION_MAJOR < 3
#error "the tls library needs OpenSSL 3 or later"
#endif

#ifndef MSG_NOSIGNAL
#define MSG_NOSIGNAL 0 // macOS: the sockets of the network library have SO_NOSIGPIPE
#endif

#define ERR_SIZE 256

// The strings returned to Idris, which copies them at once.
static _Thread_local char out_buf[4096];

// ---------------------------------------------------------------------------
// Errors

// Write "what: reason" into dst, with the reason of the first error in the
// queue of OpenSSL (of this OS thread), and empty the queue.
static void set_error(char *dst, const char *what) {
  unsigned long e = ERR_peek_error();
  const char *reason = NULL;
  char code[128];
  if (e != 0 && ERR_SYSTEM_ERROR(e)) {
    reason = strerror(ERR_GET_REASON(e));
  } else if (e != 0) {
    reason = ERR_reason_error_string(e);
  }
  if (e != 0 && reason == NULL) {
    ERR_error_string_n(e, code, sizeof code);
    reason = code;
  }
  if (reason != NULL && what != NULL && what[0] != '\0') {
    snprintf(dst, ERR_SIZE, "%s: %s", what, reason);
  } else if (reason != NULL) {
    snprintf(dst, ERR_SIZE, "%s", reason);
  } else {
    snprintf(dst, ERR_SIZE, "%s", what != NULL ? what : "unknown error");
  }
  ERR_clear_error();
}

const char *idris_tls_code_message(int code) {
  switch (code) {
  case IDRIS_TLS_WANT_READ: return "the TLS connection needs to read";
  case IDRIS_TLS_WANT_WRITE: return "the TLS connection needs to write";
  case IDRIS_TLS_CLOSED: return "the peer closed the TLS session";
  case IDRIS_TLS_UNEXPECTED_EOF: return "the connection ended without a TLS close_notify";
  case IDRIS_TLS_PROTOCOL_ERROR: return "TLS error";
  case IDRIS_TLS_VERIFY_ERROR: return "certificate verification failed";
  case IDRIS_TLS_CONFIG_ERROR: return "TLS configuration error";
  default: return "unknown TLS result";
  }
}

const char *idris_tls_openssl_version(void) {
  return OpenSSL_version(OPENSSL_VERSION);
}

// ---------------------------------------------------------------------------
// Contexts

typedef struct sni_cert {
  char *name;
  SSL_CTX *ctx;
  struct sni_cert *next;
} sni_cert;

typedef struct {
  SSL_CTX *ctx;
  int is_server;
  int min_version;
  // ALPN of a server: its protocols in the wire format, by preference.
  unsigned char *alpn;
  unsigned int alpn_len;
  int alpn_required;
  sni_cert *sni;
  char err[ERR_SIZE];
} tls_ctx;

// The wire format of ALPN (each name after its length in one byte) of a
// list separated by commas.  NULL for a name that is empty or too long.
static unsigned char *alpn_wire(const char *protocols, unsigned int *len) {
  size_t n = strlen(protocols);
  unsigned char *w = malloc(n + 1);
  if (w == NULL) return NULL;
  size_t at = 0;
  const char *p = protocols;
  for (;;) {
    const char *end = strchr(p, ',');
    size_t l = end != NULL ? (size_t)(end - p) : strlen(p);
    if (l == 0 || l > 255) {
      free(w);
      return NULL;
    }
    w[at++] = (unsigned char)l;
    memcpy(w + at, p, l);
    at += l;
    if (end == NULL) break;
    p = end + 1;
  }
  *len = (unsigned int)at;
  return w;
}

// Select the first protocol of the server that the client offers.
static int alpn_select(SSL *ssl, const unsigned char **out, unsigned char *outlen,
                       const unsigned char *in, unsigned int inlen, void *arg) {
  (void)ssl;
  tls_ctx *c = arg;
  if (c->alpn == NULL) return SSL_TLSEXT_ERR_NOACK;
  for (unsigned int i = 0; i < c->alpn_len; i += 1u + c->alpn[i]) {
    unsigned int l = c->alpn[i];
    for (unsigned int j = 0; j < inlen; j += 1u + in[j]) {
      if (in[j] == l && j + 1 + l <= inlen && memcmp(in + j + 1, c->alpn + i + 1, l) == 0) {
        *out = in + j + 1;
        *outlen = (unsigned char)l;
        return SSL_TLSEXT_ERR_OK;
      }
    }
  }
  return c->alpn_required ? SSL_TLSEXT_ERR_ALERT_FATAL : SSL_TLSEXT_ERR_NOACK;
}

// Does the SNI name match the name of a certificate (`*.domain` for one
// more label)?
static int sni_match(const char *pattern, const char *name) {
  if (pattern[0] == '*' && pattern[1] == '.') {
    const char *dot = strchr(name, '.');
    return dot != NULL && dot != name && strcasecmp(dot, pattern + 1) == 0;
  }
  return strcasecmp(pattern, name) == 0;
}

// A server: take the certificate of the name the client asked for.
static int servername_cb(SSL *ssl, int *alert, void *arg) {
  (void)alert;
  tls_ctx *c = arg;
  const char *name = SSL_get_servername(ssl, TLSEXT_NAMETYPE_host_name);
  if (name == NULL) return SSL_TLSEXT_ERR_OK;
  for (sni_cert *s = c->sni; s != NULL; s = s->next) {
    if (sni_match(s->name, name)) {
      SSL_set_SSL_CTX(ssl, s->ctx);
      break;
    }
  }
  return SSL_TLSEXT_ERR_OK;
}

static SSL_CTX *new_ssl_ctx(tls_ctx *c) {
  SSL_CTX *ctx = SSL_CTX_new(c->is_server ? TLS_server_method() : TLS_client_method());
  if (ctx == NULL) return NULL;
  SSL_CTX_set_min_proto_version(ctx, c->min_version == 13 ? TLS1_3_VERSION : TLS1_2_VERSION);
  SSL_CTX_set_options(ctx, SSL_OP_NO_RENEGOTIATION);
  // Partial writes: SSL_write returns once a record is out, so that the
  // caller knows how much of its bytes went.  Moving write buffer: after a
  // write that wanted to wait, the retry gives the same bytes, maybe at
  // another address (a bytevector of Chez may move with the collector;
  // a Buffer of RefC does not).
  SSL_CTX_set_mode(ctx, SSL_MODE_ENABLE_PARTIAL_WRITE | SSL_MODE_ACCEPT_MOVING_WRITE_BUFFER);
  if (c->is_server) {
    static const unsigned char sid[] = "idris2i-1-tls";
    SSL_CTX_set_session_id_context(ctx, sid, sizeof sid - 1);
    SSL_CTX_set_alpn_select_cb(ctx, alpn_select, c);
  }
  return ctx;
}

void *idris_tls_ctx_new(int is_server, int min_version) {
  tls_ctx *c = calloc(1, sizeof *c);
  if (c == NULL) return NULL;
  c->is_server = is_server;
  c->min_version = min_version;
  c->ctx = new_ssl_ctx(c);
  ERR_clear_error();
  if (c->ctx == NULL) {
    free(c);
    return NULL;
  }
  if (is_server) {
    SSL_CTX_set_tlsext_servername_callback(c->ctx, servername_cb);
    SSL_CTX_set_tlsext_servername_arg(c->ctx, c);
  } else {
    SSL_CTX_set_verify(c->ctx, SSL_VERIFY_PEER, NULL);
  }
  return c;
}

void idris_tls_ctx_free(void *p) {
  tls_ctx *c = p;
  if (c == NULL) return;
  SSL_CTX_free(c->ctx);
  for (sni_cert *s = c->sni; s != NULL;) {
    sni_cert *next = s->next;
    SSL_CTX_free(s->ctx);
    free(s->name);
    free(s);
    s = next;
  }
  free(c->alpn);
  free(c);
}

const char *idris_tls_ctx_error(void *p) {
  tls_ctx *c = p;
  return c->err;
}

int idris_tls_ctx_use_system_trust(void *p) {
  tls_ctx *c = p;
  ERR_clear_error();
  if (SSL_CTX_set_default_verify_paths(c->ctx) != 1) {
    set_error(c->err, "cannot use the trusted certificates of the system");
    return IDRIS_TLS_CONFIG_ERROR;
  }
  ERR_clear_error();
  return 0;
}

int idris_tls_ctx_trust(void *p, const char *ca_file, const char *ca_dir) {
  tls_ctx *c = p;
  const char *f = ca_file[0] != '\0' ? ca_file : NULL;
  const char *d = ca_dir[0] != '\0' ? ca_dir : NULL;
  if (f == NULL && d == NULL) return 0;
  ERR_clear_error();
  if (SSL_CTX_load_verify_locations(c->ctx, f, d) != 1) {
    char what[ERR_SIZE];
    snprintf(what, sizeof what, "cannot load the trusted certificates of %s", f != NULL ? f : d);
    set_error(c->err, what);
    return IDRIS_TLS_CONFIG_ERROR;
  }
  if (c->is_server && f != NULL) {
    STACK_OF(X509_NAME) *names = SSL_load_client_CA_file(f);
    if (names != NULL) SSL_CTX_set_client_CA_list(c->ctx, names);
  }
  ERR_clear_error();
  return 0;
}

int idris_tls_ctx_trust_pem(void *p, const char *pem) {
  tls_ctx *c = p;
  ERR_clear_error();
  BIO *b = BIO_new_mem_buf(pem, -1);
  if (b == NULL) {
    set_error(c->err, "out of memory");
    return IDRIS_TLS_CONFIG_ERROR;
  }
  X509_STORE *store = SSL_CTX_get_cert_store(c->ctx);
  int count = 0;
  X509 *x;
  while ((x = PEM_read_bio_X509(b, NULL, NULL, NULL)) != NULL) {
    int ok = X509_STORE_add_cert(store, x);
    if (ok && c->is_server) SSL_CTX_add_client_CA(c->ctx, x);
    X509_free(x);
    if (!ok) {
      BIO_free(b);
      set_error(c->err, "cannot trust a certificate");
      return IDRIS_TLS_CONFIG_ERROR;
    }
    count++;
  }
  BIO_free(b);
  if (count == 0) {
    set_error(c->err, "no certificate in the PEM text of the trusted certificates");
    return IDRIS_TLS_CONFIG_ERROR;
  }
  ERR_clear_error(); // (the end of the text: no start line)
  return 0;
}

int idris_tls_ctx_set_verify(void *p, int mode) {
  tls_ctx *c = p;
  int m = mode == 0 ? SSL_VERIFY_NONE
        : mode == 1 ? SSL_VERIFY_PEER
        : SSL_VERIFY_PEER | SSL_VERIFY_FAIL_IF_NO_PEER_CERT;
  SSL_CTX_set_verify(c->ctx, m, NULL);
  return 0;
}

// The chain and key of PEM text.
static int use_cert_pem(SSL_CTX *ctx, const char *chain, const char *key, char *err) {
  BIO *b = BIO_new_mem_buf(chain, -1);
  if (b == NULL) {
    set_error(err, "out of memory");
    return IDRIS_TLS_CONFIG_ERROR;
  }
  X509 *leaf = PEM_read_bio_X509_AUX(b, NULL, NULL, NULL);
  if (leaf == NULL || SSL_CTX_use_certificate(ctx, leaf) != 1) {
    X509_free(leaf);
    BIO_free(b);
    set_error(err, "cannot use the certificate of the PEM text");
    return IDRIS_TLS_CONFIG_ERROR;
  }
  X509_free(leaf);
  SSL_CTX_clear_chain_certs(ctx);
  X509 *x;
  while ((x = PEM_read_bio_X509(b, NULL, NULL, NULL)) != NULL) {
    if (SSL_CTX_add0_chain_cert(ctx, x) != 1) {
      X509_free(x);
      BIO_free(b);
      set_error(err, "cannot use a certificate of the chain of the PEM text");
      return IDRIS_TLS_CONFIG_ERROR;
    }
  }
  BIO_free(b);
  ERR_clear_error(); // (the end of the text: no start line)
  b = BIO_new_mem_buf(key, -1);
  EVP_PKEY *k = b != NULL ? PEM_read_bio_PrivateKey(b, NULL, NULL, NULL) : NULL;
  BIO_free(b);
  if (k == NULL || SSL_CTX_use_PrivateKey(ctx, k) != 1) {
    EVP_PKEY_free(k);
    set_error(err, "cannot use the private key of the PEM text");
    return IDRIS_TLS_CONFIG_ERROR;
  }
  EVP_PKEY_free(k);
  return 0;
}

static int use_cert_file(SSL_CTX *ctx, const char *chain, const char *key, char *err) {
  char what[ERR_SIZE];
  if (SSL_CTX_use_certificate_chain_file(ctx, chain) != 1) {
    snprintf(what, sizeof what, "cannot use the certificate chain of %s", chain);
    set_error(err, what);
    return IDRIS_TLS_CONFIG_ERROR;
  }
  if (SSL_CTX_use_PrivateKey_file(ctx, key, SSL_FILETYPE_PEM) != 1) {
    snprintf(what, sizeof what, "cannot use the private key of %s", key);
    set_error(err, what);
    return IDRIS_TLS_CONFIG_ERROR;
  }
  return 0;
}

static int use_cert(SSL_CTX *ctx, const char *chain, const char *key, int is_pem_text,
                    char *err) {
  ERR_clear_error();
  int r = is_pem_text ? use_cert_pem(ctx, chain, key, err)
                      : use_cert_file(ctx, chain, key, err);
  if (r != 0) return r;
  if (SSL_CTX_check_private_key(ctx) != 1) {
    ERR_clear_error();
    set_error(err, "the private key does not match the certificate");
    return IDRIS_TLS_CONFIG_ERROR;
  }
  ERR_clear_error();
  return 0;
}

int idris_tls_ctx_use_cert(void *p, const char *chain, const char *key, int is_pem_text) {
  tls_ctx *c = p;
  return use_cert(c->ctx, chain, key, is_pem_text, c->err);
}

int idris_tls_ctx_add_sni_cert(void *p, const char *name, const char *chain,
                               const char *key, int is_pem_text) {
  tls_ctx *c = p;
  if (!c->is_server) {
    snprintf(c->err, ERR_SIZE, "a certificate for an SNI name is for a server");
    return IDRIS_TLS_CONFIG_ERROR;
  }
  sni_cert *s = calloc(1, sizeof *s);
  if (s != NULL) {
    s->name = strdup(name);
    s->ctx = new_ssl_ctx(c);
  }
  if (s == NULL || s->name == NULL || s->ctx == NULL) {
    if (s != NULL) {
      SSL_CTX_free(s->ctx);
      free(s->name);
      free(s);
    }
    set_error(c->err, "out of memory");
    return IDRIS_TLS_CONFIG_ERROR;
  }
  // The connection switches to this context when the name matches: it
  // verifies client certificates as the main one does (the verification
  // of a connection uses the trusted certificates of its current context).
  SSL_CTX_set1_cert_store(s->ctx, SSL_CTX_get_cert_store(c->ctx));
  SSL_CTX_set_verify(s->ctx, SSL_CTX_get_verify_mode(c->ctx), NULL);
  STACK_OF(X509_NAME) *cas = SSL_CTX_get_client_CA_list(c->ctx);
  if (cas != NULL) {
    STACK_OF(X509_NAME) *copy = SSL_dup_CA_list(cas);
    if (copy != NULL) SSL_CTX_set_client_CA_list(s->ctx, copy);
  }
  int r = use_cert(s->ctx, chain, key, is_pem_text, c->err);
  if (r != 0) {
    SSL_CTX_free(s->ctx);
    free(s->name);
    free(s);
    return r;
  }
  s->next = c->sni;
  c->sni = s;
  return 0;
}

int idris_tls_ctx_set_alpn(void *p, const char *protocols, int required) {
  tls_ctx *c = p;
  unsigned int len = 0;
  unsigned char *w = alpn_wire(protocols, &len);
  if (w == NULL) {
    snprintf(c->err, ERR_SIZE, "a name of an ALPN protocol is empty or longer than 255 bytes");
    return IDRIS_TLS_CONFIG_ERROR;
  }
  if (c->is_server) {
    free(c->alpn);
    c->alpn = w;
    c->alpn_len = len;
    c->alpn_required = required;
    return 0;
  }
  ERR_clear_error();
  int r = SSL_CTX_set_alpn_protos(c->ctx, w, len); // (0 on success)
  free(w);
  if (r != 0) {
    set_error(c->err, "cannot set the ALPN protocols");
    return IDRIS_TLS_CONFIG_ERROR;
  }
  return 0;
}

// ---------------------------------------------------------------------------
// The socket BIO: recv(2) and send(2) with MSG_NOSIGNAL, so that a write to
// a peer that is gone fails with EPIPE instead of raising SIGPIPE (the BIO
// of OpenSSL uses write(2)).  The errno of a failure is kept in the
// connection, for SSL_ERROR_SYSCALL.

typedef struct {
  pthread_mutex_t lock;
  SSL *ssl;
  int fd;
  int fatal;      // an error ended the session: no close_notify
  int io_errno;   // the errno of the last failed recv or send
  int verify;     // the X509_V_* result of a failed verification
  int released;   // idris_tls_conn_release was called
  char err[ERR_SIZE];
} tls_conn;

static int bio_write(BIO *b, const char *buf, int len) {
  tls_conn *c = BIO_get_data(b);
  BIO_clear_retry_flags(b);
  ssize_t n;
  do {
    n = send(c->fd, buf, (size_t)len, MSG_NOSIGNAL);
  } while (n < 0 && errno == EINTR);
  if (n < 0) {
    c->io_errno = errno;
    if (errno == EAGAIN || errno == EWOULDBLOCK) BIO_set_retry_write(b);
    return -1;
  }
  return (int)n;
}

static int bio_read(BIO *b, char *buf, int len) {
  tls_conn *c = BIO_get_data(b);
  BIO_clear_retry_flags(b);
  ssize_t n;
  do {
    n = recv(c->fd, buf, (size_t)len, 0);
  } while (n < 0 && errno == EINTR);
  if (n < 0) {
    c->io_errno = errno;
    if (errno == EAGAIN || errno == EWOULDBLOCK) BIO_set_retry_read(b);
    return -1;
  }
  if (n == 0) BIO_set_flags(b, BIO_FLAGS_IN_EOF);
  return (int)n;
}

static int bio_puts(BIO *b, const char *s) {
  return bio_write(b, s, (int)strlen(s));
}

static long bio_ctrl(BIO *b, int cmd, long num, void *ptr) {
  (void)num;
  tls_conn *c = BIO_get_data(b);
  switch (cmd) {
  case BIO_CTRL_FLUSH:
    return 1;
  case BIO_CTRL_EOF:
    return BIO_test_flags(b, BIO_FLAGS_IN_EOF) != 0;
  case BIO_C_GET_FD:
    if (c == NULL) return -1;
    if (ptr != NULL) *(int *)ptr = c->fd;
    return c->fd;
  default:
    return 0;
  }
}

static int bio_create(BIO *b) {
  BIO_set_init(b, 1);
  return 1;
}

static int bio_destroy(BIO *b) {
  (void)b;
  return 1;
}

// The method is made once, and never freed (OpenSSL keeps no reference to
// the methods that are not used any more).
static BIO_METHOD *sock_method;
static pthread_once_t sock_method_once = PTHREAD_ONCE_INIT;

static void make_sock_method(void) {
  BIO_METHOD *m = BIO_meth_new(BIO_get_new_index() | BIO_TYPE_SOURCE_SINK | BIO_TYPE_DESCRIPTOR,
                               "idris2i-1 non-blocking socket");
  if (m == NULL) return;
  BIO_meth_set_write(m, bio_write);
  BIO_meth_set_read(m, bio_read);
  BIO_meth_set_puts(m, bio_puts);
  BIO_meth_set_ctrl(m, bio_ctrl);
  BIO_meth_set_create(m, bio_create);
  BIO_meth_set_destroy(m, bio_destroy);
  sock_method = m;
}

// ---------------------------------------------------------------------------
// Connections

static int is_ip_address(const char *host) {
  unsigned char a[16];
  return inet_pton(AF_INET, host, a) == 1 || inet_pton(AF_INET6, host, a) == 1;
}

void *idris_tls_conn_new(void *p, int fd, const char *host, int verify_host) {
  tls_ctx *ctx = p;
  tls_conn *c = calloc(1, sizeof *c);
  if (c == NULL) return NULL;
  if (pthread_mutex_init(&c->lock, NULL) != 0) {
    free(c);
    return NULL;
  }
  c->fd = fd;
  ERR_clear_error();
  pthread_once(&sock_method_once, make_sock_method);
  BIO *bio = sock_method != NULL ? BIO_new(sock_method) : NULL;
  SSL *ssl = bio != NULL ? SSL_new(ctx->ctx) : NULL;
  if (ssl == NULL) {
    BIO_free(bio);
    set_error(c->err, "cannot make a TLS session");
    c->fatal = 1;
    return c;
  }
  BIO_set_data(bio, c);
  SSL_set_bio(ssl, bio, bio);
  c->ssl = ssl;
  if (ctx->is_server) {
    SSL_set_accept_state(ssl);
  } else {
    SSL_set_connect_state(ssl);
    if (host[0] != '\0') {
      int ip = is_ip_address(host);
      if (!ip && SSL_set_tlsext_host_name(ssl, host) != 1) {
        set_error(c->err, "cannot set the SNI name");
        goto fail;
      }
      if (verify_host) {
        SSL_set_hostflags(ssl, X509_CHECK_FLAG_NO_PARTIAL_WILDCARDS);
        if (SSL_set1_host(ssl, host) != 1) {
          set_error(c->err, "cannot set the name to verify");
          goto fail;
        }
      }
    }
  }
  ERR_clear_error();
  return c;
fail:
  SSL_free(ssl);
  c->ssl = NULL;
  c->fatal = 1;
  return c;
}

int idris_tls_conn_status(void *p) {
  tls_conn *c = p;
  return c->ssl != NULL ? 0 : IDRIS_TLS_CONFIG_ERROR;
}

// The result of an OpenSSL call that failed (ret is what it returned).
static int failed(tls_conn *c, int ret) {
  int e = SSL_get_error(c->ssl, ret);
  int r;
  switch (e) {
  case SSL_ERROR_WANT_READ:
    r = IDRIS_TLS_WANT_READ;
    break;
  case SSL_ERROR_WANT_WRITE:
    r = IDRIS_TLS_WANT_WRITE;
    break;
  case SSL_ERROR_ZERO_RETURN:
    r = IDRIS_TLS_CLOSED;
    break;
  case SSL_ERROR_SYSCALL:
    c->fatal = 1;
    if (ERR_peek_error() != 0) {
      set_error(c->err, NULL);
      r = IDRIS_TLS_PROTOCOL_ERROR;
    } else if (c->io_errno != 0) {
      snprintf(c->err, ERR_SIZE, "%s", strerror(c->io_errno));
      r = -c->io_errno;
    } else {
      snprintf(c->err, ERR_SIZE, "the connection ended without a TLS close_notify");
      r = IDRIS_TLS_UNEXPECTED_EOF;
    }
    break;
  case SSL_ERROR_SSL: {
    c->fatal = 1;
    unsigned long err = ERR_peek_error();
    long v = SSL_get_verify_result(c->ssl);
    if (ERR_GET_LIB(err) == ERR_LIB_SSL && ERR_GET_REASON(err) == SSL_R_UNEXPECTED_EOF_WHILE_READING) {
      snprintf(c->err, ERR_SIZE, "the connection ended without a TLS close_notify");
      r = IDRIS_TLS_UNEXPECTED_EOF;
    } else if (ERR_GET_LIB(err) == ERR_LIB_SSL
               && ERR_GET_REASON(err) == SSL_R_CERTIFICATE_VERIFY_FAILED && v != X509_V_OK) {
      c->verify = (int)v;
      snprintf(c->err, ERR_SIZE, "certificate verify failed: %s",
               X509_verify_cert_error_string(v));
      r = IDRIS_TLS_VERIFY_ERROR;
    } else {
      set_error(c->err, NULL);
      r = IDRIS_TLS_PROTOCOL_ERROR;
    }
    break;
  }
  default:
    c->fatal = 1;
    snprintf(c->err, ERR_SIZE, "unexpected state of OpenSSL (SSL_get_error %d)", e);
    r = IDRIS_TLS_PROTOCOL_ERROR;
    break;
  }
  ERR_clear_error();
  return r;
}

// Take the lock and get ready for a call: 0, or -EBADF when the session was
// released.
static int begin(tls_conn *c) {
  pthread_mutex_lock(&c->lock);
  if (c->ssl == NULL) {
    pthread_mutex_unlock(&c->lock);
    return -EBADF;
  }
  ERR_clear_error();
  c->io_errno = 0;
  return 0;
}

static int end(tls_conn *c, int r) {
  pthread_mutex_unlock(&c->lock);
  return r;
}

int idris_tls_handshake(void *p) {
  tls_conn *c = p;
  int r = begin(c);
  if (r != 0) return r;
  int ret = SSL_do_handshake(c->ssl);
  return end(c, ret == 1 ? 0 : failed(c, ret));
}

int idris_tls_read(void *p, char *buf, int offset, int len) {
  tls_conn *c = p;
  if (len <= 0) return 0;
  int r = begin(c);
  if (r != 0) return r;
  size_t n = 0;
  int ret = SSL_read_ex(c->ssl, buf + offset, (size_t)len, &n);
  return end(c, ret == 1 ? (int)n : failed(c, ret));
}

int idris_tls_write(void *p, const char *buf, int offset, int len) {
  tls_conn *c = p;
  if (len <= 0) return 0;
  int r = begin(c);
  if (r != 0) return r;
  size_t n = 0;
  int ret = SSL_write_ex(c->ssl, buf + offset, (size_t)len, &n);
  return end(c, ret == 1 ? (int)n : failed(c, ret));
}

// Write two ranges: in one record when they fit in one (a head and a
// small body make one record, not two), from the first range otherwise.
#define RECORD_SIZE 16384

int idris_tls_write2(void *p, const char *buf1, int off1, int len1,
                     const char *buf2, int off2, int len2) {
  if (len1 <= 0) return idris_tls_write(p, buf2, off2, len2);
  if (len2 <= 0 || len1 + len2 > RECORD_SIZE) return idris_tls_write(p, buf1, off1, len1);
  tls_conn *c = p;
  int r = begin(c);
  if (r != 0) return r;
  char both[RECORD_SIZE];
  memcpy(both, buf1 + off1, (size_t)len1);
  memcpy(both + len1, buf2 + off2, (size_t)len2);
  size_t n = 0;
  int ret = SSL_write_ex(c->ssl, both, (size_t)(len1 + len2), &n);
  return end(c, ret == 1 ? (int)n : failed(c, ret));
}

int idris_tls_shutdown(void *p) {
  tls_conn *c = p;
  int r = begin(c);
  if (r != 0) return r;
  if (c->fatal || !SSL_is_init_finished(c->ssl)) return end(c, 0);
  int ret = SSL_shutdown(c->ssl);
  if (ret == 1) return end(c, 0);
  if (ret == 0) {
    ERR_clear_error();
    return end(c, 1);
  }
  r = failed(c, ret);
  // (the peer closed first, or went away: there is nothing more to wait for)
  return end(c, r == IDRIS_TLS_CLOSED ? 0 : r);
}

int idris_tls_conn_release(void *p) {
  tls_conn *c = p;
  int released = 0;
  pthread_mutex_lock(&c->lock);
  if (!c->released) {
    SSL_free(c->ssl);
    c->ssl = NULL;
    c->released = 1;
    released = 1;
  }
  pthread_mutex_unlock(&c->lock);
  return released;
}

void idris_tls_conn_free(void *p) {
  tls_conn *c = p;
  if (c == NULL) return;
  (void)idris_tls_conn_release(c);
  pthread_mutex_destroy(&c->lock);
  free(c);
}

const char *idris_tls_conn_error(void *p) {
  tls_conn *c = p;
  pthread_mutex_lock(&c->lock);
  snprintf(out_buf, sizeof out_buf, "%s", c->err);
  pthread_mutex_unlock(&c->lock);
  return out_buf;
}

int idris_tls_verify_result(void *p) {
  tls_conn *c = p;
  return c->verify;
}

const char *idris_tls_info(void *p, int what) {
  tls_conn *c = p;
  out_buf[0] = '\0';
  pthread_mutex_lock(&c->lock);
  if (c->ssl != NULL) {
    const char *s = NULL;
    switch (what) {
    case 0:
      s = SSL_is_init_finished(c->ssl) ? SSL_get_version(c->ssl) : NULL;
      break;
    case 1:
      s = SSL_get_cipher_name(c->ssl);
      if (s != NULL && strcmp(s, "(NONE)") == 0) s = NULL;
      break;
    case 2: {
      const unsigned char *data = NULL;
      unsigned int len = 0;
      SSL_get0_alpn_selected(c->ssl, &data, &len);
      if (data != NULL && len < sizeof out_buf) {
        memcpy(out_buf, data, len);
        out_buf[len] = '\0';
      }
      break;
    }
    case 3:
      s = SSL_get_servername(c->ssl, TLSEXT_NAMETYPE_host_name);
      break;
    case 4:
      s = SSL_get0_peer_certificate(c->ssl) != NULL ? "1" : NULL;
      break;
    default:
      break;
    }
    if (s != NULL) snprintf(out_buf, sizeof out_buf, "%s", s);
  }
  pthread_mutex_unlock(&c->lock);
  return out_buf;
}

// Copy what was printed into the BIO to out_buf.
static void bio_to_out(BIO *b) {
  char *data = NULL;
  long n = BIO_get_mem_data(b, &data);
  if (n < 0) n = 0;
  if ((size_t)n >= sizeof out_buf) n = sizeof out_buf - 1;
  if (n > 0) memcpy(out_buf, data, (size_t)n);
  out_buf[n] = '\0';
}

static void print_alt_names(BIO *b, X509 *x) {
  GENERAL_NAMES *names = X509_get_ext_d2i(x, NID_subject_alt_name, NULL, NULL);
  if (names == NULL) return;
  int first = 1;
  for (int i = 0; i < sk_GENERAL_NAME_num(names); i++) {
    GENERAL_NAME *g = sk_GENERAL_NAME_value(names, i);
    if (g->type == GEN_DNS) {
      BIO_printf(b, "%sDNS:%.*s", first ? "" : ",", ASN1_STRING_length(g->d.dNSName),
                 (const char *)ASN1_STRING_get0_data(g->d.dNSName));
      first = 0;
    } else if (g->type == GEN_IPADD) {
      int len = ASN1_STRING_length(g->d.iPAddress);
      const unsigned char *a = ASN1_STRING_get0_data(g->d.iPAddress);
      char text[64];
      if ((len == 4 && inet_ntop(AF_INET, a, text, sizeof text) != NULL)
          || (len == 16 && inet_ntop(AF_INET6, a, text, sizeof text) != NULL)) {
        BIO_printf(b, "%sIP:%s", first ? "" : ",", text);
        first = 0;
      }
    } else if (g->type == GEN_EMAIL) {
      BIO_printf(b, "%semail:%.*s", first ? "" : ",", ASN1_STRING_length(g->d.rfc822Name),
                 (const char *)ASN1_STRING_get0_data(g->d.rfc822Name));
      first = 0;
    } else if (g->type == GEN_URI) {
      BIO_printf(b, "%sURI:%.*s", first ? "" : ",",
                 ASN1_STRING_length(g->d.uniformResourceIdentifier),
                 (const char *)ASN1_STRING_get0_data(g->d.uniformResourceIdentifier));
      first = 0;
    }
  }
  GENERAL_NAMES_free(names);
}

const char *idris_tls_peer_cert(void *p, int what) {
  tls_conn *c = p;
  out_buf[0] = '\0';
  pthread_mutex_lock(&c->lock);
  X509 *x = c->ssl != NULL ? SSL_get0_peer_certificate(c->ssl) : NULL;
  BIO *b = x != NULL ? BIO_new(BIO_s_mem()) : NULL;
  if (b != NULL) {
    switch (what) {
    case 0:
      X509_NAME_print_ex(b, X509_get_subject_name(x), 0, XN_FLAG_RFC2253);
      break;
    case 1:
      X509_NAME_print_ex(b, X509_get_issuer_name(x), 0, XN_FLAG_RFC2253);
      break;
    case 2:
      ASN1_TIME_print_ex(b, X509_get0_notBefore(x), ASN1_DTFLGS_ISO8601);
      break;
    case 3:
      ASN1_TIME_print_ex(b, X509_get0_notAfter(x), ASN1_DTFLGS_ISO8601);
      break;
    case 4:
      print_alt_names(b, x);
      break;
    case 5: {
      BIGNUM *bn = ASN1_INTEGER_to_BN(X509_get0_serialNumber(x), NULL);
      char *hex = bn != NULL ? BN_bn2hex(bn) : NULL;
      if (hex != NULL) BIO_puts(b, hex);
      OPENSSL_free(hex);
      BN_free(bn);
      break;
    }
    default:
      break;
    }
    bio_to_out(b);
    BIO_free(b);
  }
  ERR_clear_error();
  pthread_mutex_unlock(&c->lock);
  return out_buf;
}
