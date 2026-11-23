# HTTP: server, router, client, WebSocket (this fork)

The `http` library is this fork's (upstream 0.8 has no HTTP library): an
HTTP/1.1 and HTTP/2 server and client, a router with JSON helpers, and
WebSocket, on the non-blocking sockets of `network`. Build with

```sh
idris2 -p contrib -p network -p http Main.idr -o app
```

or `depends = contrib, network, http` in the `.ipkg`. All three `-p` flags are
needed: `-p` does not load the packages a package depends on, and `-p http`
alone fails with "Module Network.Socket.Async not found".

On RefC (the default backend) each connection is a green thread; on Chez and
Racket an OS thread. Not on the JavaScript backends; on Windows the sockets are
stubs that fail.

Every example below is a complete program: its imports are in the first block,
and `main = exService` (or another example) runs it. They start a server on
`127.0.0.1` port 0 (the system picks a free port), talk to it with the client,
and stop it, so they need no `curl`.

```idris
import Data.ByteString
import Data.IORef
import Data.Maybe
import Data.SortedMap
import Data.String
import Language.JSON.Derive
import Network.HTTP.Client
import Network.HTTP.Router
import Network.WebSocket
import System
import System.Signal

%language ElabReflection
%default covering
```

`%default covering` saves writing `covering` on every function: most of the
library is `covering`, so a `total` function cannot call it.

## The modules

| module | has |
|---|---|
| `Network.HTTP.Server` | `startServer`, `waitServer`, `stopServer srv graceMs`, `serve`; `Request` (fields `method`, `path`, `query`, `headers`, `body`, `remote`), `Response`; `textResponse`, `bytesResponse`, `emptyResponse`, `statusResponse`, `withHeader`; `requestBody`; `ServerConfig`, `defaultServerConfig addr` |
| `Network.HTTP.Router` | re-exports the server; `route METHOD "/pattern/:id/*rest" handler`, `router : List Route -> Handler` (404, 405 with `Allow`, `HEAD` by the `GET` route); `param`, `queryParam`, `queryParams`; `jsonBody`, `jsonResponse`, `jsonError` |
| `Network.HTTP.Client` | `newClient defaultClientConfig`, `httpGet`, `httpPost`, `fetch`, `withResponse` (streamed body); `Reply` (`status`, `headers`, `body`) |
| `Network.HTTP.Types` | `Method` (`GET`, `POST`, ...), `Status` (`statusOK`, `statusCreated`, `statusNotFound`, `statusBadRequest`, ..., `.code`), `Headers` (`emptyHeaders`, `addHeader`, `lookupHeader`, case-insensitive) |
| `Network.WebSocket` | `websocketRoute`, `acceptWebSocket`, `connectWebSocket`, `receive`, `sendText`, `sendBinary`, `closeWebSocket` |
| `Network.URI` | `parseURI`, percent-encoding |

Paths, header names and values, and bodies are `ByteString`s (`toStringLossy`
to print one; string literals work as `ByteString`s). A `case` on a
`ByteString` literal is rejected (it is not a constructor): compare with `==`,
or use the router. A handler is `Request -> IO Response` (`Handler`), a route
handler `Request -> Params -> IO Response`; neither can throw. A crash in a
handler (a missing case, `idris_crash`, an index out of a `Buffer`) ends only
that request with a 500: the server runs every handler in a crash boundary (see
`System.Crash` in `concurrency.md` for what that leaks).

## A JSON service

