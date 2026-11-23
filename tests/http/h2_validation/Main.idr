-- The rules of RFC 9113 that the HTTP/2 server checks, each with frames
-- sent as they are by a raw client: malformed requests (a stream error
-- PROTOCOL_ERROR), frames that break the rules of the connection (GOAWAY),
-- frames that are ignored, and the limits of the header list (431, with
-- the decoder kept in step).
import Data.ByteString
import Data.List
import Data.String
import H2Raw
import Network.HTTP.Router
import Network.HTTP2.Frame
import System

%default covering

routes : List Route
routes =
  [ route GET "/hello" $ \req, _ => pure (textResponse statusOK "hello")
  , route POST "/echo" $ \req, _ => do
      Right b <- requestBody req
        | Left e => pure (textResponse statusBadRequest (show e))
      pure (textResponse statusOK ("got " ++ show (length b)))
  , route GET "/slow" $ \_, _ => do usleep 300000; pure (textResponse statusOK "slow")
  , route GET "/version" $ \req, _ =>
      pure (textResponse statusOK "\{show req.version.major}.\{show req.version.minor} \{show (lookupHeader "host" req.headers)} \{show (lookupHeader "cookie" req.headers)}")
  ]

-- One request on a new connection: the frames, and what comes back (up
-- to the end of a stream, or to GOAWAY).
tryUntil : (String -> Bool) -> SockAddr -> String -> (Raw -> IO (List Frame)) -> IO ()
tryUntil stop a label mk = do
  r <- openRaw a []
  fs <- mk r
  send r fs
  expect r label 3000 stop
  close r

try : SockAddr -> String -> (Raw -> IO (List Frame)) -> IO ()
try = tryUntil streamEnd

headers : Raw -> Int -> Bool -> List (String, String) -> IO Frame
headers r s end fs = do
  b <- block r fs
  pure (Headers s end True Nothing Nothing b)

