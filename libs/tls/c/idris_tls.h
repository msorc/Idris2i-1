#pragma once

// TLS connections over non-blocking sockets, with OpenSSL 3 (see Network.TLS
// in the tls library).
//
// As in idris_net_async.h, an Idris `Int` is an `int` here, a `Buffer` is a
// pointer to its bytes, and a `GCAnyPtr` or `AnyPtr` is a `void *`.  No
// function blocks: the sockets are non-blocking, and an operation that
// cannot go on returns IDRIS_TLS_WANT_READ or IDRIS_TLS_WANT_WRITE, after
// which the caller waits for the socket (idris2_ioWait on RefC,
// idris2_fdWaitBlocking elsewhere) and calls it again with the same
// arguments.
//
// errno and the error queue of OpenSSL belong to the OS thread, and a green
// thread may move to another OS thread between two foreign calls: so every
// function here does its whole operation, and collects its error, in one
// call.  The message of the last error of a connection is kept in the
// connection (idris_tls_conn_error), and that of a context in the context
// (idris_tls_ctx_error).
//
// The strings that functions return point to memory of the OS thread that
// called them (or of the object), valid until the next call on that thread:
// the caller copies them at once (an Idris `String` result does).
//
// A connection may be used by two threads at a time, one that reads and one
// that writes: every operation takes a lock of the connection for the time
// of one OpenSSL call, which never blocks.  Two threads that read, or two
// that write, at the same time are not supported.

// The results of the operations on connections, below 0: they are all below
// -1000, so that they are not confused with minus an errno code (the errors
// of the system are returned as minus their errno code, as in the network
// library, and minus EBADF for a connection that was released).
#define IDRIS_TLS_WANT_READ       (-1001) // wait until the socket is readable
#define IDRIS_TLS_WANT_WRITE      (-1002) // wait until the socket is writable
#define IDRIS_TLS_CLOSED          (-1003) // the peer closed the TLS session (close_notify)
#define IDRIS_TLS_UNEXPECTED_EOF  (-1004) // the stream ended without close_notify
#define IDRIS_TLS_PROTOCOL_ERROR  (-1005) // an error of TLS (see idris_tls_conn_error)
#define IDRIS_TLS_VERIFY_ERROR    (-1006) // the certificate of the peer was rejected
#define IDRIS_TLS_CONFIG_ERROR    (-1007) // a context or a connection could not be set up

// ---------------------------------------------------------------------------
// Contexts

// A new context for clients (is_server 0) or servers (1), with TLS 1.2
// (min_version 12) or 1.3 (13) at least, the default ciphers of OpenSSL,
// and no renegotiation.  A client context verifies the certificate of the
// server by default (with no trusted certificates yet: see below).  NULL
// when OpenSSL cannot make one (out of memory).  Freed by idris_tls_ctx_free.
void *idris_tls_ctx_new(int is_server, int min_version);

// Free a context.  The connections made with it keep what they need of it,
// and stay usable.
void idris_tls_ctx_free(void *ctx);

// The message of the last error of a function of a context.
const char *idris_tls_ctx_error(void *ctx);

// The functions below return 0, or IDRIS_TLS_CONFIG_ERROR with a message
// in idris_tls_ctx_error.

// Trust the certificates of the system (SSL_CTX_set_default_verify_paths).
int idris_tls_ctx_use_system_trust(void *ctx);

// Trust the certificates of a PEM file, and/or of a directory hashed with
// `openssl rehash` ("" for none).  On a server context, the names of the
// certificates of the file are also the ones a client certificate is asked
// to be issued by.
int idris_tls_ctx_trust(void *ctx, const char *ca_file, const char *ca_dir);

// Trust the certificates of PEM text.
int idris_tls_ctx_trust_pem(void *ctx, const char *pem);

// Verify the peer: 0 not at all; 1 verify its certificate when it sends one
// (always for a client, which the server always sends one to); 2 also fail
// when the peer sends none (a server that requires client certificates).
int idris_tls_ctx_set_verify(void *ctx, int mode);

// The certificate chain and private key of the context: PEM files
// (is_pem_text 0), or PEM text (1).  The chain starts with the certificate
// of the context, followed by the intermediate ones.
int idris_tls_ctx_use_cert(void *ctx, const char *chain, const char *key,
                           int is_pem_text);

