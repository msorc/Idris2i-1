-- A few TLS connections under Valgrind: handshakes, data both ways, ALPN,
-- a client certificate, a verification failure, a clean close, a dropped
-- connection that only the collector frees, and contexts freed by the
-- collector.  Valgrind must find no memory errors and no leaks.
import Data.Buffer
import Network.Socket.Async
import Network.TLS
import System
import System.Concurrency
import Data.IORef

covering
serve : IORef Nat -> ServerContext -> AsyncSocket -> Nat -> IO ()
serve failed ctx l Z = pure ()
serve failed ctx l (S k) = do
  Right sock <- Network.Socket.Async.accept l Nothing
    | Left e => putStrLn "accept: \{show e}"
  r <- Network.TLS.accept ctx sock Nothing
  case r of
    Left e => modifyIORef failed S
    Right s => do
      Just buf <- newBuffer 64
        | Nothing => putStrLn "newBuffer"
      n <- recvCode s buf 0 64 (-1)
      when (n > 0) $ ignore (sendAllCode s buf 0 n (-1))
      ignore (close s)
  serve failed ctx l k

covering
talk : ClientContext -> SockAddr -> (keep : Bool) -> IO (Maybe TLSSocket)
talk ctx addr keep = do
  Right sock <- Network.Socket.Async.connect addr Nothing
    | Left e => do putStrLn "connect: \{show e}"; pure Nothing
  Right s <- Network.TLS.connect ctx "localhost" sock Nothing
    | Left e => do putStrLn "client: \{show e}"; pure Nothing
  Just buf <- newBuffer 64
    | Nothing => pure Nothing
  setString buf 0 "ping"
  ignore (sendAllCode s buf 0 4 (-1))
  n <- recvCode s buf 0 64 (-1)
  putStrLn "client: \{!(getString buf 0 (max 0 n))}, ALPN \{show !(alpnSelected s)}, peer \{show (map subject !(peerCertificate s))}"
  if keep then pure (Just s) else do
    ignore (close s)
    pure Nothing

covering
main : IO ()
main = do
  [_, certs] <- getArgs
    | _ => putStrLn "usage: main <certs>"
  Right sctx <- newServerContext ({ alpn := ["h2"], clientAuth := OptionalClientCertificate,
                                    clientTrust := [CAFile (certs ++ "/ca.pem")] }
                                    (serverConfig (credentialFiles (certs ++ "/chain.pem") (certs ++ "/server.key"))))
    | Left e => putStrLn "server context: \{show e}"
  Right cctx <- newClientContext ({ trust := [CAFile (certs ++ "/ca.pem")], alpn := ["h2"],
                                    certificate := Just (credentialFiles (certs ++ "/client.pem") (certs ++ "/client.key")) }
                                    defaultClientConfig)
    | Left e => putStrLn "client context: \{show e}"
  Right strict <- newClientContext defaultClientConfig
    | Left e => putStrLn "client context: \{show e}"
  Left e <- newServerContext (serverConfig (credentialFiles (certs ++ "/missing.pem") (certs ++ "/server.key")))
    | Right _ => putStrLn "a context without a certificate"
  Right l <- listenOn (Inet "127.0.0.1" 0) 8
    | Left e => putStrLn "listen: \{show e}"
  Right addr <- localAddress l
    | Left e => putStrLn "localAddress: \{show e}"
  failed <- newIORef 0
  server <- fork (serve failed sctx l 4)
  ignore (talk cctx addr False)
  ignore (talk strict addr False)
  -- (dropped without close: its socket is closed here, its TLS session by
  -- the collector)
  Just kept <- talk cctx addr True
    | Nothing => pure ()
  ignore (Network.Socket.Async.close (socketOf kept))
  ignore (talk cctx addr False)
  threadWait server
  ignore (Network.Socket.Async.close l)
  putStrLn "failed handshakes of the server: \{show !(readIORef failed)}"
