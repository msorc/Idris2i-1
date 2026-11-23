-- Measurements of the tls library: handshakes, and bulk transfers through
-- TLS and through plain sockets.  The server and the client are separate
-- processes, so that `perf stat` measures one side at a time (see
-- bench.sh).
--
--   bench hs-server <certs> <name> <port file> <n>   take n handshakes
--   bench hs-client <certs> <port> <n> <concurrency>
--   bench bulk-server tls|plain <certs> <port file> <MB>  send MB to one client
--   bench bulk-client tls|plain <certs> <port> <MB>
module Main

import Data.Buffer
import Data.IORef
import Data.List
import Network.Socket.Async
import Network.TLS
import System
import System.Concurrency
import System.File

listenPort : String -> IO (Maybe AsyncSocket)
listenPort portFile = do
  Right l <- listenOn (Inet "127.0.0.1" 0) 4096
    | Left e => do putStrLn "listen: \{show e}"; pure Nothing
  Right (Inet _ port) <- localAddress l
    | _ => pure Nothing
  Right () <- writeFile portFile (show port)
    | Left e => pure Nothing
  pure (Just l)

covering
hsServer : String -> String -> String -> Nat -> IO ()
hsServer certs name portFile n = do
  Right ctx <- newServerContext (serverConfig (credentialFiles (certs ++ "/" ++ name ++ ".pem") (certs ++ "/" ++ name ++ ".key")))
    | Left e => putStrLn "context: \{show e}"
  Just l <- listenPort portFile
    | Nothing => pure ()
  done <- makeUnboundedChannel
  ts <- loop ctx l done n []
  for_ ts (\_ => channelGet done)
  ignore (Network.Socket.Async.close l)
  where
    loop : ServerContext -> AsyncSocket -> Channel () -> Nat -> List () -> IO (List ())
    loop ctx l done Z acc = pure acc
    loop ctx l done (S k) acc = do
      Right sock <- Network.Socket.Async.accept l Nothing
        | Left e => do putStrLn "accept: \{show e}"; pure acc
      _ <- fork $ do
        r <- Network.TLS.accept ctx sock Nothing
        case r of
          Right s => ignore (close s)
          Left e => putStrLn "handshake: \{show e}"
        channelPut done ()
      loop ctx l done k (() :: acc)

covering
hsClient : String -> Int -> Nat -> Nat -> IO ()
hsClient certs port n conc = do
  Right ctx <- newClientContext ({ trust := [CAFile (certs ++ "/ca.pem")] } defaultClientConfig)
    | Left e => putStrLn "context: \{show e}"
  left <- newIORef n
  done <- makeUnboundedChannel
  for_ [1 .. conc] $ \_ => fork (do pure (); worker ctx left; channelPut done ())
  for_ [1 .. conc] $ \_ => channelGet done
  where
    worker : ClientContext -> IORef Nat -> IO ()
    worker ctx left = do
      k <- atomicModifyIORef left (\m => case m of Z => (Z, False); S j => (j, True))
      if not k then pure () else do
        Right s <- Network.TLS.connectHost ctx "localhost" port Nothing
          | Left e => putStrLn "connect: \{show e}"
        ignore (close s)
        worker ctx left

chunk : Int
chunk = 262144

covering
bulkServer : Bool -> String -> String -> Int -> IO ()
bulkServer tls certs portFile mb = do
  Right ctx <- newServerContext (serverConfig (credentialFiles (certs ++ "/server.pem") (certs ++ "/server.key")))
    | Left e => putStrLn "context: \{show e}"
  Just l <- listenPort portFile
    | Nothing => pure ()
  Right sock <- Network.Socket.Async.accept l Nothing
    | Left e => putStrLn "accept: \{show e}"
  Just buf <- newBuffer chunk
    | Nothing => pure ()
  let chunks = mb * 4
  if tls
    then do Right s <- Network.TLS.accept ctx sock Nothing
              | Left e => putStrLn "handshake: \{show e}"
            sendLoop (\b, n => Network.TLS.sendAllCode s b 0 n (-1)) buf chunks
            ignore (Network.TLS.close s)
    else do sendLoop (\b, n => Network.Socket.Async.sendAllCode sock b 0 n (-1)) buf chunks
            ignore (Network.Socket.Async.close sock)
  ignore (Network.Socket.Async.close l)
  where
    sendLoop : (Buffer -> Int -> IO Int) -> Buffer -> Int -> IO ()
    sendLoop snd buf k = if k <= 0 then pure () else do
      r <- snd buf chunk
      if r < 0 then putStrLn "send: \{show r}" else sendLoop snd buf (k - 1)

covering
bulkClient : Bool -> String -> Int -> Int -> IO ()
bulkClient tls certs port mb = do
  Right ctx <- newClientContext ({ trust := [CAFile (certs ++ "/ca.pem")] } defaultClientConfig)
    | Left e => putStrLn "context: \{show e}"
  Just buf <- newBuffer chunk
    | Nothing => pure ()
  if tls
    then do Right s <- Network.TLS.connectHost ctx "localhost" port Nothing
              | Left e => putStrLn "connect: \{show e}"
            n <- recvLoop (\b => Network.TLS.recvCode s b 0 chunk (-1)) buf 0
            check n
            ignore (Network.TLS.close s)
    else do Right s <- Network.Socket.Async.connectHost "127.0.0.1" port Nothing
              | Left e => putStrLn "connect: \{show e}"
            n <- recvLoop (\b => Network.Socket.Async.recvCode s b 0 chunk (-1)) buf 0
            check n
            ignore (Network.Socket.Async.close s)
  where
    recvLoop : (Buffer -> IO Int) -> Buffer -> Int -> IO Int
    recvLoop rcv buf got = do
      r <- rcv buf
      if r <= 0 then pure got else recvLoop rcv buf (got + r)
    check : Int -> IO ()
    check n = when (n /= mb * 1048576) $ putStrLn "received \{show n} bytes"

covering
main : IO ()
main = do
  args <- getArgs
  case drop 1 args of
    ["hs-server", certs, name, pf, n] => hsServer certs name pf (cast n)
    ["hs-client", certs, port, n, c] => hsClient certs (cast port) (cast n) (cast c)
    ["bulk-server", kind, certs, pf, mb] => bulkServer (kind == "tls") certs pf (cast mb)
    ["bulk-client", kind, certs, port, mb] => bulkClient (kind == "tls") certs (cast port) (cast mb)
    _ => putStrLn "usage: see Bench.idr"