```idris
record Item where
  constructor MkItem
  id : Int
  name : String
  qty : Int

record NewItem where
  constructor MkNewItem
  name : String
  qty : Maybe Int

%hint itemTo : ToJSON Item
itemTo = %runElab deriveToJSON defaultOptions
%hint newItemFrom : FromJSON NewItem
newItemFrom = %runElab deriveFromJSON defaultOptions

record Store where
  constructor MkStore
  items : SortedMap Int Item
  next : Int

idParam : Params -> Maybe Int
idParam ps = param "id" ps >>= parseInteger

routes : IORef Store -> List Route
routes store =
  [ route GET "/health" $ \_, _ => pure (textResponse statusOK "ok\n")
  , route GET "/items" $ \_, _ => do
      s <- readIORef store
      pure (jsonResponse statusOK (values s.items))
  , route GET "/items/:id" $ \_, ps => do
      s <- readIORef store
      pure $ case idParam ps >>= \i => lookup i s.items of
        Just it => jsonResponse statusOK it
        Nothing => jsonError statusNotFound "no such item"
  , route POST "/items" $ \req, _ => do
      Right new <- jsonBody {a = NewItem} req     -- 400 with the reason, or 413
        | Left bad => pure bad
      -- Handlers run in parallel: change shared state atomically.
      it <- atomicModifyIORef store $ \s =>
              let it = MkItem s.next new.name (fromMaybe 1 new.qty) in
              ({ items $= insert it.id it, next $= (+ 1) } s, it)
      pure (withHeader "Location" (fromString "/items/\{show it.id}")
              (jsonResponse statusCreated it))
  ]

show1 : Client -> String -> Method -> String -> RequestBody -> IO ()
show1 c base m path body = do
  Right r <- fetch c m (base ++ path) (addHeader "Content-Type" "application/json" emptyHeaders) body
    | Left e => putStrLn "\{show m} \{path}: \{show e}"
  putStrLn "\{show m} \{path} -> \{show r.status.code} \{toStringLossy r.body}"

exService : IO ()
exService = do
  store <- newIORef (MkStore empty 1)
  Right srv <- startServer (defaultServerConfig (Inet "127.0.0.1" 0)) (router (routes store))
    | Left e => putStrLn "cannot listen: \{show e}"
  let base = "http://\{show (serverAddress srv)}"
  c <- newClient defaultClientConfig
  show1 c base POST "/items" (RequestBytes "{\"name\": \"apple\", \"qty\": 3}")
  show1 c base POST "/items" (RequestBytes "{\"name\": \"pear\"}")
  show1 c base POST "/items" (RequestBytes "{\"qty\": 3}")
  show1 c base GET "/items" NoRequestBody
  show1 c base GET "/items/2" NoRequestBody
  show1 c base GET "/items/9" NoRequestBody
  show1 c base DELETE "/items/1" NoRequestBody
  show1 c base GET "/nowhere" NoRequestBody
  stopServer srv 1000
```

Output (the 404 and 405 of the router are plain text, with `Allow` for 405):

```text
POST /items -> 201 {"id":1,"name":"apple","qty":3}
POST /items -> 201 {"id":2,"name":"pear","qty":1}
POST /items -> 400 {"error":"missing member","path":"$.name"}
GET /items -> 200 [{"id":1,"name":"apple","qty":3},{"id":2,"name":"pear","qty":1}]
GET /items/2 -> 200 {"id":2,"name":"pear","qty":1}
GET /items/9 -> 404 {"error":"no such item"}
DELETE /items/1 -> 405 405 Method Not Allowed
GET /nowhere -> 404 404 Not Found
```

## Serving until Ctrl-C

`startServer` returns at once; the accept loop and the connections run in their
own threads. `waitServer` blocks until the server stops. `stopServer srv ms`
stops accepting and lets requests in progress finish for up to `ms`
milliseconds. Signals are polled with `System.Signal`:

```idris
stopOnInterrupt : Server -> IO ()
stopOnInterrupt srv = do
  Just SigINT <- handleNextCollectedSignal
    | _ => do usleep 100000; stopOnInterrupt srv
  stopServer srv 5000

serveForever : Int -> IO ()
serveForever port = do
  store <- newIORef (MkStore empty 1)
  let cfg = { accessLog := Just (\e => putStrLn "\{show e.method} \{toStringLossy e.target} \{show e.status}")
            , maxBodySize := 1000000 }
            (defaultServerConfig (Inet "127.0.0.1" port))
  Right srv <- startServer cfg (router (routes store))
    | Left e => die "cannot listen on \{show port}: \{show e}"
  putStrLn "listening on \{show (serverAddress srv)}"
  Right () <- collectSignal SigINT
    | Left _ => putStrLn "cannot catch SIGINT"
  _ <- fork (stopOnInterrupt srv)
  waitServer srv
```

