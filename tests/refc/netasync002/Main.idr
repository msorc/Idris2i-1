-- Non-blocking sockets: deadlines, a peer that closes, a socket closed
-- while a thread waits for it, options, IPv6, datagrams, names, and a write
-- of the blocking API to a closed peer (which must not raise SIGPIPE).
import Data.Buffer
import Data.List
import Network.Socket
import Network.Socket.Async
import Network.Socket.DNS
import System
import System.Concurrency

orDie : Show e => String -> IO (Either e a) -> IO a
orDie what act = do
  Right x <- act
    | Left e => do putStrLn "\{what}: \{show e}"; exitFailure
  pure x

newBuf : Int -> IO Buffer
newBuf n = do
  Just b <- newBuffer n
    | Nothing => do putStrLn "newBuffer"; exitFailure
  pure b

-- A connected pair: (client, server side).
covering
pair : AsyncSocket -> IO (AsyncSocket, AsyncSocket)
pair l = do
  addr <- orDie "localAddress" (localAddress l)
  c <- orDie "connect" (connect addr Nothing)
  s <- orDie "accept" (accept l Nothing)
  pure (c, s)

covering
deadlines : AsyncSocket -> IO ()
deadlines l = do
  -- nobody connects
  d <- deadlineIn 50000000
  r <- accept l (Just d)
  putStrLn "accept with nobody connecting: \{either show (const "accepted") r}"
  -- a silent peer
  (c, s) <- pair l
  buf <- newBuf 16
  d <- deadlineIn 50000000
  r <- recv c buf 0 16 (Just d)
  putStrLn "recv from a silent peer: \{either show show r}"
  -- a deadline in the past fails at once, even with nothing to wait for
  r <- recvCode c buf 0 16 0
  putStrLn "recv with a past deadline: \{show (codeError r)}"
  ignore (close c)
  ignore (close s)

-- Connect to a listener whose queue is full: the system drops the
-- connection requests, so one of them times out.
covering
fullBacklog : IO ()
fullBacklog = do
  l <- orDie "listen" (listenOn (Inet "127.0.0.1" 0) 0)
  addr <- orDie "localAddress" (localAddress l)
  r <- tryConnect addr 0 []
  putStrLn "connect to a full queue: \{r}"
  ignore (close l)
  where
    tryConnect : SockAddr -> Nat -> List AsyncSocket -> IO String
    tryConnect addr n held
        = if n >= 64 then do traverse_ close held; pure "never timed out"
          else do
            d <- deadlineIn 100000000
            Right s <- connect addr (Just d)
              | Left Timeout => do traverse_ close held; pure "timed out"
              | Left e => do traverse_ close held; pure (show e)
            tryConnect addr (S n) (s :: held)

covering
peerCloses : AsyncSocket -> IO ()
peerCloses l = do
  (c, s) <- pair l
  buf <- newBuf 16
  setString buf 0 "abc"
  orDie "sendAll" (sendAll s buf 0 3 Nothing)
  ignore (close s)
  n <- orDie "recvExactly" (recvExactly c buf 0 10 Nothing)
  putStrLn "recvExactly 10 from a peer that sent 3 and closed: \{show n}"
  n <- orDie "recv" (recv c buf 0 10 Nothing)
  putStrLn "recv after that: \{show n}"
  ignore (close c)

-- Write to a peer that closed until the system says so.
covering
writeAfterClose : AsyncSocket -> IO ()
writeAfterClose l = do
  (c, s) <- pair l
  ignore (close s)
  buf <- newBuf 4096
  r <- go c buf (the Nat 1000)
  putStrLn "send to a closed peer: \{r}"
  ignore (close c)
  where
    go : AsyncSocket -> Buffer -> Nat -> IO String
    go c buf Z = pure "never failed"
    go c buf (S k) = do
      Right _ <- send c buf 0 4096 Nothing
        | Left e => pure (if isPeerGone e then "peer gone" else show e)
      usleep 1000
      go c buf k

covering
closeWhileWaiting : AsyncSocket -> IO ()
closeWhileWaiting l = do
  (c, s) <- pair l
  result <- makeChannel
  t <- fork $ do buf <- newBuf 16
                 r <- recv c buf 0 16 Nothing
                 channelPut result (either show show r)
  usleep 50000
  ignore (close c)
  r <- channelGet result
  threadWait t
  putStrLn "recv of a socket that another thread closed: \{r}"
  ignore (close s)

