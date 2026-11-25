.. _cookbook-webservice:

*********************
Writing a web service
*********************

The ``http`` library has an HTTP/1.1 server and client built on the
non-blocking sockets of ``network`` (``Network.Socket.Async``).  With the
RefC back end each connection is a green thread, so a service can hold
thousands of connections on a few OS threads.  This page walks through
``samples/webservice``, a small JSON API over an in-memory store: a list of
things to do.

The modules
===========

``Network.HTTP.Server``
    ``startServer``, ``stopServer``, ``serve``; the ``Request`` and
    ``Response`` records; ``ServerConfig`` with its limits and timeouts.

``Network.HTTP.Router``
    ``route`` (a method and a path pattern), ``router`` (a ``Handler`` that
    answers 404 and 405 by itself), the JSON helpers ``jsonBody``,
    ``jsonResponse`` and ``jsonError``.  It re-exports the server.

``Network.HTTP.Client``
    ``newClient``, ``fetch``, ``httpGet``, ``httpPost``, ``withResponse``
    for URLs; ``request`` for a connection made by hand.

``Network.HTTP.Connection`` and ``Network.HTTP.Transport``
    the reading and writing of messages, and the byte stream under them
    (a socket, or a TLS session from another library).

The data
========

The service sends items and receives new ones.  The JSON instances are
derived (``Language.JSON.Derive``):

.. code-block:: idris

    record Todo where
      constructor MkTodo
      id : Int
      title : String
      done : Bool

    record NewTodo where
      constructor MkNewTodo
      title : String
      done : Maybe Bool

    %hint
    todoToJSON : ToJSON Todo
    todoToJSON = %runElab deriveToJSON defaultOptions

    %hint
    newTodoFromJSON : FromJSON NewTodo
    newTodoFromJSON = %runElab deriveFromJSON defaultOptions

A ``Maybe`` field may be missing from the JSON object; the others must be
there.

The store is an ``IORef`` holding a map and the next id.  The handlers run
in many threads at once (one per connection, and with several workers in
parallel), so the store only changes through ``atomicModifyIORef``, which
runs its function again if another thread wrote the ``IORef`` meanwhile:

.. code-block:: idris

    record Store where
      constructor MkStore
      items : SortedMap Int Todo
      nextId : Int

Routes
======

A route is a method, a pattern and a handler, which gets the request and
the captured segments of the path:

.. code-block:: idris

    routes : IORef Store -> List Route
    routes store =
      [ route GET "/todos/:id" $ \_, ps => do
          s <- readIORef store
          pure $ case idParam ps >>= \i => lookup i s.items of
            Just t => jsonResponse statusOK t
            Nothing => jsonError statusNotFound "no such item"

      , route POST "/todos" $ \req, _ => do
          Right new <- jsonBody {a = NewTodo} req
            | Left bad => pure bad
          todo <- atomicModifyIORef store $ \s =>
                    let t = MkTodo s.nextId new.title (fromMaybe False new.done) in
                    ({ items $= insert t.id t, nextId $= (+ 1) } s, t)
          pure (jsonResponse statusCreated todo)
      , ...
      ]

``:id`` captures one segment, and ``*rest`` the rest of the path.  The
segments are percent-decoded before they are compared or captured.
``jsonBody`` reads the body (up to ``maxBodySize``) and decodes it; when
that fails it gives the response to send instead: 413 for a body that is
too large, and 400 with the reason and the part of the value that does not
fit, in the notation of JSONPath::

    {"error":"expected a string, got a number","path":"$.title"}

``router routes`` is the handler of the server.  A path that no route has
gets 404, one that routes have with other methods 405 with ``Allow``, and
``HEAD`` goes to the ``GET`` route (the server sends the head only).
``queryParam "done" req`` reads the query.

Serving
=======