`ServerConfig` also has `maxConnections`, `headTimeout`, `bodyTimeout`,
`idleTimeout`, `writeTimeout` (milliseconds), `errorLog`, `http2` (an
`H2Config`). HTTP/2 is served to clients that ask for it (`h2c` prior
knowledge; `h2` over TLS with ALPN), with the same handlers. Use
`IDRIS2_WORKERS=1` rather than a build with `-DIDRIS2_SINGLE_WORKER`, which has
no preemption.

A request body: `requestBody req : IO (Either HttpError ByteString)` reads it
whole (up to `maxBodySize`), `readChunk req.body` a piece at a time. A response
body: `BytesBody`, `BuilderBody`, or `StreamBody (Maybe length) writer` for one
written in pieces (`respond status headers body` builds the `Response`).

## The client

```idris
hello : Handler
hello req = pure (textResponse statusOK "\{show req.method} \{toStringLossy req.path}\n")

exClient : IO ()
exClient = do
  Right srv <- startServer (defaultServerConfig (Inet "127.0.0.1" 0)) hello
    | Left e => putStrLn (show e)
  let url = "http://\{show (serverAddress srv)}/hello"
  c <- newClient ({ requestTimeout := 5000 } defaultClientConfig)
  Right r <- httpGet c url
    | Left e => putStrLn "GET failed: \{show e}"
  putStrLn "\{show r.status.code} \{show (lookupHeader "content-type" r.headers)}"
  putStr (toStringLossy r.body)
  Right r2 <- httpPost c url "application/json" "{\"a\":1}"
    | Left e => putStrLn (show e)
  printLn r2.status.code
  Left e <- httpGet c "http://127.0.0.1:1/"
    | Right _ => putStrLn "unexpected"
  putStrLn "refused: \{show e}"
  stopServer srv 1000
```

A `Client` keeps a pool of persistent connections per host, follows up to
`maxRedirects` redirects and bounds each request by `requestTimeout`
(milliseconds). `fetch c method url headers body` is the general form
(`NoRequestBody`, `RequestBytes bs`, `RequestStream`). `https://` needs a TLS
connector from `http-tls` (see `tls.md`); without it the request fails with a
message that names the missing transport. No cookies, proxies or compression.

## WebSocket

`websocketRoute "/path" options session` makes a route that checks the
handshake (answering 4xx itself) and runs `session req params ws` in the thread
of the connection; the connection closes when it returns. `receive ws : IO
(Either CloseInfo Message)` gives whole messages (`TextMessage bytes`,
`BinaryMessage bytes`; `messageString` for text) and answers pings itself; a
`Left` means the connection ended. Only one thread at a time may `receive`; any
number may `sendText`/`sendMessage`.

```idris
session : Request -> Params -> WebSocket -> IO ()
session req _ ws = do
  let who = fromMaybe "someone" (queryParam "name" req)
  ignore (sendText ws "hello \{who}")
  loop
  where
    loop : IO ()
    loop = do
      Right msg <- receive ws
        | Left closed => pure ()            -- peer closed or connection failed
      ignore (sendText ws ("echo: " ++ messageString msg))
      loop

exWebSocket : IO ()
exWebSocket = do
  let opts = { config := { maxMessageSize := 65536 } defaultWSConfig } defaultAcceptOptions
  Right srv <- startServer (defaultServerConfig (Inet "127.0.0.1" 0))
                 (router [websocketRoute "/ws" opts session])
    | Left e => putStrLn (show e)
  Right ws <- connectWebSocket defaultConnectOptions "ws://\{show (serverAddress srv)}/ws?name=ann"
    | Left e => putStrLn "connect: \{show e}"
  for_ ["one", "two"] $ \t => ignore (sendText ws t)
  for_ [1, 2, 3] $ \_ => do
    Right m <- receive ws
      | Left closed => putStrLn "closed: \{show closed.code}"
    putStrLn (messageString m)
  info <- closeWebSocket ws 1000 "bye"
  printLn info.code
  stopServer srv 1000
```

`wss://` URLs need the `tlsConnect` of `ConnectOptions` (from `http-tls`).
`AcceptOptions` has `subprotocols` and `checkOrigin`; `WSConfig` has
`pingInterval`, `pongTimeout`, `idleTimeout`, `sendTimeout` (milliseconds) and
the size limits. No `permessage-deflate`, no WebSocket over HTTP/2.
