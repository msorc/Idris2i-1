*******************
The ``tls`` library
*******************

``libs/tls`` has TLS client and server connections over the non-blocking
sockets of ``Network.Socket.Async`` (see "Non-blocking sockets" in
:doc:`../backends/refc`), made with OpenSSL 3.  A connection is used like a
socket of that module, from a green thread: every operation that cannot go
on at once waits for the socket, and the worker that runs the thread runs
other threads meanwhile.

Building and installing
=======================

The library is optional: it is built, tested and installed with the others
only when ``pkg-config`` finds OpenSSL 3 or later (``pkg-config --exists
'openssl >= 3'``), with its development files.  Otherwise ``make``, ``make
test`` and ``make install`` say once that the library is skipped, and do
everything else as without it.  ``make IDRIS2I_1_TLS=1`` builds it anyway (and
fails without OpenSSL), ``make IDRIS2I_1_TLS=0`` leaves it out, and
``PKG_CONFIG`` names another ``pkg-config``.  It is not part of the
libraries of ``bootstrap``.

The library has a part in C (``libs/tls/c``), built by the ``prebuild``
script of ``tls.ipkg`` and installed in the ``lib`` directory of the package
by its ``postinstall`` script (see "Linking C libraries" in
:doc:`../ffi/ffi`): a static archive and its header for the RefC back end,
and a shared library for the Scheme ones.  A program that imports
``Network.TLS`` is linked with the archive and with OpenSSL (with the flags
of ``pkg-config --libs openssl``) by itself; it only needs ``depends =
network, tls`` in its package, or ``-p network -p tls``.

Using it
========

A program makes a context once, from a configuration, then wraps the
sockets that it connects or accepts:

.. code-block:: idris

    import Data.Buffer
    import Network.Socket.Async
    import Network.TLS

    covering
    get : IO ()
    get = do
      Right ctx <- newClientContext ({ alpn := ["http/1.1"] } defaultClientConfig)
        | Left e => putStrLn (show e)
      Right s <- connectHost ctx "example.org" 443 Nothing
        | Left e => putStrLn (show e)
      Just buf <- newBuffer 4096
        | Nothing => pure ()
      let req = "GET / HTTP/1.1\r\nHost: example.org\r\nConnection: close\r\n\r\n"
      setString buf 0 req
      Right () <- sendAll s buf 0 (cast (length req)) Nothing
        | Left e => putStrLn (show e)
      Right n <- recv s buf 0 4096 Nothing
        | Left e => putStrLn (show e)
      putStrLn !(getString buf 0 n)
      ignore (close s)

A server accepts a socket with ``Network.Socket.Async.accept``, then runs
the handshake with ``Network.TLS.accept``, in the thread of the connection:

.. code-block:: idris

    serve : ServerContext -> AsyncSocket -> IO ()
    serve ctx listener = do
      Right sock <- Network.Socket.Async.accept listener Nothing
        | Left e => putStrLn (show e)
      _ <- fork $ do
        d <- deadlineIn 10000000000
        Right s <- Network.TLS.accept ctx sock (Just d)
          | Left e => putStrLn (show e)
        ...
      serve ctx listener

with a context such as ``newServerContext (serverConfig (credentialFiles
"chain.pem" "key.pem"))``.  The names of ``Network.TLS`` are those of
``Network.Socket.Async`` where they do the same thing (``connect``,
``accept``, ``recv``, ``recvCode``, ``sendAll2Code``, ``close``, ...), and
the module re-exports ``Network.Socket.Async``: a name that both have is
written with its module where its arguments do not tell which one it is.

Configuration
-------------

``ClientConfig`` (``defaultClientConfig``):

* ``minVersion``: ``TLS12`` (the default) or ``TLS13``.  TLS 1.0 and 1.1 are
  never accepted.
* ``trust``: where the trusted certificates come from: ``SystemTrust`` (the
  default: those that OpenSSL finds on the system, which ``SSL_CERT_FILE``
  and ``SSL_CERT_DIR`` can override), ``CAFile``, ``CADirectory`` (hashed with
  ``openssl rehash``) and ``CAText`` (PEM text).
* ``verifyPeer`` and ``verifyHostname``: both on by default.
  ``insecureNoVerification`` turns both off, for tests.
* ``alpn``: the protocols to offer with ALPN, in order (none by default).
* ``certificate``: a client certificate and its key, for servers that ask
  for one.

``ServerConfig`` (``serverConfig credentials``):

* ``credentials``: the certificate chain (the certificate first, then the
  intermediate ones) and its private key, as PEM files (``PEMFile``) or PEM
  text (``PEMText``).
* ``sniCredentials``: other credentials for the names that clients ask for
  with SNI: a host name, or ``*.domain`` for any name of one more label in
  ``domain``.  The first one that matches is used, ``credentials`` when none
  does.
* ``alpn``: the protocols that the server takes, by preference: it selects
  the first of them that the client offers.  When there is none,
  ``alpnRequired`` says whether the handshake fails (with the alert
  ``no_application_protocol``) or goes on without ALPN (the default).
