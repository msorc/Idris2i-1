-- A TLS echo server and its clients, green threads of one program on
-- loopback: the handshake, round trips, what both sides see of the
-- connection (version, SNI, the certificate of the server), and the end of
-- the stream after close_notify.
import Data.Buffer
import Data.List
import Data.Maybe
import Data.String
import Network.Socket.Async
import Network.TLS
import System
import System.Concurrency

clients : Nat
clients = 8

-- Echo until the end of the TLS stream; report what the server saw of the
-- first connection.
covering
echo : TLSSocket -> Buffer -> IO ()
echo s buf = do
  n <- recvCode s buf 0 256 (-1)
  if n <= 0
     then do when (n < 0) $ putStrLn "server: \{show !(codeError s n)}"
             ignore (close s)
     else do r <- sendAllCode s buf 0 n (-1)
             if r < 0 then ignore (close s) else echo s buf

covering
acceptLoop : ServerContext -> AsyncSocket -> Channel (Maybe String) -> IO ()
acceptLoop ctx l names = do
  Right sock <- Network.Socket.Async.accept l Nothing
    | Left Closed => pure ()
    | Left e => putStrLn "accept: \{show e}"
  _ <- fork $ do
    Right s <- Network.TLS.accept ctx sock Nothing
      | Left e => putStrLn "server handshake: \{show e}"
    name <- serverName s
    channelPut names name
    Just buf <- newBuffer 256
      | Nothing => putStrLn "newBuffer"
    echo s buf
  acceptLoop ctx l names

covering
client : ClientContext -> SockAddr -> Nat -> IO (Maybe String)
client ctx addr i = do
  Right sock <- Network.Socket.Async.connect addr Nothing
    | Left e => pure (Just "connect: \{show e}")
  Right s <- Network.TLS.connect ctx "localhost" sock Nothing
    | Left e => pure (Just "client handshake: \{show e}")
  Just out <- newBuffer 64
    | Nothing => pure (Just "newBuffer")
  Just back <- newBuffer 64
    | Nothing => pure (Just "newBuffer")
  r <- trips s out back 5
  ignore (close s)
  pure r
  where
    trips : TLSSocket -> Buffer -> Buffer -> Nat -> IO (Maybe String)
    trips s out back Z = pure Nothing
    trips s out back (S k) = do
      let msg = "client \{show i} round trip \{show k}"
          len = cast (length msg)
      setString out 0 msg
      Right () <- sendAll s out 0 len Nothing
        | Left e => pure (Just "send: \{show e}")
      Right n <- recvExactly s back 0 len Nothing
        | Left e => pure (Just "recv: \{show e}")
      got <- getString back 0 n
      if got == msg then trips s out back k
         else pure (Just "sent \{show msg}, got \{show got}")

covering
main : IO ()
main = do
  [_, certs] <- getArgs
    | _ => putStrLn "usage: main <certs>"
  Right sctx <- newServerContext (serverConfig (credentialFiles (certs ++ "/server.pem") (certs ++ "/server.key")))
    | Left e => putStrLn "server context: \{show e}"
  Right cctx <- newClientContext ({ trust := [CAFile (certs ++ "/ca.pem")] } defaultClientConfig)
    | Left e => putStrLn "client context: \{show e}"
  Right l <- listenOn (Inet "127.0.0.1" 0) 128
    | Left e => putStrLn "listen: \{show e}"
  Right addr <- localAddress l
    | Left e => putStrLn "localAddress: \{show e}"
  names <- makeUnboundedChannel
  server <- fork (acceptLoop sctx l names)

  -- one connection, looked at closely
  Right sock <- Network.Socket.Async.connect addr Nothing
    | Left e => putStrLn "connect: \{show e}"
  Right s <- Network.TLS.connect cctx "localhost" sock Nothing
    | Left e => putStrLn "handshake: \{show e}"
  putStrLn "version: \{!(tlsVersion s)}"
  putStrLn "cipher known: \{show (!(cipherName s) /= "")}"
  putStrLn "ALPN: \{show !(alpnSelected s)}"
  putStrLn "SNI sent by the client: \{show !(serverName s)}"
  Just cert <- peerCertificate s
    | Nothing => putStrLn "no certificate"
  putStrLn "server subject: \{cert.subject}"
  putStrLn "server issuer: \{cert.issuer}"
  putStrLn "server names: \{show cert.altNames}"
  putStrLn "valid from a date: \{show (isPrefixOf "20" cert.notBefore)}"
  name <- channelGet names
  putStrLn "SNI seen by the server: \{show name}"
  Just buf <- newBuffer 64
    | Nothing => putStrLn "newBuffer"
  setString buf 0 "hello"
  Right () <- sendAll s buf 0 5 Nothing
    | Left e => putStrLn "send: \{show e}"
  Right n <- recvExactly s buf 0 5 Nothing
    | Left e => putStrLn "recv: \{show e}"
  putStrLn "echo: \{!(getString buf 0 n)}"
  Right () <- close s
    | Left e => putStrLn "close: \{show e}"
  r <- recvCode s buf 0 5 (-1)
  putStrLn "recv after close: \{show !(codeError s r)}"

  -- several clients at once
  results <- makeChannel
  ts <- for [1 .. clients] $ \i =>
          fork (do pure (); client cctx addr i >>= channelPut results)
  errs <- for [1 .. clients] $ \_ => channelGet results
  for_ ts (\t => threadWait t)
  for_ errs (\e => maybe (pure ()) putStrLn e)
  let good : Nat = length (filter isNothing errs)
  putStrLn "\{show good} of \{show clients} clients echoed"
  -- (the accept loop ends on RefC, where closing the socket wakes it up;
  -- the program ends without waiting for it)
  ignore (Network.Socket.Async.close l)
