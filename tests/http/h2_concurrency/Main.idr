-- The client and the server of the library over HTTP/2 (h2c, prior
-- knowledge): 100 requests at once on one connection with interleaved
-- large bodies both ways and checksums; flow control that stalls and
-- resumes (a handler that reads late, a client that reads slowly); a
-- graceful shutdown with streams in progress; protocol selection (an
-- HTTP/1.1 client on the same port, HTTP/2 to a server without h2c); and
-- a request retried after a GOAWAY that did not process it.
import Data.ByteString
import Data.ByteString.Internal
import Data.IORef
import Data.List
import Data.String
import H2Raw
import HttpTest
import Network.HTTP.Client
import Network.HTTP.Server
import Network.HTTP2.Frame
import Network.HTTP2.HPACK
import Network.Socket.Async
import System
import System.Concurrency

%default covering

step : ByteString -> Int -> Int -> Bits64 -> Bits64
step bs i n acc = if i >= n then acc else step bs (i + 1) n (acc * 31 + cast (unsafeIndex bs i))

checksum : Bits64 -> ByteString -> Bits64
checksum acc bs = step bs 0 (lengthInt bs) acc

-- The body of request `i`: 200,000 bytes that depend on i.
bodyOf : Int -> ByteString
bodyOf i = Data.ByteString.replicate 200000 (cast (i `mod` 200 + 32))

consume : BodyReader -> Bits64 -> Int -> IO (Either HttpError (Bits64, Int))
consume r acc n = do
  Right (Just bs) <- readChunk r
    | Right Nothing => pure (Right (acc, n))
    | Left e => pure (Left e)
  consume r (checksum acc bs) (n + lengthInt bs)

-- Write a body in pieces of 10,000 bytes.
writeIn : BodyWriter -> ByteString -> IO ()
writeIn w bs =
  if length bs == 0 then pure () else do
    Right () <- writeBody w (take 10000 bs)
      | Left _ => pure ()
    writeIn w (drop 10000 bs)

app : Handler
app req =
  if req.path == "/echo" then do
    -- the checksum of the request body, and the body back as a stream
    Right b <- requestBody req
      | Left e => pure (textResponse statusBadRequest (show e))
    pure (respond statusOK (addHeader "x-sum" (fromString (show (checksum 0 b))) emptyHeaders)
                  (StreamBody Nothing (\w => writeIn w b)))
  else if req.path == "/late" then do
    -- reads a large body only after a while: the client waits for the window
    usleep 300000
    Right (s, n) <- consume req.body 0 0
      | Left e => pure (textResponse statusBadRequest (show e))
    pure (textResponse statusOK "\{show n} bytes")
  else if req.path == "/big" then
    pure (bytesResponse statusOK "application/octet-stream" (Data.ByteString.replicate 2000000 97))
  else if req.path == "/slow" then do
    usleep 1000000
    pure (textResponse statusOK "slow \{show req.version.major}")
  else pure (textResponse statusOK "hello \{show req.version.major}")

-- Read a body slowly: a pause every 64 kB.
slowRead : BodyReader -> Int -> Int -> IO (Either HttpError Int)
slowRead r n mark = do
  Right (Just bs) <- readChunk r
    | Right Nothing => pure (Right n)
    | Left e => pure (Left e)
  let n' = n + lengthInt bs
  when (n' `div` 65536 /= mark) $ usleep 20000
  slowRead r n' (n' `div` 65536)

result : String -> Either HttpError Reply -> IO ()
result label (Left e) = putStrLn "\{label}: error \{show e}"
result label (Right r) = putStrLn "\{label}: \{show r.status.code} \{show r.body}"

