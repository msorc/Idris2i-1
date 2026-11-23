-- 16 MB through a TLS connection each way at the same time, with small
-- send buffers so that writes are partial and reads and writes wait
-- often: on each side one green thread writes while another reads the
-- same connection.  Both sides compare checksums of what was sent and
-- what came.  The client writes pairs of ranges (sendAll2Code).
import Data.Buffer
import Data.Maybe
import Network.Socket.Async
import Network.TLS
import System
import System.Concurrency

chunk : Int
chunk = 65536

chunks : Int
chunks = 256 -- 16 MB

-- The words of chunk `k` that `side` sends.
fill : Bits64 -> Buffer -> Int -> IO ()
fill side buf k = go 0
  where
    go : Int -> IO ()
    go i = if i >= chunk then pure () else do
             setBits64 buf i ((cast (k * chunk + i) + side) * 0x9E3779B97F4A7C15)
             go (i + 8)

-- The checksum of a chunk, after `acc`.
sumChunk : Buffer -> Bits64 -> IO Bits64
sumChunk buf acc = go 0 acc
  where
    go : Int -> Bits64 -> IO Bits64
    go i a = if i >= chunk then pure a else do
               w <- getBits64 buf i
               go (i + 8) (a * 31 + w)

-- Send every chunk, one range at a time or two halves with sendAll2Code:
-- the checksum of what was sent, or the error code.
covering
sender : TLSSocket -> Bits64 -> (pairs : Bool) -> IO (Either Int Bits64)
sender s side pairs = do
  Just buf <- newBuffer chunk
    | Nothing => pure (Left 0)
  Just buf2 <- newBuffer chunk
    | Nothing => pure (Left 0)
  go buf buf2 0 0
  where
    go : Buffer -> Buffer -> Int -> Bits64 -> IO (Either Int Bits64)
    go buf buf2 k acc
        = if k >= chunks then pure (Right acc) else do
            fill side buf k
            acc' <- sumChunk buf acc
            r <- if pairs
                   then do copyData buf (chunk `div` 2) (chunk `div` 2) buf2 0
                           sendAll2Code s buf 0 (chunk `div` 2) buf2 0 (chunk `div` 2) (-1)
                   else sendAllCode s buf 0 chunk (-1)
            if r < 0 then pure (Left r) else go buf buf2 (k + 1) acc'

-- Receive every chunk: the checksum of what came, or the error code.
covering
receiver : TLSSocket -> IO (Either Int Bits64)
receiver s = do
  Just buf <- newBuffer chunk
    | Nothing => pure (Left 0)
  go buf 0 0
  where
    go : Buffer -> Int -> Bits64 -> IO (Either Int Bits64)
    go buf k acc
        = if k >= chunks then pure (Right acc) else do
            r <- recvExactlyCode s buf 0 chunk (-1)
            if r /= chunk then pure (Left r) else do
              acc' <- sumChunk buf acc
              go buf (k + 1) acc'

-- Run a sender and a receiver on the connection at the same time.
covering
both : TLSSocket -> Bits64 -> Bool -> IO (Either Int Bits64, Either Int Bits64)
both s side pairs = do
  ch <- makeChannel
  t <- fork (do pure (); receiver s >>= channelPut ch)
  sent <- sender s side pairs
  got <- channelGet ch
  threadWait t
  pure (sent, got)

-- (a small receive buffer would make TCP on loopback, whose segments are
-- 64 kB, stall: the window would stay below one segment)
smallBuffers : AsyncSocket -> IO ()
smallBuffers sock = ignore (setOption sock SendBuffer 8192)

-- What a side reports: the checksum that it computed of what it sent, and
-- of what it got.
report : String -> TLSSocket -> (Either Int Bits64, Either Int Bits64) -> IO (Maybe Bits64, Maybe Bits64)
report who s (sent, got) = do
  case sent of
    Left e => putStrLn "\{who} send: \{show !(codeError s e)}"
    Right _ => pure ()
  case got of
    Left e => if e >= 0 then putStrLn "\{who} recv: only part of the data"
                else putStrLn "\{who} recv: \{show !(codeError s e)}"
    Right _ => pure ()
  pure (either (const Nothing) Just sent, either (const Nothing) Just got)

covering
main : IO ()
main = do
  [_, certs] <- getArgs
    | _ => putStrLn "usage: main <certs>"
  Right sctx <- newServerContext (serverConfig (credentialFiles (certs ++ "/server.pem") (certs ++ "/server.key")))
    | Left e => putStrLn "server context: \{show e}"
  Right cctx <- newClientContext ({ trust := [CAFile (certs ++ "/ca.pem")] } defaultClientConfig)
    | Left e => putStrLn "client context: \{show e}"
  Right l <- listenOn (Inet "127.0.0.1" 0) 8
    | Left e => putStrLn "listen: \{show e}"
  Right addr <- localAddress l
    | Left e => putStrLn "localAddress: \{show e}"
  results <- makeChannel
  server <- fork $ do
    Right sock <- Network.Socket.Async.accept l Nothing
      | Left e => putStrLn "accept: \{show e}"
    smallBuffers sock
    Right s <- Network.TLS.accept sctx sock Nothing
      | Left e => putStrLn "server handshake: \{show e}"
    r <- both s 1 False >>= report "server" s
    ignore (close s)
    channelPut results r
  Right sock <- Network.Socket.Async.socket IPv4 StreamSocket
    | Left e => putStrLn "socket: \{show e}"
  smallBuffers sock
  Right () <- connectSocket sock addr Nothing
    | Left e => putStrLn "connect: \{show e}"
  Right s <- Network.TLS.connect cctx "localhost" sock Nothing
    | Left e => putStrLn "client handshake: \{show e}"
  (csent, cgot) <- both s 2 True >>= report "client" s
  ignore (close s)
  (ssent, sgot) <- channelGet results
  threadWait server
  ignore (Network.Socket.Async.close l)
  putStrLn "client to server: \{show (chunks * chunk)} bytes, checksums match: \{show (isJust csent && csent == sgot)}"
  putStrLn "server to client: \{show (chunks * chunk)} bytes, checksums match: \{show (isJust ssent && ssent == cgot)}"
  putStrLn "the two directions differ: \{show (csent /= ssent)}"
