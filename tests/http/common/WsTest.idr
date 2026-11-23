-- Helpers of the WebSocket tests: a raw peer that sends frames byte by
-- byte (valid or not) and reads and prints the frames it gets.
module WsTest

import Data.Bits
import Data.Buffer
import Data.ByteString
import Data.ByteString.Internal
import Data.IORef
import Data.List
import Data.String
import Network.HTTP.Transport
import Network.Socket.Async
import Network.WebSocket.Frame
import System

%default covering

||| A raw connection and the bytes read but not used yet.
public export
record Raw where
  constructor MkRaw
  sock : AsyncSocket
  pending : IORef ByteString

-- A byte string of the first `n` bytes of a buffer.
bytesOf : Buffer -> Int -> ByteString
bytesOf b n = unsafeCreate n (\dst => copyData b 0 n dst 0)

||| Send all of a byte string.
export
rawSend : Raw -> ByteString -> IO ()
rawSend r bs = do
  let n = lengthInt bs
  Just b <- newBuffer (max 1 n)
    | Nothing => pure ()
  copyData (unsafeBuffer bs) (unsafeOffset bs) n b 0
  ignore (sendAll r.sock b 0 n Nothing)

-- More bytes (at least one), or Nothing at the end, on a failure or after
-- the deadline.
more : Raw -> Int -> IO (Maybe ByteString)
more r d = do
  Just b <- newBuffer 65536
    | Nothing => pure Nothing
  res <- recv r.sock b 0 65536 (Just d)
  case res of
    Right 0 => pure Nothing
    Right n => pure (Just (bytesOf b n))
    Left _ => pure Nothing

||| At least `n` bytes (taken), or Nothing if they do not come in time.
export
rawTake : Raw -> Int -> (ms : Int) -> IO (Maybe ByteString)
rawTake r n ms = do
  d <- deadlineIn (ms * 1000000)
  go d
  where
    go : Int -> IO (Maybe ByteString)
    go d = do
      p <- readIORef r.pending
      if lengthInt p >= n
         then do writeIORef r.pending (unsafeSlice n (lengthInt p - n) p)
                 pure (Just (unsafeSlice 0 n p))
         else do
           Just m <- more r d
             | Nothing => pure Nothing
           writeIORef r.pending (p <+> m)
           go d

||| Connect and send a request head; read the response head (up to the
||| blank line).  The response head as text, and the connection.
export
rawRequest : SockAddr -> String -> IO (String, Raw)
rawRequest addr req = do
  Right s <- connect addr Nothing
    | Left e => do putStrLn "connect: \{show e}"; exitFailure
  p <- newIORef Data.ByteString.empty
  let r = MkRaw s p
  rawSend r (fromString req)
  d <- deadlineIn 5000000000
  head <- readHead r d
  pure (head, r)
  where
    readHead : Raw -> Int -> IO String
    readHead r d = do
      p <- readIORef r.pending
      case findEnd p 0 of
        Just i => do
          writeIORef r.pending (unsafeSlice (i + 4) (lengthInt p - i - 4) p)
          pure (toStringLossy (unsafeSlice 0 i p))
        Nothing => do
          Just m <- more r d
            | Nothing => pure (toStringLossy p)
          writeIORef r.pending (p <+> m)
          readHead r d
      where
        findEnd : ByteString -> Int -> Maybe Int
        findEnd bs i =
          if i + 4 > lengthInt bs then Nothing
          else if unsafeIndex bs i == 13 && unsafeIndex bs (i + 1) == 10 &&
                  unsafeIndex bs (i + 2) == 13 && unsafeIndex bs (i + 3) == 10
            then Just i else findEnd bs (i + 1)

||| A valid handshake request for a path, with more header lines.
export
handshakeRequest : String -> List String -> String
handshakeRequest path extra =
  "GET \{path} HTTP/1.1\r\nHost: localhost\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n" ++
  "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\nSec-WebSocket-Version: 13\r\n" ++
  concatMap (++ "\r\n") extra ++ "\r\n"

||| Open a WebSocket connection by hand (the response status line is
||| checked).
export
rawOpen : SockAddr -> String -> IO Raw
rawOpen addr path = do
  (head, r) <- rawRequest addr (handshakeRequest path [])
  when (not (isPrefixOf "HTTP/1.1 101" head)) $ do
    putStrLn "handshake failed: \{head}"
    exitFailure
  pure r