.. code-block:: idris

    main : IO ()
    main = do
      store <- newIORef (MkStore empty 1)
      let cfg = { accessLog := Just logRequest } (defaultServerConfig (Inet "127.0.0.1" 8080))
      Right srv <- startServer cfg (router (routes store))
        | Left e => putStrLn "cannot listen: \{show e}"
      Right () <- collectSignal SigINT
        | Left _ => putStrLn "cannot catch SIGINT"
      _ <- fork (stopOnInterrupt srv)
      waitServer srv

``startServer`` listens and returns at once; the accept loop and the
connections run in threads of their own.  ``stopOnInterrupt`` polls for the
signal (``System.Signal``) and calls ``stopServer srv 5000``: the server
stops accepting, closes the connections that wait for a request, lets the
requests in progress finish for up to five seconds (their connections close
after the response), and then ``waitServer`` returns.

The ``ServerConfig`` record has the limits: the limits of the head parser
(``Network.HTTP.Parser.Limits``), ``maxBodySize``, ``maxConnections``, and
the timeouts in milliseconds: ``headTimeout`` (a client that sends its head
too slowly gets 408), ``bodyTimeout`` (each read of a body),
``idleTimeout`` (between requests of a persistent connection) and
``writeTimeout``.  ``accessLog`` gets a record per response; ``errorLog``
gets what went wrong in the server.

What the server does by itself: persistent connections and pipelined
requests answered in order, ``Connection: close`` and HTTP/1.0, ``100
Continue`` when the handler starts reading the body of a request that asks
for it, draining a body that the handler did not read, ``Content-Length``
or the chunked coding, ``Date``.  A malformed or ambiguous request (one
with both ``Content-Length`` and ``Transfer-Encoding``, say) is answered
with the status that the parser gives and the connection is closed: the
handler never sees it.  A response field whose value has a CR or LF is
replaced by a 500 rather than sent.

Bodies
======

A request body is read whole with ``requestBody req`` or, for a large
upload, a piece at a time with ``readChunk req.body``, which does not keep
what it has given.  A response body is ``BytesBody``, ``BuilderBody``, or
``StreamBody len write`` for a body written a piece at a time by
``write``, in the chunked coding when its length is not known
(``writeBody w bytes``).

Errors in handlers
==================

A handler is an ``IO`` action, which cannot throw.  ``fromEither log h``
makes a handler of ``h : Request -> IO (Either String Response)`` that
answers 500 for a ``Left`` and gives the message to ``log``.

A crash of a handler (``idris_crash``, a missing case of a partial function,
an index out of a ``Buffer``) ends only its request: the server runs every
handler in a crash boundary (``System.Crash.catchCrash``).  The error log of
the configuration gets the message (and the backtrace, with
``IDRIS2I_1_REFC_BACKTRACE=1``), the access log gets the request, and the client
gets 500 if no part of the response was sent; over HTTP/1.1 the connection is
then closed, over HTTP/2 only the stream ends (reset with ``INTERNAL_ERROR`` if
its response had started).  A WebSocket session that crashes is closed with
1011.  This is for isolation, not for errors that the handler expects: a
caught crash leaks what the handler still held (its request, if it still
needed it: a few hundred bytes for a small one), and
a ``Mutex`` that it held stays held.  ``crashesCaught`` says how many there
were, for a server that should be restarted now and then.  Stack overflows and
crashes in finalisers still end the process (see :doc:`../backends/refc`).

Building and running
====================

``samples/webservice/webservice.ipkg`` depends on ``contrib``, ``network``
and ``http``:

.. code-block:: bash

    cd samples/webservice
    idris2i-1 --build webservice.ipkg
    ./build/exec/webservice 8080

    curl -d '{"title": "write the docs"}' http://127.0.0.1:8080/todos
    curl http://127.0.0.1:8080/todos

The RefC back end (the default) gives green threads and the reactor of
non-blocking sockets.  It runs one worker per processor; ``IDRIS2I_1_WORKERS=1``
runs every thread on one OS thread, ``IDRIS2I_1_WORKERS=4`` on four.  Each
green thread has a stack of 8 MB of address space (``IDRIS2I_1_THREAD_STACK_SIZE``)
of which only the pages it touches use memory, so an idle connection costs
little.  On Chez the same program works with an OS thread per
connection, each read and write blocking its thread.