showOpt : AsyncSocket -> SockOption -> Int -> IO String
showOpt s opt v = do
  Right () <- setOption s opt v
    | Left e => pure (show e)
  Right v' <- getOption s opt
    | Left e => pure (show e)
  pure (show v')

covering
options : IO ()
options = do
  s <- orDie "socket" (socket IPv4 StreamSocket)
  putStrLn "NoDelay 1: \{!(showOpt s NoDelay 1)}"
  putStrLn "NoDelay 0: \{!(showOpt s NoDelay 0)}"
  putStrLn "KeepAlive 1: \{!(showOpt s KeepAlive 1)}"
  putStrLn "ReuseAddr 1: \{!(showOpt s ReuseAddr 1)}"
  putStrLn "ReusePort 1: \{!(showOpt s ReusePort 1)}"
  putStrLn "Linger 5: \{!(showOpt s Linger 5)}"
  putStrLn "Linger -1: \{!(showOpt s Linger (-1))}"
  orDie "RecvBuffer" (setOption s RecvBuffer 65536)
  v <- orDie "RecvBuffer" (getOption s RecvBuffer)
  putStrLn "RecvBuffer 65536: at least 65536: \{show (v >= 65536)}"
  ignore (close s)

covering
ipv6 : IO ()
ipv6 = do
  Right l <- listenOn (Inet6 "::1" 0) 16
    | Left _ => putStrLn "IPv6 loopback: ok" -- (no IPv6 here)
  (c, s) <- pair l
  buf <- newBuf 8
  setString buf 0 "six"
  orDie "sendAll" (sendAll c buf 0 3 Nothing)
  n <- orDie "recvExactly" (recvExactly s buf 0 3 Nothing)
  got <- getString buf 0 n
  Right (Inet6 h _) <- peerAddress s
    | other => putStrLn "IPv6 peer: \{either show show other}"
  v6only <- orDie "V6Only" (getOption l V6Only)
  putStrLn (if got == "six" && h == "::1" then "IPv6 loopback: ok" else "IPv6: got \{got} from \{h}")
  traverse_ close [c, s, l]

covering
datagrams : IO ()
datagrams = do
  a <- orDie "socket" (socket IPv4 DatagramSocket)
  b <- orDie "socket" (socket IPv4 DatagramSocket)
  orDie "bind" (bind a (Inet "127.0.0.1" 0))
  orDie "bind" (bind b (Inet "127.0.0.1" 0))
  aAddr <- orDie "localAddress" (localAddress a)
  bAddr <- orDie "localAddress" (localAddress b)
  buf <- newBuf 32
  setString buf 0 "hello"
  n <- orDie "sendTo" (sendTo a buf 0 5 bAddr Nothing)
  d <- deadlineIn 1000000000
  (m, from) <- orDie "recvFrom" (recvFrom b buf 8 24 (Just d))
  got <- getString buf 8 m
  putStrLn "datagram: \{got}, from the sender: \{show (from == aAddr)}"
  d <- deadlineIn 20000000
  r <- recvFrom b buf 0 24 (Just d)
  putStrLn "recvFrom with nothing sent: \{either show (const "received") r}"
  traverse_ close [a, b]

dns : IO ()
dns = do
  r <- resolve "localhost" 80 Nothing
  putStrLn $ case r of
    Right as => "localhost: \{show (any isLoopback as && all ((== 80) . addrPort) as)}"
    Left msg => "localhost: \{msg}"
  r <- resolve "127.0.0.1" 8080 Nothing
  putStrLn "127.0.0.1: \{either id show r}"
  r <- resolve "no-such-host.invalid" 80 Nothing
  putStrLn $ case r of
    Right as => "no-such-host.invalid resolved: \{show as}"
    Left msg => "no-such-host.invalid: failed, with a message: \{show (msg /= "")}"
  r <- connectHost "no-such-host.invalid" 80 Nothing
  putStrLn $ case r of
    Left (ResolveError _) => "connectHost to it: ResolveError"
    Left e => "connectHost to it: \{show e}"
    Right _ => "connectHost to it: connected"
  where
    isLoopback : SockAddr -> Bool
    isLoopback (Inet "127.0.0.1" _) = True
    isLoopback (Inet6 "::1" _) = True
    isLoopback _ = False

-- The blocking API: a write to a peer that closed fails with an error.
covering
blockingSigpipe : AsyncSocket -> IO ()
blockingSigpipe l = do
  Inet _ port <- orDie "localAddress" (localAddress l)
    | _ => putStrLn "not IPv4"
  Right c <- Network.Socket.socket AF_INET Stream 0
    | Left e => putStrLn "socket: \{show e}"
  0 <- Network.Socket.connect c (IPv4Addr 127 0 0 1) port
    | e => putStrLn "connect: \{show e}"
  s <- orDie "accept" (accept l Nothing)
  ignore (close s)
  r <- go c (the Nat 1000)
  putStrLn "blocking send to a closed peer: \{r}"
  Network.Socket.close c
  where
    go : Socket -> Nat -> IO String
    go c Z = pure "never failed"
    go c (S k) = do
      Right _ <- Network.Socket.send c "0123456789"
        | Left _ => pure "failed"
      usleep 1000
      go c k

covering
main : IO ()
main = do
  l <- orDie "listen" (listenOn (Inet "127.0.0.1" 0) 64)
  deadlines l
  fullBacklog
  peerCloses l
  writeAfterClose l
  closeWhileWaiting l
  blockingSigpipe l
  options
  ipv6
  datagrams
  dns
  ignore (close l)
  putStrLn "done"
