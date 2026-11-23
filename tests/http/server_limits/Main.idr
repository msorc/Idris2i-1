-- The limits and timeouts of the server, and malformed requests (the
-- shapes used for request smuggling among them): each gets the status the
-- parser suggests and the connection is closed, and no handler sees it.
import Data.ByteString
import Data.IORef
import Data.List
import Data.String
import HttpTest
import Network.HTTP.Client
import Network.HTTP.Server
import System

%default covering

app : IORef (List String) -> Handler
app seen req = do
  modifyIORef seen (toStringLossy req.target ::)
  if req.path == "/echo"
     then do
       Right b <- requestBody req
         | Left BodyTooLarge => pure (statusResponse statusContentTooLarge)
         | Left e => pure (textResponse statusBadRequest ("cannot read the body: " ++ show e ++ "\n"))
       pure (bytesResponse statusOK "text/plain" b)
     else pure (textResponse statusOK "ok\n")

main : IO ()
main = do
  seen <- newIORef []
  let lim = { maxStartLine := 2048, maxHeaderLine := 1024, maxHeadSize := 4096 } defaultLimits
  let cfg = { headTimeout := 400, idleTimeout := 400, bodyTimeout := 400,
              maxBodySize := 1000, limits := lim,
              errorLog := \msg => putStrLn "server error: \{msg}" }
            (defaultServerConfig (Inet "127.0.0.1" 0))
  srv <- orDie "start" (startServer cfg (app seen))
  let a = serverAddress srv
  -- timeouts
  exchange a "slow head (slowloris)" "GET /slow HTTP/1.1\r\nHost: x\r\nX-A: 1\r\n" False 5000
  exchange a "nothing sent" "" False 5000
  exchange a "idle persistent connection" "GET /idle HTTP/1.1\r\nHost: x\r\n\r\n" False 5000
  exchange a "slow body" "POST /echo HTTP/1.1\r\nHost: x\r\nContent-Length: 10\r\n\r\nabc" False 5000
  -- sizes
  exchange a "Content-Length above the limit"
    "POST /echo HTTP/1.1\r\nHost: x\r\nContent-Length: 2000\r\n\r\n" False 5000
  exchange a "chunked body above the limit"
    ("POST /echo HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: chunked\r\n\r\n" ++
     concat (replicate 5 ("190\r\n" ++ pack (replicate 400 'x') ++ "\r\n")) ++ "0\r\n\r\n") True 5000
  exchange a "field line too long"
    ("GET /long HTTP/1.1\r\nHost: x\r\nX-Long: " ++ pack (replicate 2000 'a') ++ "\r\n\r\n") True 5000
  exchange a "head too large"
    ("GET /big HTTP/1.1\r\nHost: x\r\n" ++ concat (replicate 10 ("X-F: " ++ pack (replicate 500 'b') ++ "\r\n")) ++ "\r\n") True 5000
  exchange a "request line too long"
    ("GET /" ++ pack (replicate 3000 'c') ++ " HTTP/1.1\r\nHost: x\r\n\r\n") True 5000
  -- malformed and ambiguous heads
  exchange a "Content-Length and Transfer-Encoding (smuggling)"
    "POST /echo HTTP/1.1\r\nHost: x\r\nContent-Length: 4\r\nTransfer-Encoding: chunked\r\n\r\n0\r\n\r\nGET /smuggled HTTP/1.1\r\nHost: x\r\n\r\n" True 5000
  exchange a "two different Content-Length"
    "POST /echo HTTP/1.1\r\nHost: x\r\nContent-Length: 3\r\nContent-Length: 4\r\n\r\nabcd" True 5000
  exchange a "Transfer-Encoding not ending with chunked"
    "POST /echo HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: chunked, identity\r\n\r\n" True 5000
  exchange a "Transfer-Encoding gzip, chunked"
    "POST /echo HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: gzip, chunked\r\n\r\n0\r\n\r\n" True 5000
  exchange a "Transfer-Encoding in HTTP/1.0"
    "POST /echo HTTP/1.0\r\nTransfer-Encoding: chunked\r\n\r\n0\r\n\r\n" True 5000
  exchange a "space before the colon"
    "GET /a HTTP/1.1\r\nHost : x\r\n\r\n" True 5000
  exchange a "obsolete line folding"
    "GET /a HTTP/1.1\r\nHost: x\r\nX-A: 1\r\n  2\r\n\r\n" True 5000
  exchange a "bare LF"
    "GET /a HTTP/1.1\nHost: x\n\n" True 5000
  exchange a "bare CR"
    "GET /a HTTP/1.1\r\nHost: x\rX: y\r\n\r\n" True 5000
  exchange a "no Host"
    "GET /a HTTP/1.1\r\n\r\n" True 5000
  exchange a "two Host fields"
    "GET /a HTTP/1.1\r\nHost: x\r\nHost: y\r\n\r\n" True 5000
  exchange a "HTTP/2.0 request line"
    "GET /a HTTP/2.0\r\nHost: x\r\n\r\n" True 5000
  exchange a "target with a space"
    "GET /a b HTTP/1.1\r\nHost: x\r\n\r\n" True 5000
  exchange a "target with a byte that is not allowed"
    "GET /a{b} HTTP/1.1\r\nHost: x\r\n\r\n" True 5000
  exchange a "bad chunk size"
    "POST /echo HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: chunked\r\n\r\nzz\r\nabc\r\n0\r\n\r\nGET /after HTTP/1.1\r\nHost: x\r\n\r\n" True 5000
  exchange a "a good request after a bad one on the same connection is not served"
    "GET /first HTTP/1.1\r\nHost: x\r\n\r\nGET /second HTTP/1.1\r\nHost: x\r\nBad Name: 1\r\n\r\nGET /third HTTP/1.1\r\nHost: x\r\n\r\n" True 5000
  -- the client, against the limits
  c <- newClient defaultClientConfig
  Right r <- httpPost c "http://\{show a}/echo" "text/plain" (fromString (pack (replicate 2000 'z')))
    | Left e => putStrLn "client: \{show e}"
  putStrLn "client, body above the limit: \{show r.status.code}"
  stopServer srv 1000
  s <- readIORef seen
  putStrLn "targets the handler saw: \{show (reverse s)}"
