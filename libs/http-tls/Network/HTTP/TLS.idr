||| HTTPS: the server and the client of the `http` library over the TLS
||| connections of the `tls` library.
|||
||| A server makes a context of the `tls` library once and gives it to
||| `httpsServerConfig`, which makes each connection run the handshake of
||| TLS in its own thread, before the first request (a client that does not
||| finish it within `headTimeout` is dropped):
|||
||| ```idris
||| import Network.HTTP.Server
||| import Network.HTTP.TLS
||| import Network.TLS
|||
||| main : IO ()
||| main = do
|||   Right ctx <- newServerContext (Network.TLS.serverConfig
|||                                    (credentialFiles "cert.pem" "key.pem"))
|||     | Left e => putStrLn (show e)
|||   (cfg, stats) <- httpsServerConfig ctx (defaultServerConfig (Inet "0.0.0.0" 8443))
|||   Right () <- serve cfg hello
|||     | Left e => putStrLn (show e)
|||   pure ()
||| ```
|||
||| A client gets a connector for `https://` URLs from a client context
||| (`httpsClientConfig`): the name of the host of the URL is sent with SNI
||| (unless it is an IP address) and the certificate of the server is
||| verified for it, as the context says.
|||
||| The protocol that the two sides agreed on with ALPN, if the contexts
||| offered some, is the `transportProtocol` of the transport.
module Network.HTTP.TLS

import Data.Buffer
import Data.IORef
import Network.HTTP.Client
import Network.HTTP.Server
import Network.HTTP.Transport
import Network.Socket.Async
import Network.TLS
import Network.TLS.Codes
import System.Concurrency

%default covering

--------------------------------------------------------------------------
-- The transport
--------------------------------------------------------------------------

-- A code of the tls library as one of the transport: minus an errno code
-- (a TLS stream that ends without close_notify, or a TLS error, is a reset
-- of the connection for HTTP).
transportCode : Int -> Int
transportCode r = if r > -1000 then r else negate econnreset

-- After the reading side was shut down, a reader that was waiting gets the
-- end of the stream (the socket gives it, which TLS takes for a stream cut
-- short).
tlsRecv : TLSSocket -> IORef Bool -> Buffer -> Int -> Int -> Int -> IO Int
tlsRecv s shut b o n d = do
  r <- recvCode s b o n d
  if r >= 0 then pure r else do
    sh <- readIORef shut
    pure (if sh then 0 else transportCode r)

tlsSendAll : TLSSocket -> Buffer -> Int -> Int -> Int -> IO Int
tlsSendAll s b o n d = do
  r <- sendAllCode s b o n d
  pure (transportCode r)

tlsSendAll2 : TLSSocket -> Buffer -> Int -> Int -> Buffer -> Int -> Int -> Int -> IO Int
tlsSendAll2 s b1 o1 n1 b2 o2 n2 d = do
  r <- sendAll2Code s b1 o1 n1 b2 o2 n2 d
  pure (transportCode r)

-- `ShutWrite` sends close_notify (waiting at most a second for the socket
-- to take it), then ends the writing side of the socket; `ShutRead` ends
-- the reading side of the socket, which wakes up a reader; `ShutBoth` ends
-- both sides of the socket at once, without close_notify (the connection
-- is being cut).
tlsShutdown : TLSSocket -> IORef Bool -> ShutdownHow -> IO ()
tlsShutdown s shut ShutWrite = do
  d <- deadlineAfterMs 1000
  ignore (closeNotifyCode s d)
  ignore (Network.Socket.Async.shutdown (socketOf s) ShutWrite)
tlsShutdown s shut how = do
  writeIORef shut True
  ignore (Network.Socket.Async.shutdown (socketOf s) how)

||| How long closing a TLS transport waits for the close_notify of the
||| peer, in milliseconds.
export
closeWaitMs : Int
closeWaitMs = 500

tlsClose : TLSSocket -> IO ()
tlsClose s = do
  d <- deadlineAfterMs closeWaitMs
  ignore (closeCodeWithin s d)

||| The transport of a TLS connection (secure, with the protocol that ALPN
||| selected as its `transportProtocol`), and the address of the peer if
||| known.
|||
||| Its errors are minus errno codes, as for a socket: a TLS stream that
||| ends without close_notify, or an error of TLS, is `-ECONNRESET`.
||| `transportShutdown` with `ShutWrite` sends close_notify, with
||| `ShutRead` or `ShutBoth` it wakes up a reader, which gets the end of the
||| stream.  `transportClose` sends close_notify if it was not sent, waits
||| `closeWaitMs` at most for the one of the peer, and closes the socket.
export
tlsTransport : TLSSocket -> (peer : Maybe SockAddr) -> IO Transport
tlsTransport s peer = do
  shut <- newIORef False
  p <- alpnSelected s
  pure (customTransportWithProtocol
          (MkTransportOps (tlsRecv s shut) (tlsSendAll s) (tlsSendAll2 s)
                          (tlsShutdown s shut) (tlsClose s) peer True)
          p)

