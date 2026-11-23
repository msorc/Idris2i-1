-- The client of the http library against its server over HTTPS:
-- persistent connections, bodies of a known length and chunked ones in
-- both directions, a large body with its checksum, a URL with an IP
-- address, what the handler sees of the connection, and the counters of
-- handshakes.
import Data.ByteString
import Data.IORef
import Data.List
import Data.Maybe
import Data.String
import HttpsTest
import Network.HTTP.Client
import Network.HTTP.Router
import Network.HTTP.Server
import Network.HTTP.TLS
import Network.TLS
import System
import System.Concurrency

%default covering

big : ByteString
big = bigBody 3000000

-- Read a body a piece at a time.
readPieces : BodyReader -> List ByteString -> IO (Either HttpError ByteString)
readPieces b acc = do
  Right (Just p) <- readChunk b
    | Right Nothing => pure (Right (concat (reverse acc)))
    | Left e => pure (Left e)
  readPieces b (p :: acc)

routes : List Route
routes =
  [ route GET "/hello" $ \_, _ => pure (textResponse statusOK "hello")
  , route POST "/echo" $ \req, _ => do
      Right b <- requestBody req
        | Left e => pure (statusResponse statusBadRequest)
      pure (textResponse statusOK ("echo " ++ toStringLossy b))
  , route POST "/sum" $ \req, _ => do
      Right b <- readPieces req.body []
        | Left e => pure (textResponse statusBadRequest (show e))
      let chunked = hasHeader "transfer-encoding" req.headers
      pure (textResponse statusOK ("chunked=\{show chunked} " ++ checksum b))
  , route GET "/big" $ \_, _ => pure (bytesResponse statusOK "application/octet-stream" big)
  , route GET "/stream" $ \_, _ =>
      pure (respond statusOK emptyHeaders (StreamBody Nothing (\w =>
              traverse_ (\i => ignore (writeBody w (fromString ("piece " ++ show i ++ "\n")))) [the Int 1 .. 200])))
  , route GET "/conn" $ \req, _ =>
      pure (textResponse statusOK "secure=\{show req.secure} remote=\{show (isJust req.remote)}")
  ]

result : String -> Either HttpError Reply -> IO ()
result label (Left e) = putStrLn "\{label}: error \{show e}"
result label (Right r) = putStrLn "\{label}: \{show r.status.code} \{show r.body}"

main : IO ()
main = do
  [_, certs] <- getArgs
    | _ => die "usage: main CERTS"
  sctx <- serverContext certs "server" []
  (cfg, stats) <- httpsServerConfig sctx (defaultServerConfig (Inet "127.0.0.1" 0))
  Right srv <- startServer cfg (router routes)
    | Left e => die "start: \{show e}"
  let port = show (addrPort (serverAddress srv))
  let base = "https://localhost:" ++ port
  c <- httpsClient !(clientContext certs [])
  result "GET" !(httpGet c (base ++ "/hello"))
  result "POST" !(httpPost c (base ++ "/echo") "text/plain" "over TLS")
  result "connection" !(httpGet c (base ++ "/conn"))
  -- persistent connections
  rs <- traverse (\_ => httpGet c (base ++ "/hello")) [the Int 1 .. 30]
  putStrLn "30 more requests: \{show (all (either (const False) (\r => r.status.code == 200)) rs)}"
  putStrLn "connections opened by the client: \{show !(connectionsOpened c)}"
  -- a large body each way
  Right r <- httpGet c (base ++ "/big")
    | Left e => die "big: \{show e}"
  putStrLn "large response: \{checksum r.body}, the same: \{show (r.body == big)}"
  result "large request" !(httpPost c (base ++ "/sum") "application/octet-stream" big)
  putStrLn "expected: \{checksum big}"
  -- chunked both ways
  Right r <- httpGet c (base ++ "/stream")
    | Left e => die "stream: \{show e}"
  putStrLn "chunked response: \{show (length (lines (toStringLossy r.body)))} lines, chunked: \{show (hasHeader "transfer-encoding" r.headers)}"
  let up = RequestStream Nothing (\w => traverse_ (\i => ignore (writeBody w (take 10000 (drop (i * 10000) big)))) [0 .. 299])
  result "chunked request" !(fetch c POST (base ++ "/sum") emptyHeaders up)
  putStrLn "connections opened by the client: \{show !(connectionsOpened c)}"
  -- an IP address in the URL: verified against the IP address of the
  -- certificate, and not sent with SNI
  result "IP address" !(httpGet c ("https://127.0.0.1:" ++ port ++ "/hello"))
  -- several threads
  done <- makeChannel
  traverse_ (\i => fork (do
                rs <- traverse (\_ => httpGet c (base ++ "/hello")) [1 .. 5]
                channelPut done (all (either (const False) (\x => x.status.code == 200)) rs)))
            [the Int 1 .. 8]
  oks <- traverse (\_ => channelGet done) [the Int 1 .. 8]
  putStrLn "8 threads, 5 requests each: \{show (all id oks)}"
  closeIdle c
  stopServer srv 1000
  n <- handshakeCounts stats
  putStrLn "handshakes: \{show n.failed} failed, \{show (n.succeeded >= 3)} that at least 3 succeeded"