HTTPS
=====

The ``http-tls`` library (``libs/http-tls``, built with the ``tls`` library
when OpenSSL 3 is there: see :doc:`../libraries/tls`) serves the same
routes over TLS.  ``samples/webservice/Https.idr`` is the sample over HTTPS
(the routes are in ``Todos.idr``, which both mains import):

.. code-block:: idris

    import Network.HTTP.Router
    import Network.HTTP.TLS
    import Network.TLS

    main : IO ()
    main = do
      Right ctx <- newServerContext ({ alpn := ["http/1.1"] }
                                       (Network.TLS.serverConfig (credentialFiles "cert.pem" "key.pem")))
        | Left e => putStrLn "cannot use the certificate: \{show e}"
      store <- newStore
      (cfg, stats) <- httpsServerConfig ctx (defaultServerConfig (Inet "127.0.0.1" 8443))
      Right srv <- startServer cfg (router (routes store))
        | Left e => putStrLn "cannot listen: \{show e}"
      ...

.. code-block:: bash

    cd samples/webservice
    openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes \
      -keyout key.pem -out cert.pem -days 30 -subj /CN=localhost \
      -addext subjectAltName=DNS:localhost,IP:127.0.0.1
    idris2i-1 --build webservice-https.ipkg
    ./build/exec/webservice-https 8443 cert.pem key.pem
    curl --cacert cert.pem https://localhost:8443/todos

``httpsServerConfig`` makes each connection run the TLS handshake in its
own thread before its first request, within ``headTimeout``: a client that
does not finish it in time (one that connects and says nothing, say) is
dropped, as is a plain HTTP request sent to the HTTPS port.  Failed
handshakes go to ``errorLog`` and are counted (``handshakeCounts stats``);
they never stop the server.  A handler sees ``req.secure`` set.

A client fetches ``https://`` URLs once its configuration has a TLS
connector:

.. code-block:: idris

    Right cfg <- defaultHTTPSClientConfig       -- the authorities of the system
      | Left e => putStrLn (show e)
    c <- newClient cfg
    r <- httpGet c "https://localhost:8443/todos"

or ``httpsClientConfig ctx defaultClientConfig`` with a ``ClientContext``
of one's own (``trust := [CAFile "cert.pem"]`` for the certificate above).
The host of the URL is sent with SNI and the certificate is verified for
it; a certificate that does not verify fails the request with an
``OtherError`` that says why (``TLS: certificate verify failed: hostname
mismatch``).

HTTP/2
======

The server speaks HTTP/2 (RFC 9113) to the clients that ask for it, with
the same handlers: a ``Handler`` does not need to know the protocol, and
``req.version`` is ``MkVersion 2 0`` (``http2``) for a request that came
over HTTP/2.  A connection is served with HTTP/2

* over TLS, when ALPN selected ``h2``: offer it in the context of the server,
  ``{ alpn := ["h2", "http/1.1"] } (serverConfig creds)``;
* on a plain connection, when the client starts with the preface of HTTP/2
  (``h2c`` with prior knowledge, as ``curl --http2-prior-knowledge`` does),
  unless ``{ http2.cleartext := False }``.  The ``Upgrade: h2c`` mechanism
  of HTTP/1.1 is not implemented (RFC 9113 made it obsolete).

Each stream runs its handler in a green thread of its own; a reader thread
per connection reads and decodes the frames (and keeps the HPACK decoder),
and a writer thread writes everything that the streams queue, in order
(and keeps the HPACK encoder).  Request bodies are read with the same
``BodyReader`` as for HTTP/1.1; the window of a stream is opened again as
the handler reads its body, so a handler that does not read makes the
client stop rather than the server buffer.  A response body goes out
within the windows of the client, and the writer of a ``StreamBody`` waits
for them (up to ``writeTimeout``).  ``UpgradeBody`` is not possible over
HTTP/2 (the server answers 500 and logs it).  A stream that the client
resets makes the reads and writes of its handler fail; the handler thread
runs on until it returns.  ``stopServer`` sends GOAWAY, lets the streams in
progress finish within the grace time and refuses new ones.

