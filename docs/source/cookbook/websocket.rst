.. _cookbook-websocket:

*********************
WebSocket connections
*********************

``Network.WebSocket`` (in the ``http`` library) has the server and the client
sides of WebSocket connections (RFC 6455) over the HTTP/1.1 server and client
of the library.  This page walks through ``samples/chat``, a chat room: what
someone sends goes to everybody in the room.

The server side
===============

A handler answers an upgrade request with ``acceptWebSocket``, which checks
the handshake and gives either the ``101`` response that hands the
connection to a session function, or the error response that the RFC asks
for (405 for another method than ``GET``, 426 with ``Upgrade: websocket``
without the ``Upgrade`` field, 426 with ``Sec-WebSocket-Version: 13`` for
another version, 400 for a bad key, 403 for an origin that the
``checkOrigin`` of the options refuses).  With the router,
``websocketRoute`` makes the route:

.. code-block:: idris

    routes : Room -> List Route
    routes room =
      [ route GET "/" $ \_, _ => pure (bytesResponse statusOK "text/html; charset=utf-8" (fromString page))
      , websocketRoute "/chat" options $ \req, _, ws =>
          session room (fromMaybe "someone" (queryParam "name" req)) ws
      ]

The session runs in the thread of the connection.  When it returns, the
connection is closed (with 1000 if the session did not close it) once no
other thread uses it.  If it crashes (see the errors of handlers in
:ref:`cookbook-webservice`), the connection is closed with 1011 and the error
log of the server gets the crash.

.. code-block:: idris

    session : Room -> String -> WebSocket -> IO ()
    session room name ws = do
      (i, n) <- join room name ws
      ignore (sendText ws ("welcome " ++ name ++ ", " ++ show n ++ " here"))
      broadcast room ("* " ++ name ++ " joined")
      loop
      leave room i
      broadcast room ("* " ++ name ++ " left")
      where
        loop : IO ()
        loop = do
          Right msg <- receive ws
            | Left _ => pure ()
          broadcast room (name ++ ": " ++ messageString msg)
          loop

``subprotocols`` of ``AcceptOptions`` lists the subprotocols that the server
speaks, the one it prefers first; ``subprotocol ws`` says which one the
handshake selected.  No extension is negotiated: an offer of
``permessage-deflate`` is ignored.

Messages
========

``receive`` gives whole messages, ``TextMessage`` or ``BinaryMessage``, each
with a ``ByteString``: the fragments of a message are put together (up to
``maxMessageSize``), and the bytes of a text message have been checked to be
UTF-8 (``messageString`` makes them a ``String`` without checking them
again).  On the way, ``receive`` answers pings, counts pongs
(``pongCount``), and does the closing handshake; when the connection ends it
gives a ``CloseInfo``: the code and reason of the close frame of the peer
(1005 for a close frame without a code, 1006 when none came), the code that
this side sent, and which side started.  A peer that breaks the protocol is
closed with 1002 (a protocol error), 1007 (text that is not UTF-8) or 1009
(a message over the limit).

``sendText``, ``sendBinary`` and ``sendMessage`` send a message;
``fragmentSize`` of the configuration sends long ones in fragments.  ``ping``
sends a ping, ``closeWebSocket ws code reason`` does the closing handshake
(and waits at most ``closeTimeout`` for the peer), and ``abort`` drops the
connection.  ``receiveBefore`` is ``receive`` with a deadline.

Threads
=======

One thread at a time may receive, and any number may send, at the same time
as the receiver and as each other: a send has the right to write for its
whole message, so messages never interleave.  ``broadcast`` in the sample
sends from the thread of the person who wrote, to every connection in turn:

.. code-block:: idris

    broadcast : Room -> String -> IO ()
    broadcast room msg = do
      mutexAcquire room.lock
      ps <- readIORef room.people
      mutexRelease room.lock
      let bytes = fromString msg
      for_ (values ps) $ \(_, ws) => ignore (sendMessage ws (TextMessage bytes))

Nothing is queued: a send returns when the transport has taken all the bytes
of the message.  A peer that does not read makes its senders wait, until
``sendTimeout``, after which its connection is failed and its session ends;
memory does not grow.  (A room with many slow readers would rather give each
connection a writer thread fed by a bounded channel, so that one slow reader
does not hold up the others.)  The pongs that ``receive`` sends never wait for
a sender that a slow peer holds up: they go out after its message.
``closeWebSocket`` from another thread wakes a thread that is blocked in
``receive``; the sample does that when it stops.

Keep-alive and limits
=====================

.. code-block:: idris

    options : AcceptOptions
    options = { config := { maxMessageSize := 4096, idleTimeout := 600000, sendTimeout := 5000
                          , pingInterval := 30000 } defaultWSConfig } defaultAcceptOptions

With ``pingInterval``, ``receive`` sends a ping when nothing has come for that
long and drops the connection when nothing comes within ``pongTimeout``
after it; ``idleTimeout`` closes a connection (with 1001) that has had no
message for that long.  ``maxFrameSize`` and ``maxMessageSize`` bound what
the peer can make the program hold.  The defaults are in ``defaultWSConfig``:
16 MiB for frames and messages, 30 s per send, 5 s for the closing handshake,
no keep-alive and no idle timeout.

The client side
===============

.. code-block:: idris

    Right ws <- connectWebSocket defaultConnectOptions "ws://127.0.0.1:8080/chat?name=ann"
      | Left e => putStrLn (show e)
    ignore (sendText ws "hello")
    Right m <- receive ws
      | Left closed => putStrLn (show closed)
    putStrLn (messageString m)

``connectWebSocket`` resolves the host, connects, sends the handshake with a
random key (and the ``subprotocols`` and ``headers`` of the options), and
checks the response.  ``wss://`` URLs need the ``tlsConnect`` of the options
(see the ``tls`` library).  The frames of a client are masked with keys from
the random source of the system (``getentropy``).
