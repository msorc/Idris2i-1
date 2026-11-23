-- The limits of the HTTP/2 server against abusive clients, each with raw
-- frames: the number of streams at a time, rapid reset (CVE-2023-44487),
-- CONTINUATION, PING, SETTINGS and empty-frame floods, padding, window
-- overflows, DATA beyond the windows, the settings timeout, a client that
-- does not read (the write timeout), and the idle timeout.
import Data.ByteString
import Data.List
import Data.Maybe
import Data.String
import H2Raw
import Network.HTTP.Router
import Network.HTTP2.Frame
import System
import System.Clock

%default covering

routes : List Route
routes =
  [ route GET "/hello" $ \req, _ => pure (textResponse statusOK "hello")
  , route GET "/slow" $ \_, _ => do usleep 1500000; pure (textResponse statusOK "slow")
  , route POST "/slow" $ \_, _ => do usleep 1500000; pure (textResponse statusOK "slow")
  , route GET "/big" $ \_, _ => pure (bytesResponse statusOK "application/octet-stream" (Data.ByteString.replicate 1000000 120))
  ]

headers : Raw -> Int -> Bool -> List (String, String) -> IO Frame
headers r s end fs = do
  b <- block r fs
  pure (Headers s end True Nothing Nothing b)

msSince : Clock Monotonic -> IO Integer
msSince t0 = do
  t <- clockTime Monotonic
  pure (toNano (timeDifference t t0) `div` 1000000)

-- Read until the end of the connection (or 20 s): whether it ended, and
-- the GOAWAY frames that came.
untilEnd : Raw -> IO (Bool, List String)
untilEnd r = do
  (fs, ended) <- frames r 20000 (const False)
  pure (ended, filter (isPrefixOf "GOAWAY") fs)

flood : SockAddr -> String -> Frame -> Int -> IO ()
flood a label f n = do
  r <- openRaw a []
  let one = toByteString (encodeFrame f)
  -- (sent in pieces, without reading what comes back)
  let chunk = concat (List.replicate 1000 one)
  traverse_ (\_ => sendBytes r chunk) [1 .. n `div` 1000]
  (ended, gs) <- untilEnd r
  putStrLn "--- \{label}: the server ended the connection: \{show ended}"
  close r