-- A raw HTTP/2 server that answers the first connection with GOAWAY (last
-- stream 0: nothing processed) and the second with 200.
goawayServer : IO SockAddr
goawayServer = do
  l <- orDie "listen" (listenOn (Inet "127.0.0.1" 0) 16)
  a <- orDie "address" (localAddress l)
  _ <- fork $ do
    s1 <- orDie "accept" (accept l Nothing)
    _ <- readUntil s1 "\x00\x00\x00\x00\x01" 2000
    sendFrames s1 [SettingsFrame False [], GoAway 0 NoError "not now"]
    _ <- readUntilEnd s1 1000
    ignore (close s1)
    s2 <- orDie "accept" (accept l Nothing)
    _ <- readUntil s2 "\x00\x00\x00\x00\x01" 2000
    let (blk, _) = encodeHeaderBlock (newEncoder 4096 False) [MkHeaderField ":status" "200" False]
    sendFrames s2 [SettingsFrame False [], SettingsFrame True [],
                   Headers 1 False True Nothing Nothing (toByteString blk), DataFrame 1 True Nothing "second"]
    _ <- readUntilEnd s2 1000
    ignore (close s2)
    ignore (close l)
  pure a
  where
    sendFrames : AsyncSocket -> List Frame -> IO ()
    sendFrames s fs = sendRaw s (toByteString (concat (map encodeFrame fs)))

main : IO ()
main = do
  Right srv <- startServer (defaultServerConfig (Inet "127.0.0.1" 0)) app
    | Left e => putStrLn (show e)
  let base = "http://\{show (serverAddress srv)}"
  c <- newClient ({ http2PriorKnowledge := True } defaultClientConfig)
  -- 100 at once
  done <- makeChannel
  traverse_ (\i => fork (do
      r <- fetch c POST (base ++ "/echo") emptyHeaders (RequestBytes (bodyOf i))
      channelPut done (case r of
        Right rep => rep.status.code == 200 && rep.body == bodyOf i
                     && lookupHeader "x-sum" rep.headers == Just (fromString (show (checksum 0 (bodyOf i))))
        Left e => False))) [the Int 1 .. 100]
  oks <- traverse (\_ => channelGet done) [the Int 1 .. 100]
  putStrLn "100 requests at once, 200 kB each way, bodies and checksums right: \{show (length (filter id oks))}"
  putStrLn "connections opened: \{show !(connectionsOpened c)}"
  -- flow control
  result "a handler that reads 1 MB late" !(fetch c POST (base ++ "/late") emptyHeaders
                                              (RequestStream Nothing (\w => writeIn w (Data.ByteString.replicate 1000000 98))))
  Right n <- withResponse c GET (base ++ "/big") emptyHeaders NoRequestBody (\resp => slowRead resp.body 0 0)
    | Left e => putStrLn (show e)
  putStrLn "a client that reads 2 MB slowly: \{show n}"
  putStrLn "connections opened: \{show !(connectionsOpened c)}"
  -- protocol selection
  c1 <- newClient defaultClientConfig
  result "an HTTP/1.1 client on the same port" !(httpGet c1 (base ++ "/hello"))
  closeIdle c1
  Right noh2c <- startServer ({ http2.cleartext := False } (defaultServerConfig (Inet "127.0.0.1" 0))) app
    | Left e => putStrLn (show e)
  c2 <- newClient ({ http2PriorKnowledge := True, requestTimeout := 3000 } defaultClientConfig)
  r <- httpGet c2 "http://\{show (serverAddress noh2c)}/hello"
  putStrLn "HTTP/2 to a server without h2c fails: \{show (either (const True) (const False) r)}"
  closeIdle c2
  c3 <- newClient defaultClientConfig
  result "and HTTP/1.1 works there" !(httpGet c3 "http://\{show (serverAddress noh2c)}/hello")
  closeIdle c3
  stopServer noh2c 1000
  -- GOAWAY before the request was processed: sent again on a new connection
  ga <- goawayServer
  c4 <- newClient ({ http2PriorKnowledge := True } defaultClientConfig)
  result "after a GOAWAY that did not process it" !(httpGet c4 "http://\{show ga}/")
  putStrLn "connections opened: \{show !(connectionsOpened c4)}"
  closeIdle c4
  -- a graceful shutdown with streams in progress
  slowDone <- makeChannel
  traverse_ (\i => fork (do
      r <- httpGet c (base ++ "/slow")
      channelPut slowDone (either show (\x => show x.status.code ++ " " ++ toStringLossy x.body) r)))
    [the Int 1 .. 5]
  usleep 300000
  stopper <- fork (stopServer srv 5000)
  rs <- traverse (\_ => channelGet slowDone) [the Int 1 .. 5]
  putStrLn "streams in progress at the shutdown: \{show (sort rs)}"
  threadWait stopper
  r <- httpGet c (base ++ "/hello")
  putStrLn "after the shutdown, a request fails: \{show (either (const True) (const False) r)}"
  closeIdle c