main : IO ()
main = do
  Right srv <- startServer ({ errorLog := \_ => pure () } (defaultServerConfig (Inet "127.0.0.1" 0))) (router routes)
    | Left e => putStrLn (show e)
  let a = serverAddress srv
  try a "a valid GET" $ \r => pure [!(headers r 1 True (get "/hello"))]
  try a "version, host from :authority, cookies joined" $ \r =>
    pure [!(headers r 1 True (get "/version" ++ [("cookie", "a=1"), ("cookie", "b=2")]))]
  try a "a POST with a body" $ \r =>
    pure [!(headers r 1 False (post "/echo" ++ [("content-length", "5")])), DataFrame 1 False Nothing "ab", DataFrame 1 True Nothing "cde"]
  try a "a name in upper case" $ \r => pure [!(headers r 1 True (get "/hello" ++ [("X-Upper", "1")]))]
  try a "no :path" $ \r => pure [!(headers r 1 True [(":method", "GET"), (":scheme", "http"), (":authority", "x")])]
  try a "no :method" $ \r => pure [!(headers r 1 True [(":scheme", "http"), (":path", "/hello")])]
  try a "an empty :path" $ \r => pure [!(headers r 1 True [(":method", "GET"), (":scheme", "http"), (":path", "")])]
  try a "two :path" $ \r => pure [!(headers r 1 True (get "/hello" ++ [(":path", "/x")]))]
  try a "a pseudo-header field after a regular one" $ \r =>
    pure [!(headers r 1 True [(":method", "GET"), ("x-a", "1"), (":scheme", "http"), (":path", "/hello")])]
  try a "an unknown pseudo-header field" $ \r => pure [!(headers r 1 True (get "/hello" ++ [(":protocol", "x")]))]
  try a "a response pseudo-header field" $ \r => pure [!(headers r 1 True (get "/hello" ++ [(":status", "200")]))]
  try a "connection: keep-alive" $ \r => pure [!(headers r 1 True (get "/hello" ++ [("connection", "keep-alive")]))]
  try a "transfer-encoding: chunked" $ \r => pure [!(headers r 1 True (get "/hello" ++ [("transfer-encoding", "chunked")]))]
  try a "te: gzip" $ \r => pure [!(headers r 1 True (get "/hello" ++ [("te", "gzip")]))]
  try a "te: trailers" $ \r => pure [!(headers r 1 True (get "/hello" ++ [("te", "trailers")]))]
  try a "a value with a CR" $ \r => pure [!(headers r 1 True (get "/hello" ++ [("x-a", "a\rb")]))]
  try a "content-length 5 with 3 bytes" $ \r =>
    pure [!(headers r 1 False (post "/echo" ++ [("content-length", "5")])), DataFrame 1 True Nothing "abc"]
  try a "content-length 2 with 3 bytes" $ \r =>
    pure [!(headers r 1 False (post "/echo" ++ [("content-length", "2")])), DataFrame 1 True Nothing "abc"]
  try a "content-length 3 and END_STREAM on HEADERS" $ \r =>
    pure [!(headers r 1 True (post "/echo" ++ [("content-length", "3")]))]
  try a "trailers" $ \r =>
    pure [!(headers r 1 False (post "/echo")), DataFrame 1 False Nothing "abc", !(headers r 1 True [("x-trailer", "t")])]
  try a "trailers without END_STREAM" $ \r =>
    pure [!(headers r 1 False (post "/echo")), DataFrame 1 False Nothing "abc", !(headers r 1 False [("x-trailer", "t")])]
  try a "a pseudo-header field in trailers" $ \r =>
    pure [!(headers r 1 False (post "/echo")), !(headers r 1 True [(":path", "/x")])]
  try a "DATA after END_STREAM" $ \r =>
    pure [!(headers r 1 True (get "/slow")), DataFrame 1 False Nothing "abc"]
  -- the connection
  try a "DATA on stream 0" $ \r => pure [DataFrame 0 True Nothing "x"]
  try a "an even stream id" $ \r => pure [!(headers r 2 True (get "/hello"))]
  -- (the response on stream 5 may or may not be out before the GOAWAY)
  r <- openRaw a []
  send r [!(headers r 5 True (get "/hello")), !(headers r 3 True (get "/hello"))]
  (fs, _) <- frames r 3000 goaway
  putStrLn "--- a stream id lower than the one before"
  traverse_ (\f => putStrLn ("  " ++ f)) (filter (isPrefixOf "GOAWAY") fs)
  close r
  try a "PUSH_PROMISE from the client" $ \r => pure [PushPromise 1 True Nothing 2 !(block r (get "/x"))]
  try a "CONTINUATION without HEADERS" $ \r => pure [Continuation 1 True !(block r (get "/hello"))]
  try a "another frame inside a header block" $ \r => do
    b <- block r (get "/hello")
    pure [Headers 1 True False Nothing Nothing b, Ping False "12345678"]
  try a "a field block that is not HPACK" $ \r => pure [Headers 1 True True Nothing Nothing (pack [0xff, 0xff, 0xff])]
  try a "RST_STREAM on an idle stream" $ \r => pure [RstStream 7 Cancel]
  try a "WINDOW_UPDATE of 0" $ \r => pure [WindowUpdate 0 0]
  try a "SETTINGS_INITIAL_WINDOW_SIZE above 2^31-1" $ \r =>
    pure [SettingsFrame False [(InitialWindowSize, 0x80000000)]]
  try a "a frame larger than SETTINGS_MAX_FRAME_SIZE" $ \r =>
    pure [DataFrame 1 True Nothing (Data.ByteString.replicate 20000 65)]
  -- ignored
  try a "PRIORITY, an unknown frame and an unknown setting, then a GET" $ \r =>
    pure [PriorityFrame 1 (MkPriority False 0 16), UnknownFrame 0x42 0 0 "whatever",
          SettingsFrame False [(UnknownSetting 0x99, 7)], !(headers r 1 True (get "/hello"))]
  try a "PING" $ \r => pure [Ping False "abcdefgh", !(headers r 1 True (get "/hello"))]
  try a "HEADERS with CONTINUATION" $ \r => do
    b <- block r (get "/hello" ++ [("x-long", pack (replicate 3000 'v'))])
    pure [Headers 1 True False Nothing Nothing (take 1000 b), Continuation 1 False (take 1000 (drop 1000 b)),
          Continuation 1 True (drop 2000 b)]
  -- the header list: 431, and the decoder in step for the next request
  r <- openRaw a []
  big <- block r (get "/hello" ++ [("x-a", "indexed"), ("x-big", pack (replicate 70000 'b'))])
  send r [Headers 1 True False Nothing Nothing (take 16000 big),
          Continuation 1 False (take 16000 (drop 16000 big)),
          Continuation 1 False (take 16000 (drop 32000 big)),
          Continuation 1 False (take 16000 (drop 48000 big)),
          Continuation 1 True (drop 64000 big)]
  expect r "a header list of 70 kB" 3000 streamEnd
  send r [!(headers r 3 True (get "/hello" ++ [("x-a", "indexed")]))]
  expect r "then a request that uses the dynamic table" 3000 streamEnd
  close r
  stopServer srv 1000