main : IO ()
main = do
  let h2 = { maxConcurrentStreams := 10, settingsTimeout := 500 } defaultH2Config
  let cfg = { writeTimeout := 1000, idleTimeout := 700, http2 := h2, errorLog := \_ => pure () }
              (defaultServerConfig (Inet "127.0.0.1" 0))
  Right srv <- startServer cfg (router routes)
    | Left e => putStrLn (show e)
  let a = serverAddress srv
  -- streams at a time
  r <- openRaw a []
  hs <- traverse (\i => headers r (2 * i + 1) True (get "/slow")) [0 .. 10]
  send r hs
  (fs, _) <- frames r 2500 (const False)
  putStrLn "--- 11 streams with a limit of 10"
  traverse_ (\f => putStrLn ("  " ++ f)) (filter (isPrefixOf "RST") fs)
  putStrLn "  responses: \{show (length (filter (isPrefixOf "HEADERS") fs))}, \{show (length (filter (isSuffixOf "END") fs))} ended"
  close r
  -- rapid reset
  r <- openRaw a []
  fs <- traverse (\i => do h <- headers r (2 * i + 1) True (get "/slow")
                           pure [h, RstStream (2 * i + 1) Cancel]) [0 .. 999]
  send r (concat fs)
  (fs, _) <- frames r 5000 goaway
  putStrLn "--- 1000 streams opened and reset at once"
  -- (the last stream id of the GOAWAY depends on when the limit is hit)
  putStrLn "  GOAWAY ENHANCE_YOUR_CALM (too many streams reset): \{show (any (\f => isPrefixOf "GOAWAY" f && isInfixOf "ENHANCE_YOUR_CALM (too many streams reset)" f) fs)}"
  putStrLn "  other frames than RST_STREAM and GOAWAY: \{show (filter (\f => not (isPrefixOf "RST_STREAM" f || isPrefixOf "GOAWAY" f)) fs)}"
  close r
  -- CONTINUATION
  r <- openRaw a []
  b <- block r (get "/hello")
  send r (Headers 1 True False Nothing Nothing b :: replicate 100 (Continuation 1 False "\x40\x01a\x01b"))
  expect r "100 CONTINUATION frames" 5000 goaway
  close r
  r <- openRaw a []
  b <- block r (get "/hello")
  send r (Headers 1 True False Nothing Nothing b :: replicate 9 (Continuation 1 False (Data.ByteString.replicate 16000 0x41)))
  expect r "144 kB of CONTINUATION frames" 5000 goaway
  close r
  -- empty frames
  r <- openRaw a []
  send r (!(headers r 1 False (post "/slow")) :: replicate 2000 (DataFrame 1 False Nothing ""))
  expect r "2000 empty DATA frames" 5000 goaway
  close r
  r <- openRaw a []
  send r (!(headers r 1 False (post "/slow")) :: replicate 2000 (DataFrame 1 False (Just 200) ""))
  expect r "2000 DATA frames of padding only" 5000 goaway
  close r
  r <- openRaw a []
  send r (Headers 1 True False Nothing Nothing "" :: replicate 2000 (Continuation 1 False ""))
  expect r "an empty HEADERS and empty CONTINUATION frames" 5000 goaway
  close r
  r <- openRaw a []
  send r (replicate 2000 (UnknownFrame 0x42 0 0 ""))
  expect r "2000 empty frames of an unknown type" 5000 goaway
  close r
  -- floods of control frames that the client does not read
  flood a "500,000 PING frames, not read" (Ping False "12345678") 500000
  flood a "500,000 SETTINGS frames, not read" (SettingsFrame False []) 500000
  -- windows
  r <- openRaw a []
  send r [WindowUpdate 0 0x7fffffff]
  expect r "the window of the connection above 2^31-1" 3000 goaway
  close r
  r <- openRaw a []
  send r [!(headers r 1 True (get "/slow")), WindowUpdate 1 0x7fffffff]
  expect r "the window of a stream above 2^31-1" 3000 streamEnd
  close r
  r <- openRaw a []
  send r (!(headers r 1 False (post "/slow")) :: replicate 17 (DataFrame 1 False Nothing (Data.ByteString.replicate 16000 0x61)))
  expect r "272 kB to a stream whose window is 256 kB, which the handler does not read" 3000 streamEnd
  close r
  r <- openRaw a []
  hs <- traverse (\i => headers r (2 * i + 1) False (post "/slow")) [0 .. 4]
  send r (hs ++ concatMap (\i => replicate 15 (DataFrame (2 * i + 1) False Nothing (Data.ByteString.replicate 16000 0x61))) [0 .. 4])
  expect r "1.2 MB on five streams, beyond the window of the connection (1 MiB)" 3000 goaway
  close r
  -- the settings timeout (500 ms here)
  t0 <- clockTime Monotonic
  r <- openRawAck False a []
  expect r "SETTINGS not acknowledged" 3000 goaway
  ms <- msSince t0
  putStrLn "  after 0.5 to 2 s: \{show (ms >= 450 && ms < 2000)}"
  close r
  -- a client that does not read: the server sends what the window of the
  -- client allows (65,535 bytes), then gives up after the write timeout
  r <- openRaw a []
  send r [!(headers r 1 True (get "/big"))]
  (fs, _) <- frames r 5000 streamEnd
  let sizes = mapMaybe (\f => if isPrefixOf "DATA" f then Just (the Int (cast (fromMaybe "0" (head' (drop 2 (words f)))))) else Nothing) fs
  putStrLn "--- a client that never opens its window"
  putStrLn "  DATA bytes: \{show (sum sizes)}"
  traverse_ (\f => putStrLn ("  " ++ f)) (filter (not . isPrefixOf "DATA") fs)
  close r
  -- the idle timeout (700 ms here)
  t0 <- clockTime Monotonic
  r <- openRaw a []
  send r [!(headers r 1 True (get "/hello"))]
  expect r "a connection left idle" 5000 goaway
  ms <- msSince t0
  putStrLn "  after 0.7 to 3 s: \{show (ms >= 650 && ms < 3000)}"
  when (ms < 650 || ms >= 3000) $ putStrLn "  (\{show ms} ms)"
  close r
  -- the server goes on
  r <- openRaw a []
  send r [!(headers r 1 True (get "/hello"))]
  expect r "the server goes on" 3000 streamEnd
  close r
  stopServer srv 1000
