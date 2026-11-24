# TLS and HTTPS (this fork)

`tls` (module `Network.TLS`) has TLS client and server connections over the
non-blocking sockets of `Network.Socket.Async`, made with OpenSSL 3. `http-tls`
(module `Network.HTTP.TLS`) puts the HTTP server, client and WebSocket of
`http` over it. Both are this fork's, and optional: they are installed only
when the compiler was built where `pkg-config` found OpenSSL 3 with its
development files. Check with `idris2i-1 --list-packages`; a program that imports
`Network.TLS` is linked with OpenSSL by itself.

| program uses | `-p` flags | `depends =` |
|---|---|---|
| `Network.TLS` only | `-p network -p tls` | `network, tls` |
| HTTPS (`Network.HTTP.TLS`) | `-p contrib -p network -p http -p tls -p http-tls` | `contrib, network, http, tls, http-tls` |

The example below is a complete program: its imports are in the first block,
and `main = exHttps` runs it. It needs a certificate for `localhost` in the
current directory:

```sh
openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes \
  -keyout key.pem -out cert.pem -days 30 -subj /CN=localhost \
  -addext subjectAltName=DNS:localhost,IP:127.0.0.1
```

```idris
import Data.Buffer
import Data.ByteString
import Network.HTTP.Client
import Network.HTTP.Router
import Network.HTTP.TLS
import Network.TLS

%default covering
```

## Configuration

- `Network.TLS.serverConfig (credentialFiles "cert.pem" "key.pem")` gives a
  `ServerConfig` (fields `alpn`, `sniCredentials`, `clientAuth`, `minVersion`);
  `newServerContext cfg : io (Either TLSError ServerContext)` loads it.
- `Network.TLS.defaultClientConfig` verifies the peer and the host name against
  the system's authorities; `{ trust := [CAFile "cert.pem"] }` trusts a file
  instead (`CADirectory`, `CAText`, `SystemTrust`); `insecureNoVerification`
  turns verification off, for tests. `newClientContext cfg` loads it.
- The two `ServerConfig`s, `ClientConfig`s and `defaultClientConfig`s (TLS and
  HTTP) have the same names: write `Network.TLS.serverConfig`,
  `Network.HTTP.Client.defaultClientConfig` where both modules are imported.

## HTTPS server and client

`httpsServerConfig ctx cfg` turns an HTTP `ServerConfig` into one whose
connections run the TLS handshake first (within `headTimeout`; failed
handshakes are logged and counted, never fatal). The handlers are the same, and
see `req.secure`. On the client side, `httpsClientConfig clientCtx cfg` adds the
TLS connector to an HTTP `ClientConfig`; `defaultHTTPSClientConfig` does it with
the system's authorities. The host of the URL is sent with SNI and verified.

```idris
rawGet : ClientContext -> Int -> IO ()
rawGet ctx port = do
  Right s <- Network.TLS.connectHost ctx "localhost" port Nothing
    | Left e => putStrLn "connect: \{show e}"
  Just buf <- newBuffer 4096
    | Nothing => pure ()
  let req = "GET /hello HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n"
  setString buf 0 req
  Right () <- Network.TLS.sendAll s buf 0 (cast (length req)) Nothing
    | Left e => putStrLn (show e)
  Right n <- Network.TLS.recv s buf 0 4096 Nothing
    | Left e => putStrLn (show e)
  putStrLn "raw TLS (\{!(tlsVersion s)}): \{!(getString buf 0 15)}..."
  ignore (Network.TLS.close s)

exHttps : IO ()
exHttps = do
  Right sctx <- newServerContext ({ alpn := ["h2", "http/1.1"] }
                                    (Network.TLS.serverConfig (credentialFiles "cert.pem" "key.pem")))
    | Left e => putStrLn "cannot use the certificate: \{show e}"
  (cfg, stats) <- httpsServerConfig sctx (defaultServerConfig (Inet "127.0.0.1" 0))
  Right srv <- startServer cfg $ router
                 [ route GET "/hello" $ \req, _ =>
                     pure (textResponse statusOK "hello over TLS, secure=\{show req.secure}\n") ]
    | Left e => putStrLn "cannot listen: \{show e}"
  let port = addrPort (serverAddress srv)
  Right cctx <- newClientContext ({ trust := [CAFile "cert.pem"] } Network.TLS.defaultClientConfig)
    | Left e => putStrLn (show e)
  c <- newClient (httpsClientConfig cctx Network.HTTP.Client.defaultClientConfig)
  Right r <- httpGet c "https://localhost:\{show port}/hello"
    | Left e => putStrLn "GET: \{show e}"
  putStr "\{show r.status.code} \{toStringLossy r.body}"
  Right sysCfg <- defaultHTTPSClientConfig          -- the system's authorities
    | Left e => putStrLn (show e)
  c2 <- newClient sysCfg
  Left e <- httpGet c2 "https://localhost:\{show port}/hello"
    | Right _ => putStrLn "unexpected"
  putStrLn "system trust: \{show e}"             -- the self-signed certificate is rejected
  rawGet cctx port
  counts <- handshakeCounts stats
  putStrLn "handshakes: \{show counts.succeeded} ok, \{show counts.failed} failed"
  stopServer srv 1000
```

A `TLSSocket` is used like an `AsyncSocket`: `recv`, `send`, `sendAll`,
`recvExactly`, `close` (sends close_notify), `abort`, with the same buffer,
offset, length and deadline arguments, returning `Either TLSError a`.
`Network.TLS` re-exports `Network.Socket.Async`, so qualify the names that both
have (`Network.TLS.recv`). A server accepts with
`Network.Socket.Async.accept listener dl`, then runs the handshake with
`Network.TLS.accept ctx sock dl` in the connection's thread. One thread may
read while another writes; two readers or two writers at once are not
supported. `tlsVersion`, `cipherName`, `alpnSelected`, `peerCertificate`
describe the connection.

WebSocket over TLS: `wss://` URLs work with `{ tlsConnect := Just (tlsConnector
cctx) } defaultConnectOptions`.

Known gaps: Linux is the only platform it has run on; no verification
callbacks in Idris2i-1 (the policy is OpenSSL's, set by the fields above).