* ``clientAuth`` (``NoClientCertificate`` by default,
  ``OptionalClientCertificate``, ``RequiredClientCertificate``) and
  ``clientTrust``, the authorities of client certificates.

The cipher suites are the defaults of OpenSSL; renegotiation is refused;
sessions are resumed as OpenSSL does by default.

Verification
------------

A client verifies the certificate of the server by default: it must chain
to a trusted authority, be valid now, and be for the name given to
``connect`` (``SSL_set1_host``; an IP address is checked against the IP
addresses of the certificate).  The name is also sent with SNI unless it is
an IP address.  A rejected certificate is a ``VerifyError`` with the code
of OpenSSL (``X509_V_ERR_*``) and its message: ``certificate verify failed:
unable to get local issuer certificate``, ``...: hostname mismatch``,
``...: certificate has expired``, ...  The peer that is rejected sees the
alert as a ``ProtocolError`` (``tlsv1 alert unknown ca``, ...).

There are no verification callbacks written in Idris2i-1: the policy is that of
OpenSSL, configured by the fields above.

Reading, writing and closing
----------------------------

As in ``Network.Socket.Async``, there are two layers:

* ``recv``, ``send``, ``sendAll``, ``sendAll2`` and ``recvExactly`` take a
  deadline (``Maybe Int``, an absolute time on the clock of
  ``System.IO.Wait.now``) and return ``Either TLSError a``;
* ``recvCode``, ``sendCode``, ``sendAllCode``, ``sendAll2Code`` and
  ``recvExactlyCode`` have the types of their namesakes in
  ``Network.Socket.Async``, with a ``TLSSocket`` for the socket, and return
  a plain ``Int`` (a deadline below 0 is none): a count, or a negative code.

``recvCode`` returns 0 at the end of the TLS stream (the peer sent
close_notify); a stream that ends without it (the peer went away, or
someone cut it) is ``codeUnexpectedEOF``, so that a reader can tell a
complete message from a truncated one.  ``sendAll2Code`` sends two ranges in
one TLS record when they fit in one (16 kB).  The negative codes are:

=========================  =====  ==========================================
Code                       Value  Meaning (``TLSError``)
=========================  =====  ==========================================
``-ETIMEDOUT``             -110   the deadline came first (``Timeout``)
``-EBADF``                 -9     the connection was closed (``Closed``)
``-EINVAL``                -22    the range is not in the buffer
other ``-errno``                  an error of the socket, ``-ECONNRESET``,
                                  ``-EPIPE``, ... (``SysError``)
``codeClosed``             -1003  close_notify during the handshake
                                  (``PeerClosed``; ``recvCode`` returns 0)
``codeUnexpectedEOF``      -1004  the stream ended without close_notify
                                  (``UnexpectedEOF``)
``codeProtocolError``      -1005  an error of TLS: an alert, an invalid
                                  message, nothing in common
                                  (``ProtocolError`` with the message of
                                  OpenSSL)
``codeVerifyError``        -1006  the certificate of the peer was rejected
                                  (``VerifyError``)
``codeConfigError``        -1007  the connection could not be set up
                                  (``ConfigError``)
=========================  =====  ==========================================

(the errno values are those of Linux).  ``codeWantRead`` (-1001) and
``codeWantWrite`` (-1002) are the codes of the C functions under the loops,
which never return them.  The codes of TLS are all at -1000 or below
(``isTLSCode``), away from the errno codes of every system, so code that
treats any negative result as a failure works with both kinds of socket;
``codeError`` turns a code into a ``TLSError`` and ``codeMessage`` gives its
message (the one of OpenSSL, which the connection keeps, for the codes of
TLS).

``close`` (``closeCode`` with an ``Int`` result) sends close_notify, waits
up to a second for the close_notify of
the peer (``closeCodeWithin`` takes the deadline), frees the TLS session and
closes the socket: waiting for the peer to close too keeps the system from
resetting a connection whose peer still sends, which could lose the end of
what this side sent.  ``abort`` closes at once, without close_notify.
``closeNotifyCode`` only sends close_notify (the end of what this side
writes) and returns: the connection can still be read until the peer ends
its side, and is then closed with ``close``.
After ``connect`` or ``accept`` the socket belongs to the connection, and
when the handshake fails it is closed.  A connection that is dropped
without ``close`` has its TLS session freed by the collector, but its
socket stays open.

``tlsVersion``, ``cipherName``, ``alpnSelected``, ``serverName`` (the name
of SNI, on both sides) and ``peerCertificate`` (subject, issuer, validity,
alternative names and serial number, for logs) say what was negotiated.

Threads
-------

Each operation does all of its work, and collects its error, in one call
of C, as errno and the error queue of OpenSSL belong to the OS thread, which
a green thread may change between two calls.  An ``SSL`` object of OpenSSL
cannot be used by two OS threads at once, so every operation takes a lock of
the connection for the time of one call to OpenSSL (which never blocks: the
socket is non-blocking).  So one thread may read a connection while
another one writes it, and either may wait for the socket in the meantime
(a read may have to write, and a write to read, as OpenSSL says); both are
woken up when the socket is ready.  Two threads that read, or two that
write, at the same time are not supported: their data would interleave in
any order, and a write that waited must be done again with the same bytes.

