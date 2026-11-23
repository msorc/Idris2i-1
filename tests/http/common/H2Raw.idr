-- A raw HTTP/2 client for the tests of the server: frames sent as they
-- are given (valid or not), and the frames that come back, decoded (the
-- field blocks with an HPACK decoder of the connection) and summarised.
module H2Raw

import Data.Buffer
import Data.ByteString
import Data.ByteString.Builder
import Data.ByteString.Internal
import Data.IORef
import Data.List
import Data.String
import Network.HTTP2.Frame
import Network.HTTP2.HPACK
import Network.Socket.Async
import System

%default covering

public export
record Raw where
  constructor MkRaw
  sock : AsyncSocket
  enc : IORef EncoderState
  dec : IORef DecoderState
  input : IORef ByteString

||| Send bytes.
export
sendBytes : Raw -> ByteString -> IO ()
sendBytes r bs = ignore (sendAll r.sock (unsafeBuffer bs) (unsafeOffset bs) (lengthInt bs) Nothing)

||| Send frames, all in one write.
export
send : Raw -> List Frame -> IO ()
send r fs = sendBytes r (toByteString (concat (map encodeFrame fs)))

||| A field block of fields (pseudo-header fields first), with the
||| encoder of the connection.
export
block : Raw -> List (String, String) -> IO ByteString
block r fs = do
  e <- readIORef r.enc
  let (b, e') = encodeHeaderBlock e (map (\(n, v) => MkHeaderField (fromString n) (fromString v) False) fs)
  writeIORef r.enc e'
  pure (toByteString b)

||| The fields of a GET of a path.
export
get : String -> List (String, String)
get p = [(":method", "GET"), (":scheme", "http"), (":authority", "localhost"), (":path", p)]

||| The fields of a POST to a path.
export
post : String -> List (String, String)
post p = [(":method", "POST"), (":scheme", "http"), (":authority", "localhost"), (":path", p)]

||| Connect, send the preface and SETTINGS, and acknowledge the server's
||| in advance if asked.
export
openRawAck : Bool -> SockAddr -> List (SettingId, Bits32) -> IO Raw
openRawAck ack a settings = do
  Right s <- connect a Nothing
    | Left e => do putStrLn "connect: \{show e}"; exitFailure
  r <- [| MkRaw (pure s) (newIORef (newEncoder 4096 False)) (newIORef (newDecoder 4096 1000000))
                (newIORef Data.ByteString.empty) |]
  sendBytes r connectionPreface
  send r (SettingsFrame False settings :: (if ack then [SettingsFrame True []] else []))
  pure r

||| Connect, send the preface and SETTINGS (and acknowledge the server's
||| in advance).
export
openRaw : SockAddr -> List (SettingId, Bits32) -> IO Raw
openRaw = openRawAck True

||| Close the socket.
export
close : Raw -> IO ()
close r = ignore (Network.Socket.Async.close r.sock)

-- Read more bytes: Nothing at the end of the stream (or an error), or
-- when the deadline passed.
readMore : Raw -> Int -> IO (Maybe ByteString)
readMore r dl = do
  Just b <- newBuffer 65536
    | Nothing => pure Nothing
  res <- recv r.sock b 0 65536 (Just dl)
  case res of
    Right 0 => pure Nothing
    Right n => pure (Just (UnsafeBS b 0 n))
    Left _ => pure Nothing

endMark : Bool -> String
endMark e = if e then " END" else ""

||| What a frame that came says, in short (field blocks decoded; SETTINGS,
||| their ACKs and WINDOW_UPDATE frames are left out unless `all`).
export
summary : Raw -> Bool -> Frame -> IO (Maybe String)
summary r all f = case f of
  Headers s end _ _ _ blk => do
    d <- readIORef r.dec
    case decodeHeaderBlock d blk of
      Right (fs, d') => do
        writeIORef r.dec d'
        let st = map (\x => toStringLossy x.value) (filter (\x => x.name == ":status") fs)
        pure (Just ("HEADERS \{show s} \{unwords st}" ++ endMark end))
      Left e => pure (Just "HEADERS \{show s} (not decoded: \{show e})")
  DataFrame s end _ d =>
    let shown = if length d <= 64 then " " ++ show (toStringLossy d) else "" in
    pure (Just ("DATA \{show s} \{show (length d)}" ++ shown ++ endMark end))
  RstStream s code => pure (Just "RST_STREAM \{show s} \{show code}")
  GoAway l code dbg => pure (Just ("GOAWAY \{show l} \{show code}" ++ (if length dbg > 0 then " (" ++ toStringLossy dbg ++ ")" else "")))
  Ping True _ => pure (Just "PING ACK")
  SettingsFrame False ps => pure (if all then Just "SETTINGS \{show (length ps)}" else Nothing)
  SettingsFrame True _ => pure (if all then Just "SETTINGS ACK" else Nothing)
  WindowUpdate s n => pure (if all then Just "WINDOW_UPDATE \{show s} \{show n}" else Nothing)
  other => pure (Just (show other))

||| Read frames until the stream ends or nothing comes for `ms`
||| milliseconds, or until `stop` says so of a summary: the summaries, and
||| whether the stream ended.
export
frames : Raw -> (ms : Int) -> (String -> Bool) -> IO (List String, Bool)
frames r ms stop = go []
  where
    go : List String -> IO (List String, Bool)
    go acc = do
      buf <- readIORef r.input
      case decodeFrame maxMaxFrameSize buf of
        Decoded f rest => do
          writeIORef r.input rest
          Just s <- summary r False f
            | Nothing => go acc
          if stop s then pure (reverse (s :: acc), False) else go (s :: acc)
        Failed e rest => do writeIORef r.input rest; go (("bad frame: " ++ show e) :: acc)
        NeedMore _ => do
          dl <- deadlineIn (ms * 1000000)
          Just more <- readMore r dl
            | Nothing => do
                -- (the end, or nothing for `ms`: tell them apart)
                t <- now
                pure (reverse acc, t < dl)
          writeIORef r.input (buf <+> more)
          go acc

||| Print what came (as `frames`), with a label.
export
expect : Raw -> String -> (ms : Int) -> (String -> Bool) -> IO ()
expect r label ms stop = do
  (fs, ended) <- frames r ms stop
  putStrLn "--- \{label}"
  traverse_ (\f => putStrLn ("  " ++ f)) fs
  when ended $ putStrLn "  [closed by the server]"

||| Stop at the end of a stream (END on HEADERS or DATA), at a reset of
||| it, or at GOAWAY.
export
streamEnd : String -> Bool
streamEnd s = isSuffixOf " END" s || isPrefixOf "RST_STREAM" s || isPrefixOf "GOAWAY" s

||| Stop at GOAWAY only.
export
goaway : String -> Bool
goaway s = isPrefixOf "GOAWAY" s