||| The bytes of a frame: the first byte (FIN, RSV and opcode), and the
||| payload, masked with a fixed key if asked.  Any first byte and any
||| length can be written (to make invalid frames).
export
frameBytes : (b0 : Bits8) -> (masked : Bool) -> ByteString -> ByteString
frameBytes b0 masked payload =
  let n = lengthInt payload
      key : Bits32 = 0x37fa213d
      m : Bits8 = if masked then 0x80 else 0
      len = if n < 126 then pack [prim__or_Bits8 m (cast n)]
            else if n < 65536 then pack [prim__or_Bits8 m 126, cast (prim__shr_Int n 8), cast n]
            else pack (prim__or_Bits8 m 127 :: map (\i => cast (prim__shr_Int n (8 * (7 - i)))) [0 .. 7])
      k = if masked then pack [0x37, 0xfa, 0x21, 0x3d] else Data.ByteString.empty
      body = if masked then mask key 0 payload else payload
  in pack [b0] <+> len <+> k <+> body

||| Send a frame (see `frameBytes`).
export
sendFrame : Raw -> (b0 : Bits8) -> (masked : Bool) -> ByteString -> IO ()
sendFrame r b0 m p = rawSend r (frameBytes b0 m p)

||| A frame read: its first byte, and its payload (unmasked).
public export
record RawFrame where
  constructor MkRawFrame
  b0 : Bits8
  payload : ByteString

||| The next frame, or Nothing at the end of the stream or after `ms`.
export
readFrame : Raw -> (ms : Int) -> IO (Maybe RawFrame)
readFrame r ms = do
  Just h <- rawTake r 2 ms
    | Nothing => pure Nothing
  let b0 = unsafeIndex h 0
      b1 = unsafeIndex h 1
      masked = prim__and_Bits8 b1 0x80 /= 0
      l7 = cast {to = Int} (prim__and_Bits8 b1 0x7F)
  len <- the (IO (Maybe Int)) $ if l7 < 126 then pure (Just l7)
         else if l7 == 126 then map (map (\e => beNum e 0 2 0)) (rawTake r 2 ms)
         else map (map (\e => beNum e 0 8 0)) (rawTake r 8 ms)
  case len of
    Nothing => pure Nothing
    Just n => do
      key <- the (IO (Maybe Bits32)) $
             if masked then map (map (\k => cast {to = Bits32} (beNum k 0 4 0))) (rawTake r 4 ms)
             else pure (Just 0)
      Just p <- the (IO (Maybe ByteString)) (if n == 0 then pure (Just Data.ByteString.empty) else rawTake r n ms)
        | Nothing => pure Nothing
      case key of
        Nothing => pure Nothing
        Just k => pure (Just (MkRawFrame b0 (if masked then mask k 0 p else p)))
  where
    beNum : ByteString -> Int -> Int -> Int -> Int
    beNum bs i n acc = if n <= 0 then acc else beNum bs (i + 1) (n - 1) (acc * 256 + cast (unsafeIndex bs i))

||| A frame as text: the opcode, FIN, and the payload (its length when it
||| is long).
export
showFrame : RawFrame -> String
showFrame f =
  let op = prim__and_Bits8 f.b0 0x0F
      fin = prim__and_Bits8 f.b0 0x80 /= 0
      n = lengthInt f.payload
      name = case op of
               0 => "cont"; 1 => "text"; 2 => "binary"; 8 => "close"; 9 => "ping"; 10 => "pong"
               _ => "op" ++ show op
      body = if op == 8
               then if n >= 2 then show (cast {to = Int} (unsafeIndex f.payload 0) * 256 + cast (unsafeIndex f.payload 1))
                                   ++ " " ++ show (toStringLossy (unsafeSlice 2 (n - 2) f.payload))
                    else "(no code)"
             else if n <= 40 then show (toStringLossy f.payload)
             else show n ++ " bytes"
  in name ++ (if fin then "" else " (not fin)") ++ " " ++ body

||| Print the frames that come until the stream ends (or nothing comes for
||| `ms`), then whether it ended.  The sending side is shut down after a
||| close frame.
export
printUntilEnd : Raw -> (ms : Int) -> IO ()
printUntilEnd r ms = do
  Just f <- readFrame r ms
    | Nothing => do
        p <- readIORef r.pending
        putStrLn (if lengthInt p == 0 then "  [end]" else "  [end, \{show (lengthInt p)} bytes left]")
  putStrLn ("  " ++ showFrame f)
  -- after a close frame, end the sending side, as a peer that answers
  -- with its own close and then closes would
  when (prim__and_Bits8 f.b0 0x0F == 8) $ ignore (shutdown r.sock ShutWrite)
  printUntilEnd r ms

||| Close the socket.
export
rawClose : Raw -> IO ()
rawClose r = ignore (close r.sock)

||| A close payload.
export
closeBytes : Int -> String -> ByteString
closeBytes code reason = pack [cast (prim__shr_Int code 8), cast code] <+> fromString reason
