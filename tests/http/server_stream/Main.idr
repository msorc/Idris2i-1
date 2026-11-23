-- Large bodies streamed both ways (chunked and with a length), checked
-- with a checksum on the other side, without holding them in memory: the
-- peak resident memory of the process (server and client) stays small.
import Data.ByteString
import Data.ByteString.Internal
import Data.List
import Data.String
import HttpTest
import Network.HTTP.Client
import Network.HTTP.Server
import System
import System.File

%default covering

piece : ByteString
piece = pack (map (\i => cast ((i * 7 + 3) `mod` 251)) [0 .. 65535])

-- 512 pieces of 64 KiB: 32 MiB.
pieces : Int
pieces = 512

step : ByteString -> Int -> Int -> Bits64 -> Bits64
step bs i n acc = if i >= n then acc else step bs (i + 1) n (acc * 31 + cast (unsafeIndex bs i))

checksum : Bits64 -> ByteString -> Bits64
checksum acc bs = step bs 0 (lengthInt bs) acc

expectedSum : Bits64
expectedSum = go pieces 0
  where
    go : Int -> Bits64 -> Bits64
    go 0 acc = acc
    go k acc = go (k - 1) (checksum acc piece)

-- Read a body to its end: the checksum and the length.
consume : BodyReader -> Bits64 -> Int -> IO (Either HttpError (Bits64, Int))
consume r acc n = do
  Right (Just bs) <- readChunk r
    | Right Nothing => pure (Right (acc, n))
    | Left e => pure (Left e)
  consume r (checksum acc bs) (n + lengthInt bs)

writePieces : BodyWriter -> Int -> IO ()
writePieces w 0 = pure ()
writePieces w k = do
  Right () <- writeBody w piece
    | Left _ => pure ()
  writePieces w (k - 1)

app : Handler
app req =
  if req.path == "/upload" then do
    Right (s, n) <- consume req.body 0 0
      | Left e => pure (textResponse statusBadRequest (show e))
    pure (textResponse statusOK "\{show n} bytes, checksum ok: \{show (s == expectedSum)}")
  else if req.path == "/download" then
    pure (respond statusOK emptyHeaders (StreamBody Nothing (\w => writePieces w pieces)))
  else if req.path == "/download-length" then
    pure (respond statusOK emptyHeaders (StreamBody (Just (pieces * 65536)) (\w => writePieces w pieces)))
  else pure (statusResponse statusNotFound)

peakRSSkB : IO Int
peakRSSkB = do
  Right s <- readFile "/proc/self/status"
    | Left _ => pure 0
  case filter (isPrefixOf "VmHWM:") (lines s) of
    (l :: _) => pure (cast (concat (filter (all isDigit . unpack) (words l))))
    [] => pure 0

download : Client -> String -> String -> IO ()
download c base path = do
  let url = base ++ path
  Right r <- withResponse c GET url emptyHeaders NoRequestBody (\resp => do
                r <- consume resp.body 0 0
                pure (resp.status.code, lookupHeader "transfer-encoding" resp.headers, r))
    | Left e => putStrLn "download: \{show e}"
  case r of
    (code, te, Right (s, n)) => putStrLn "download \{path}: \{show code} te=\{show te} \{show n} bytes, checksum ok: \{show (s == expectedSum)}"
    (_, _, Left e) => putStrLn "download: \{show e}"

main : IO ()
main = do
  let cfg = { maxBodySize := 1073741824 } (defaultServerConfig (Inet "127.0.0.1" 0))
  srv <- orDie "start" (startServer cfg app)
  let base = "http://\{show (serverAddress srv)}"
  c <- newClient defaultClientConfig
  Right r <- fetch c POST (base ++ "/upload") emptyHeaders (RequestStream Nothing (\w => writePieces w pieces))
    | Left e => putStrLn "upload: \{show e}"
  putStrLn "upload chunked: \{show r.status.code} \{toStringLossy r.body}"
  Right r <- fetch c POST (base ++ "/upload") emptyHeaders (RequestStream (Just (pieces * 65536)) (\w => writePieces w pieces))
    | Left e => putStrLn "upload: \{show e}"
  putStrLn "upload with a length: \{show r.status.code} \{toStringLossy r.body}"
  download c base "/download"
  download c base "/download-length"
  opened <- connectionsOpened c
  putStrLn "connections: \{show opened}"
  stopServer srv 1000
  kb <- peakRSSkB
  putStrLn "peak RSS below 48 MB: \{show (kb > 0 && kb < 49152)}"
  when (kb >= 49152) $ putStrLn "peak RSS: \{show kb} kB"