--------------------------------------------------------------------------
-- Servers
--------------------------------------------------------------------------

||| What the handshakes of a server came to, since it started.
public export
record HandshakeCounts where
  constructor MkHandshakeCounts
  ||| Handshakes that succeeded.
  succeeded : Int
  ||| Handshakes that failed, those that timed out included.
  failed : Int
  ||| Handshakes that did not end before their deadline.
  timedOut : Int

||| Counters of handshakes, updated by the threads of the connections.
export
data HandshakeStats = MkHandshakeStats Mutex (IORef HandshakeCounts)

||| Counters at zero.
export
newHandshakeStats : IO HandshakeStats
newHandshakeStats = [| MkHandshakeStats makeMutex (newIORef (MkHandshakeCounts 0 0 0)) |]

||| The counts now.
export
handshakeCounts : HandshakeStats -> IO HandshakeCounts
handshakeCounts (MkHandshakeStats m r) = do
  mutexAcquire m
  c <- readIORef r
  mutexRelease m
  pure c

count : HandshakeStats -> (HandshakeCounts -> HandshakeCounts) -> IO ()
count (MkHandshakeStats m r) f = do
  mutexAcquire m
  modifyIORef r f
  mutexRelease m

isTimeout : TLSError -> Bool
isTimeout Timeout = True
isTimeout _ = False

||| A `makeTransport` for `ServerConfig`: the handshake of a TLS server
||| with the context on the accepted socket, which must end within
||| `handshakeMs` milliseconds (0 for no limit).  A handshake that fails is
||| counted and given up with a message (which the server writes to its
||| error log, and then closes the socket).
export
tlsMakeTransport : ServerContext -> (handshakeMs : Int) -> HandshakeStats ->
                   AsyncSocket -> SockAddr -> IO (Either String Transport)
tlsMakeTransport ctx ms stats s addr = do
  d <- deadlineAfterMs ms
  r <- Network.TLS.accept ctx s (if d < 0 then Nothing else Just d)
  case r of
    Right tls => do
      count stats { succeeded $= (+ 1) }
      Right <$> tlsTransport tls (Just addr)
    Left e => do
      let t = the Int (if isTimeout e then 1 else 0)
      count stats (\c => { failed $= (+ 1), timedOut $= (+ t) } c)
      pure (Left ("TLS handshake failed: " ++ show e))

||| A server configuration made to serve HTTPS with a TLS context: each
||| connection runs the handshake in its own thread, within the
||| `headTimeout` of the configuration (see `tlsMakeTransport`), and the
||| counters of the handshakes.  For HTTP/2 the context must offer `h2` with
||| ALPN (`alpn` of the configuration of the TLS server).
export
httpsServerConfig : ServerContext -> Network.HTTP.Server.ServerConfig ->
                    IO (Network.HTTP.Server.ServerConfig, HandshakeStats)
httpsServerConfig ctx cfg = do
  stats <- newHandshakeStats
  pure ({ makeTransport := tlsMakeTransport ctx cfg.headTimeout stats } cfg, stats)

--------------------------------------------------------------------------
-- Clients
--------------------------------------------------------------------------

||| A connector of `https://` URLs for the client: the handshake of a TLS
||| client with the context on the connected socket, for the host of the
||| URL (sent with SNI unless it is an IP address, and verified as the
||| context says).  A handshake that fails is given up with its message,
||| which the client gives as `OtherError "TLS: ..."`.
export
tlsConnector : ClientContext -> TLSConnector
tlsConnector ctx host port s d = do
  peer <- peerAddress s
  r <- Network.TLS.connect ctx host s (if d < 0 then Nothing else Just d)
  case r of
    Left e => pure (Left (show e))
    Right tls => Right <$> tlsTransport tls (either (const Nothing) Just peer)

||| A client configuration that fetches `https://` URLs with a TLS context
||| (`tlsConnector`).
export
httpsClientConfig : ClientContext -> Network.HTTP.Client.ClientConfig -> Network.HTTP.Client.ClientConfig
httpsClientConfig ctx cfg = { tlsConnect := Just (tlsConnector ctx) } cfg

||| A client configuration that fetches `https://` URLs as
||| `defaultClientConfig` of the `http` library does `http://` ones,
||| verifying servers with the certificates of the system.
export
defaultHTTPSClientConfig : IO (Either TLSError Network.HTTP.Client.ClientConfig)
defaultHTTPSClientConfig = do
  Right ctx <- newClientContext Network.TLS.defaultClientConfig
    | Left e => pure (Left e)
  pure (Right (httpsClientConfig ctx Network.HTTP.Client.defaultClientConfig))