// A server: another certificate chain and key, used when the client asks
// for `name` with SNI (a name of a host, or `*.domain` for any name of one
// more label in `domain`; letter case does not matter).  The verification
// of client certificates is the one that the context has when this is
// called: call it after idris_tls_ctx_trust and idris_tls_ctx_set_verify.
int idris_tls_ctx_add_sni_cert(void *ctx, const char *name, const char *chain,
                               const char *key, int is_pem_text);

// ALPN.  `protocols` is a list of protocol names separated by commas
// ("h2,http/1.1").  A client offers them, in this order.  A server selects
// the first of its own list that the client offers; when there is none,
// the handshake goes on without ALPN (required 0) or fails with the alert
// no_application_protocol (required 1).
int idris_tls_ctx_set_alpn(void *ctx, const char *protocols, int required);

// ---------------------------------------------------------------------------
// Connections

// A new connection with the context on the connected, non-blocking socket
// `fd` (which it does not close).  A client sends `host` with SNI (unless
// it is empty or an IP address), and checks with verify_host 1 that the
// certificate of the server is for `host` (a name or an IP address).
// Returns the connection, or NULL when out of memory; check
// idris_tls_conn_status before using it.  Freed by idris_tls_conn_free.
void *idris_tls_conn_new(void *ctx, int fd, const char *host, int verify_host);

// 0 when the connection was made, IDRIS_TLS_CONFIG_ERROR otherwise (see
// idris_tls_conn_error).
int idris_tls_conn_status(void *conn);

// The handshake: 0 when it is done, or a negative result.
int idris_tls_handshake(void *conn);

// Read at most `len` bytes into `buf + offset`: the number of bytes (above
// 0), or a negative result (IDRIS_TLS_CLOSED at the end of the TLS stream).
int idris_tls_read(void *conn, char *buf, int offset, int len);

// Write at most `len` bytes from `buf + offset`: the number of bytes
// written (above 0; maybe fewer than `len`), or a negative result.  After
// IDRIS_TLS_WANT_READ or IDRIS_TLS_WANT_WRITE, call it again with the same
// bytes (the buffer may have moved).
int idris_tls_write(void *conn, const char *buf, int offset, int len);

// Write `len1` bytes of `buf1` from `off1`, then `len2` bytes of `buf2`
// from `off2`: in one TLS record when they fit in one.  The number of bytes
// written, which may end in either range, or a negative result; retry as
// for idris_tls_write.
int idris_tls_write2(void *conn, const char *buf1, int off1, int len1,
                     const char *buf2, int off2, int len2);

// Close the TLS session (close_notify): 0 when it is closed both ways (or
// cannot be: the handshake was not done, or the connection failed), 1 when
// close_notify was sent and the one of the peer has not come yet (call it
// again, after waiting for the socket to be readable), or a negative
// result.
int idris_tls_shutdown(void *conn);

// Free the OpenSSL session of the connection (not the socket): every later
// operation on the connection returns -EBADF.  Returns 1 the first time, 0
// afterwards (so that the caller closes the socket once).
int idris_tls_conn_release(void *conn);

// Release the connection and free it (the finaliser).
void idris_tls_conn_free(void *conn);

// The message of the last error of an operation on the connection.
const char *idris_tls_conn_error(void *conn);

// The verification result (X509_V_*) of the certificate of the peer: 0
// when it was accepted, or when it was not verified.
int idris_tls_verify_result(void *conn);

// Facts about an established connection ("" when there is none): `what` is
// 0 the version of the protocol ("TLSv1.3"), 1 the cipher suite, 2 the
// protocol selected with ALPN, 3 the name that the client asked for with
// SNI, 4 whether the peer sent a certificate ("1" or "").
const char *idris_tls_info(void *conn, int what);

// The certificate of the peer ("" when there is none): `what` is 0 the
// subject, 1 the issuer (RFC 2253), 2 the start and 3 the end of the
// validity (ISO 8601), 4 the subject alternative names ("DNS:a,IP:b"), 5
// the serial number (hexadecimal).
const char *idris_tls_peer_cert(void *conn, int what);

// The message of a result code (not of the system's errno codes).
const char *idris_tls_code_message(int code);

// The version of OpenSSL ("OpenSSL 3.6.5 ...").
const char *idris_tls_openssl_version(void);