The socket of the C part sends with ``MSG_NOSIGNAL`` (the socket BIO of
OpenSSL uses ``write(2)``, which raises ``SIGPIPE``), so a write to a peer
that is gone fails with ``EPIPE``, as with the sockets of the network
library.  Writes are partial (``SSL_MODE_ENABLE_PARTIAL_WRITE``): a write
returns once a record is out, and ``sendAllCode`` writes the rest.  A write
that waited is done again with the same bytes, which may be at another
address (``SSL_MODE_ACCEPT_MOVING_WRITE_BUFFER``: a ``Buffer`` of RefC does
not move, but a bytevector of Chez may).

HTTPS: the ``http-tls`` library
-------------------------------

``libs/http-tls`` (``-p http-tls``, module ``Network.HTTP.TLS``) puts the
server and the client of the ``http`` library over TLS connections.  It is
built, tested and installed exactly when this library is.

* ``tlsTransport`` makes a ``Transport`` of the ``http`` library of a
  ``TLSSocket``: it is ``secure``, its ``transportProtocol`` is the protocol
  that ALPN selected, and its errors are minus errno codes, as a socket's (a
  stream that ends without close_notify, or an error of TLS, is
  ``-ECONNRESET``).  Shutting down its writing side sends close_notify;
  shutting down its reading side wakes up a thread that waits in ``recv``,
  which gets the end of the stream; closing it sends close_notify if it
  was not sent, waits at most ``closeWaitMs`` (500 ms) for the one of the
  peer and closes the socket.
* ``httpsServerConfig ctx cfg`` gives the configuration of a server with
  ``makeTransport`` set to run the handshake of a ``ServerContext`` in the
  thread of each connection, with the ``headTimeout`` of the configuration
  as its deadline (``tlsMakeTransport`` takes another one), and the
  counters of the handshakes (``handshakeCounts``: succeeded, failed, timed
  out).  A handshake that fails (a plain HTTP request sent to the HTTPS
  port, a client that does not trust the certificate, one that says
  nothing until the deadline) is counted and written to the ``errorLog`` of
  the server, and the socket is closed; the accept loop goes on.
* ``httpsClientConfig ctx cfg`` gives the configuration of a client that
  fetches ``https://`` URLs over the connections of a ``ClientContext``
  (``tlsConnector``): the host of the URL is sent with SNI (unless it is an
  IP address) and the certificate is verified for it (an IP address against
  the IP addresses of the certificate).  A handshake that fails is the
  error ``OtherError "TLS: ..."`` of the request, with the message of this
  library (``TLS: certificate verify failed: hostname mismatch``, ...).
  ``defaultHTTPSClientConfig`` verifies with the certificates of the system.
* HTTP/2: a server whose context offers ``h2`` with ALPN (``alpn :=
  ["h2", "http/1.1"]``) serves HTTP/2 to the clients that select it, and a
  client whose context offers it speaks HTTP/2 to the servers that select
  it (see "HTTP/2" in :doc:`../cookbook/webservice`).

.. code-block:: idris

    import Network.HTTP.Client
    import Network.HTTP.Router
    import Network.HTTP.TLS
    import Network.TLS

    main : IO ()
    main = do
      Right sctx <- newServerContext ({ alpn := ["http/1.1"] }
                                        (Network.TLS.serverConfig (credentialFiles "chain.pem" "key.pem")))
        | Left e => putStrLn (show e)
      (cfg, stats) <- httpsServerConfig sctx (defaultServerConfig (Inet "127.0.0.1" 8443))
      Right srv <- startServer cfg (router routes)
        | Left e => putStrLn (show e)
      Right ccfg <- defaultHTTPSClientConfig
        | Left e => putStrLn (show e)
      c <- newClient ccfg
      r <- httpGet c "https://example.org/"
      ...

The TLS transport goes through the record of functions of
``customTransport``, which costs a few allocations per call on RefC (about
200 instructions per request).  A small request on a persistent connection
costs the server about 1.9 times the instructions of one over a plain
socket (35,000 against 19,000 for ``GET /hello`` in ``benchmark/http``),
nearly all of the difference in OpenSSL and in the system.  A new
connection costs a handshake on top: about 2.9 million instructions on the
server side for an ECDSA P-256 certificate.

Back ends
---------

The library works with RefC, where the waits park green threads, and with
Chez, which loads its shared library, and where the waits block OS threads
in ``poll(2)`` (and closing a connection does not wake up a thread that
waits for it).  It does not work on Windows, where the non-blocking sockets do not,
nor with the JavaScript back ends.  It has only been tested on Linux.

What it does not do
-------------------

* TLS 1.0 and 1.1, renegotiation, and cipher lists other than OpenSSL's.
* Verification callbacks written in Idris2i-1, OCSP stapling, certificate
  revocation lists, pinning.
* Tuning of sessions and session tickets, early data (0-RTT).
* QUIC and DTLS.