``ServerConfig.http2`` (an ``H2Config``, ``defaultH2Config``) has the
settings and the limits:

======================================  ==========  ===============================================
Field                                   Default     Beyond it
======================================  ==========  ===============================================
``maxConcurrentStreams``                100         RST_STREAM REFUSED_STREAM
``initialWindowSize``                   256 KiB     (window of each stream; FLOW_CONTROL_ERROR)
``connectionWindowSize``                1 MiB       (window of the connection; FLOW_CONTROL_ERROR)
``maxHeaderListSize``                   64 KiB      431, the HPACK decoder kept in step
``headerTableSize``                     4 KiB       (dynamic table of the decoder)
``maxHeaderBlockSize``                  128 KiB     GOAWAY ENHANCE_YOUR_CALM (HEADERS + CONTINUATION)
``maxContinuations``                    64          GOAWAY ENHANCE_YOUR_CALM
``settingsTimeout``                     10 s        GOAWAY SETTINGS_TIMEOUT
``maxQueuedControlFrames``              1,000       GOAWAY ENHANCE_YOUR_CALM (PING/SETTINGS floods)
``maxResetsPerSecond``                  200         GOAWAY ENHANCE_YOUR_CALM (rapid reset)
``maxEmptyFramesPerSecond``             1,000       GOAWAY ENHANCE_YOUR_CALM (empty or padding-only)
``streamBufferSize``                    256 KiB     the writer of the stream waits
``connectionBufferSize``                2 MiB       the writers of the connection wait
======================================  ==========  ===============================================

The rapid reset of CVE-2023-44487 (streams opened and reset in a loop) is
bounded twice: at most twice ``maxConcurrentStreams`` handler threads run
on a connection (more streams are refused, and the refusals count as
resets), and more than ``maxResetsPerSecond`` resets of streams in progress
end the connection.  Malformed requests (upper-case field names,
connection-specific fields, missing or repeated pseudo-header fields, a
``content-length`` that the DATA frames do not match, ...) are reset with
PROTOCOL_ERROR before the handler runs; PRIORITY frames, unknown frames and
unknown settings are ignored; PUSH_PROMISE is never sent and is a
connection error from a client.

The client speaks HTTP/2 to an ``https://`` server when ALPN selects
``h2`` (offer it in the ``ClientContext``: ``alpn := ["h2", "http/1.1"]``),
and to ``http://`` URLs with ``http2PriorKnowledge := True``.  The requests
to a host then share one connection, as many at a time as the server
allows; a request that the server did not process (above the last stream
of a GOAWAY, or refused) is sent again on a new connection if its method is
idempotent and its body can be sent again.  The ``Reply`` and
``ClientResponse`` are those of HTTP/1.1 (``version`` says which).

The client
==========

.. code-block:: idris

    c <- newClient defaultClientConfig
    Right r <- httpGet c "http://127.0.0.1:8080/todos"
      | Left e => putStrLn (show e)
    putStrLn (toStringLossy r.body)

A ``Client`` resolves the host, connects within ``connectTimeout``, sends
``Host``, keeps persistent connections in a pool per host (for
``idleTimeout``), follows up to ``maxRedirects`` redirects, and bounds each
request by ``requestTimeout``.  ``fetch`` reads the whole body (up to
``maxResponseSize``); ``withResponse`` gives the response to a function that
reads the body as a stream.

What is not there yet
=====================

* TLS without OpenSSL 3: ``https://`` URLs then fail with a message naming
  the missing transport (``tlsConnect`` of ``ClientConfig``).
* WebSocket over HTTP/2, and server push (WebSocket connections over
  HTTP/1.1 are there: see :ref:`cookbook-websocket`).
* In the client: cookies, proxies, compression.
* Pattern matching on a ``ByteString`` literal (``case req.path of "/a" =>
  ...``): a byte string is not built by a constructor, so the compiler
  rejects such a pattern; compare with ``==``, or use the router.
