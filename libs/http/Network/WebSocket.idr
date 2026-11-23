||| WebSocket connections (RFC 6455), server and client, over the HTTP/1.1
||| server and client of this library.
|||
||| A server answers an upgrade request with `acceptWebSocket`, which checks
||| the request and gives either the `101` response that hands the
||| connection to a session function, or an error response:
|||
||| ```idris
||| echo : WebSocket -> IO ()
||| echo ws = do
|||   Right msg <- receive ws
|||     | Left closed => pure ()
|||   ignore (sendMessage ws msg)
|||   echo ws
|||
||| handler : Handler
||| handler req = pure (acceptWebSocket defaultAcceptOptions req echo)
||| ```
|||
||| A client connects with `connectWebSocket` to a `ws://` (or, with a TLS
||| connector, `wss://`) URL.
|||
||| # Messages
|||
||| `receive` gives whole messages: the fragments of a message are put
||| together (up to `maxMessageSize`), and the control frames that come
||| between them are handled on the way: a ping is answered with a pong, a
||| pong is counted (`pongCount`), a close frame ends the connection with
||| the closing handshake.  The payload of a text message is a `ByteString`
||| that has been checked to be UTF-8 (incrementally, fragment by fragment,
||| so that an invalid byte fails the connection at once): most programs pass
||| it on, or parse it, as bytes, and `messageString` makes it a `String`
||| without checking it again.  A connection whose peer breaks the protocol
||| is closed with the status code that RFC 6455 gives (1002 for a protocol
||| error, 1007 for text that is not UTF-8, 1009 for a message over the
||| limit), and `receive` reports how it ended (`CloseInfo`).
|||
||| No extension is negotiated: an offer of `permessage-deflate` is ignored,
||| and a frame with a reserved bit set is a protocol error.
|||
||| # Threads
|||
||| One thread at a time may receive; any number of threads may send at the
||| same time as it and as each other.  The frames of a message are never
||| interleaved with those of another (a send takes the right to write for
||| the whole message); control frames may come between the fragments of a
||| message, as the RFC allows.  A send waits until the transport has taken
||| all the bytes of its message, so a peer that does not read makes the
||| senders wait (up to `sendTimeout`, after which the connection is failed):
||| nothing is queued, and memory does not grow.  The pongs that the receiver
||| sends never wait for a sender: when a sender has the right to write, the
||| pong is left for it to send after its message (only the latest one, as
||| the RFC allows), so a receiver is never blocked by a sender that a slow
||| peer holds up.  `closeWebSocket` may be called from any thread: a thread
||| blocked in `receive` gets the end of the connection.
|||
||| # Keep-alive and timeouts
|||
||| With `pingInterval`, the receiver sends a ping when nothing has come for
||| that long, and fails the connection (reported as 1006) when nothing comes
||| within `pongTimeout` after it; with `idleTimeout`, it closes a connection
||| that has had no message for that long (with 1001).  The quiet times are
||| measured coarsely, so that the clock is not read for every frame: a
||| timer that comes after something came starts again from then, so the
||| ping (or the close) comes after between once and twice the time of
||| quiet.  Both run inside
||| `receive`: they need a thread that receives, which is the usual shape of
||| a connection.
module Network.WebSocket

import Data.Buffer
import Data.ByteString
import Data.ByteString.Internal
import Data.IORef
import Data.List
import Data.List1
import Data.Maybe
import Network.HTTP.Client
import Network.HTTP.Internal.Bytes
import Network.HTTP.Router
import public Network.HTTP.Server
import Network.URI
import Network.WebSocket.Frame
import Network.WebSocket.Handshake
import Network.WebSocket.UTF8
import System.Concurrency
import System.Crash

%default covering

--------------------------------------------------------------------------
-- Messages, closings and errors
--------------------------------------------------------------------------

||| A message.  The payload of a text message is valid UTF-8: `receive`
||| checks it, and `sendMessage` sends it as it is.
public export
data Message
  = ||| A text message, as its UTF-8 bytes.
    TextMessage ByteString
  | ||| A binary message.
    BinaryMessage ByteString

||| The same kind and the same bytes.
export
Eq Message where
  TextMessage a == TextMessage b = a == b
  BinaryMessage a == BinaryMessage b = a == b
  _ == _ = False

||| The kind and the length, for logs (not the bytes).
export
Show Message where
  show (TextMessage b) = "TextMessage (" ++ show (lengthInt b) ++ " bytes)"
  show (BinaryMessage b) = "BinaryMessage (" ++ show (lengthInt b) ++ " bytes)"

||| The payload of a message.
export
messageBytes : Message -> ByteString
messageBytes (TextMessage b) = b
messageBytes (BinaryMessage b) = b

||| The text of a message: for a text message, its bytes as a `String`
||| (they were checked when the message came, and are not checked again); for
||| a binary message, its bytes decoded with U+FFFD for what is not UTF-8.
export
messageString : Message -> String
messageString (TextMessage b) = unsafeBufferString (unsafeBuffer b) (unsafeOffset b) (lengthInt b)
messageString (BinaryMessage b) = toStringLossy b

||| How a connection ended.
public export
record CloseInfo where
  constructor MkCloseInfo
  ||| The status code of the close frame of the peer: 1005 if it had none,
  ||| 1006 if no close frame came (the connection broke, a timeout, a
  ||| protocol error found here): 1006 is never sent.
  code : Bits16
  ||| The reason of the close frame of the peer (UTF-8); for 1006, what
  ||| happened, in words.
  reason : ByteString
  ||| The status code of the close frame that this side sent, if it sent
  ||| one (1002, 1007 or 1009 when it failed the connection).
  sent : Maybe Bits16
  ||| Did this side start the closing (`closeWebSocket`, a protocol error of
  ||| the peer, a timeout)?
  local : Bool

||| For logs and tests.
export
Show CloseInfo where
  show c = "closed " ++ show c.code ++
           (if lengthInt c.reason == 0 then "" else " " ++ show (toStringLossy c.reason)) ++
           (case c.sent of Nothing => ", sent nothing"; Just s => ", sent " ++ show s) ++
           (if c.local then ", by this side" else ", by the peer")

||| What can go wrong when connecting or sending.
public export
data WSError
  = ||| The connection is closing or closed: nothing more can be sent.
    WSClosed
  | ||| A send did not finish before `sendTimeout` (the connection is failed
    ||| if a part of the message went out).
    WSTimedOut
  | ||| The transport failed (the connection is failed).
    WSNetFailure NetError
  | ||| `sendTextBytes` of bytes that are not UTF-8.
    WSInvalidText
  | ||| A ping with more than 125 bytes of payload.
    WSControlTooLong
  | ||| A URL that is not a `ws://` or `wss://` URL, or one that cannot be
    ||| used (with the reason).
    WSBadURL String
  | ||| The HTTP exchange of the handshake failed.
    WSHttpError HttpError
  | ||| The server answered the handshake with another status than 101.
    WSRejected Status
  | ||| The `101` response of the server is not a valid WebSocket handshake
    ||| (with the reason).
    WSBadHandshake String

||| A message for logs.
export
Show WSError where
  show WSClosed = "the WebSocket connection is closed"
  show WSTimedOut = "send timed out"
  show (WSNetFailure e) = show e
  show WSInvalidText = "text message that is not UTF-8"
  show WSControlTooLong = "control frame payload longer than 125 bytes"
  show (WSBadURL s) = "bad WebSocket URL: " ++ s
  show (WSHttpError e) = "WebSocket handshake: " ++ show e
  show (WSRejected s) = "WebSocket handshake rejected: " ++ show s
  show (WSBadHandshake s) = "bad WebSocket handshake: " ++ s

||| The same error (and the same details).
export
Eq WSError where
  WSClosed == WSClosed = True
  WSTimedOut == WSTimedOut = True
  WSNetFailure a == WSNetFailure b = a == b
  WSInvalidText == WSInvalidText = True
  WSControlTooLong == WSControlTooLong = True
  WSBadURL a == WSBadURL b = a == b
  WSHttpError a == WSHttpError b = a == b
  WSRejected a == WSRejected b = a == b
  WSBadHandshake a == WSBadHandshake b = a == b
  _ == _ = False

--------------------------------------------------------------------------
-- Configuration
--------------------------------------------------------------------------

||| The limits and timeouts of a connection.  Times are in milliseconds; 0
||| is none.
public export
record WSConfig where
  constructor MkWSConfig
  ||| The largest frame accepted (a larger one is closed with 1009).
  maxFrameSize : Int
  ||| The largest message accepted, all its fragments together (a larger
  ||| one is closed with 1009).
  maxMessageSize : Int
  ||| Messages longer than this are sent in fragments of this size; 0 sends
  ||| every message as one frame.
  fragmentSize : Int
  ||| Each message (with all its fragments) must be taken by the transport
  ||| within this time; when it is not, the connection is failed.
  sendTimeout : Int
  ||| How long the closing handshake may take: for the close frame to go
  ||| out, and for the peer to answer it.
  closeTimeout : Int
  ||| Send a ping when nothing has come for this long.
  pingInterval : Int
  ||| Fail the connection when nothing comes for this long after a ping of
  ||| `pingInterval`.
  pongTimeout : Int
  ||| Close the connection (with 1001) when no message has come for this
  ||| long.
  idleTimeout : Int

||| Frames and messages up to 16 MiB, no fragmentation of what is sent, 30 s
||| to send a message, 5 s for the closing handshake, no keep-alive pings
||| (10 s for the pong when they are turned on), no idle timeout.
export
defaultWSConfig : WSConfig
defaultWSConfig = MkWSConfig 0x1000000 0x1000000 0 30000 5000 0 10000 0

--------------------------------------------------------------------------
-- Randomness (for the masking keys and the handshake key)
--------------------------------------------------------------------------

-- getentropy(3): at most 256 bytes from the random source of the system
-- (the same as /dev/urandom, without opening a file), 0 or -1.
%foreign "C:getentropy,libc 6,unistd.h"
prim__getentropy : Buffer -> Int -> PrimIO Int

-- Fill the first `n` (<= 256) bytes of a buffer with random bytes.
fillRandom : Buffer -> Int -> IO Bool
fillRandom b n = do
  r <- fromPrim (prim__getentropy b n)
  pure (r == 0)

%foreign "scheme:blodwen-buffer-getbits32"
         "RefC:getBufferUInt32LE"
         "node:lambda:(buf,offset)=>buf.readUInt32LE(offset)"
prim__getBits32 : Buffer -> Int -> PrimIO Bits32

||| `n` (at most 256) bytes from the random source of the system.
export
randomBytes : Int -> IO (Maybe ByteString)
randomBytes n = do
  b <- bufNew n
  ok <- fillRandom b n
  pure (if ok then Just (UnsafeBS b 0 n) else Nothing)

-- The size of the pool of random bytes of a client connection: 64 keys.
poolSize : Int
poolSize = 256

--------------------------------------------------------------------------
-- Connections
--------------------------------------------------------------------------

-- The states of a connection.
stOpen, stCloseSent, stCloseReceived, stClosed : Int
stOpen = 0
stCloseSent = 1
stCloseReceived = 2
stClosed = 3

-- A frame too large for the read buffer, read into a buffer of its own.
record BigFrame where
  constructor MkBigFrame
  header : FrameHeader
  buf : Buffer
  filled : Int

||| An open (or closed) WebSocket connection.
export
record WebSocket where
  constructor MkWebSocket
  transport : Transport
  isClient : Bool
  config : WSConfig
  proto : Maybe ByteString
  opts : DecodeOptions
  timers : Bool
  -- reading: one receiver at a time
  rbuf : Buffer
  rsize : Int
  rpos : IORef Int
  rend : IORef Int
  big : IORef (Maybe BigFrame)
  msgOp : IORef Int          -- 0: no message, 1: text, 2: binary
  msgParts : IORef (List ByteString)
  msgLen : IORef Int
  msgUtf8 : IORef Utf8State
  nextPing : IORef Int
  pongDue : IORef Int
  idleAt : IORef Int
  closeDl : IORef Int
  pongs : IORef Int
  -- bytes came since `nextPing` was set, a message since `idleAt` was
  -- (the timers are moved when they come, rather than at every read)
  sawData : IORef Bool
  sawMessage : IORef Bool
  -- writing: one writer at a time (`busy`), under the lock
  lock : Mutex
  cond : Condition
  busy : IORef Bool
  pendPong : IORef (Maybe ByteString)
  pendPing : IORef (Maybe ByteString)
  -- may one of them be there? (so that the writer that ends looks at them
  -- only then)
  pendAny : IORef Bool
  hbuf : Buffer
  pool : Buffer
  poolPos : IORef Int
  -- the state, under the lock
  state : IORef Int
  info : IORef (Maybe CloseInfo)
  sentCode : IORef (Maybe Bits16)
  local : IORef Bool
  ops : IORef Int
  waiters : IORef Int
  reading : IORef Bool
  tclosed : IORef Bool

||| The subprotocol that the handshake agreed on, if any.
export
subprotocol : WebSocket -> Maybe ByteString
subprotocol ws = ws.proto

||| The address of the peer, if known.
export
webSocketPeer : WebSocket -> Maybe SockAddr
webSocketPeer ws = transportPeer ws.transport

||| Is this the client side of the connection?
export
isClientSide : WebSocket -> Bool
isClientSide ws = ws.isClient

||| The number of pongs received so far.
export
pongCount : WebSocket -> IO Int
pongCount ws = readIORef ws.pongs

||| How the connection ended, once it has (`Nothing` while it is open or
||| closing).
export
closeStatus : WebSocket -> IO (Maybe CloseInfo)
closeStatus ws = do
  mutexAcquire ws.lock
  i <- readIORef ws.info
  mutexRelease ws.lock
  pure i

||| Can messages still be sent (no close frame sent or received yet)?
export
isOpen : WebSocket -> IO Bool
isOpen ws = do
  mutexAcquire ws.lock
  s <- readIORef ws.state
  mutexRelease ws.lock
  pure (s == stOpen)

-- A connection over a transport, with the bytes already read.
newWebSocket : Transport -> (isClient : Bool) -> WSConfig -> Maybe ByteString ->
               (scratch : Buffer) -> (scratchSize : Int) -> (pending : ByteString) -> IO WebSocket
newWebSocket t client cfg proto scratch ssize pend = do
  let plen = lengthInt pend
  (rb, rs) <- if plen <= ssize then pure (scratch, ssize)
              else do b <- bufNew plen; pure (b, plen)
  bufCopy (unsafeBuffer pend) (unsafeOffset pend) plen rb 0
  let maxp = min cfg.maxFrameSize cfg.maxMessageSize
  let dopts = MkDecodeOptions (not client) 0 maxp
  let timers = cfg.pingInterval > 0 || cfg.idleTimeout > 0
  now <- if timers then nowNs else pure 0
  pool <- bufNew (if client then poolSize else 0)
  hb <- bufNew 14
  [| MkWebSocket (pure t) (pure client) (pure cfg) (pure proto) (pure dopts) (pure timers)
       (pure rb) (pure rs) (newIORef 0) (newIORef plen) (newIORef Nothing)
       (newIORef 0) (newIORef []) (newIORef 0) (newIORef utf8Start)
       (newIORef (if cfg.pingInterval > 0 then now + cfg.pingInterval * 1000000 else -1))
       (newIORef (-1))
       (newIORef (if cfg.idleTimeout > 0 then now + cfg.idleTimeout * 1000000 else -1))
       (newIORef (-1)) (newIORef 0) (newIORef False) (newIORef False)
       makeMutex makeCondition (newIORef False) (newIORef Nothing) (newIORef Nothing) (newIORef False)
       (pure hb) (pure pool) (newIORef poolSize)
       (newIORef stOpen) (newIORef Nothing) (newIORef Nothing) (newIORef False)
       (newIORef 0) (newIORef 0) (newIORef False) (newIORef False) |]

||| Take over an HTTP connection on which the opening handshake has been
||| done (by hand: `acceptWebSocket` and `connectWebSocket` do it
||| themselves), as the client side or the server side, with the
||| subprotocol agreed on.  The bytes that the connection has read but not
||| used are the first frames.  The connection's own reads and writes must
||| not be used afterwards.  On the client side the transport is closed when
||| the WebSocket connection has ended and no thread uses it any more; on
||| the server side the caller closes it (the server does, after the
||| function of `UpgradeBody` returns) once `waitUnused` has returned.
export
fromConn : (isClient : Bool) -> WSConfig -> (subprotocol : Maybe ByteString) -> Conn ->
           IO WebSocket
fromConn client cfg proto c = do
  p <- pendingBytes c
  newWebSocket (connTransport c) client cfg proto (connScratch c) (connBufferSize c) p

--------------------------------------------------------------------------
-- The state, under the lock
--------------------------------------------------------------------------

-- Wait (with the lock held) for a change of the state, at most `us`
-- microseconds (for ever if negative).  The number of waiters lets the
-- common case (nobody waits) skip the broadcast.
waitFor : WebSocket -> (us : Int) -> IO ()
waitFor ws us = do
  w <- readIORef ws.waiters
  writeIORef ws.waiters (w + 1)
  if us < 0 then conditionWait ws.cond ws.lock else conditionWaitTimeout ws.cond ws.lock us
  w <- readIORef ws.waiters
  writeIORef ws.waiters (w - 1)

-- Leave an operation (with the lock held): whether the caller must close
-- the transport now (a client whose connection has ended and that nobody
-- uses any more).
leaveLocked : WebSocket -> IO Bool
leaveLocked ws = do
  n <- readIORef ws.ops
  writeIORef ws.ops (n - 1)
  w <- readIORef ws.waiters
  () <- if w > 0 then conditionBroadcast ws.cond else pure ()
  if n > 1 || not ws.isClient then pure False else do
    s <- readIORef ws.state
    tc <- readIORef ws.tclosed
    if s == stClosed && not tc
       then do writeIORef ws.tclosed True; pure True
       else pure False

-- Close the transport if asked to.
closeIf : WebSocket -> Bool -> IO ()
closeIf ws True = transportClose ws.transport
closeIf ws False = pure ()

-- Give up the right to write and end the operation of the writer.
releaseAfterFailure : WebSocket -> IO ()
releaseAfterFailure ws = do
  mutexAcquire ws.lock
  writeIORef ws.busy False
  c <- leaveLocked ws
  mutexRelease ws.lock
  closeIf ws c

-- The connection has ended: record how (if it has not ended already), shut
-- the transport down so that the threads that wait on it return, and wake
-- the threads that wait for the state.  The information of an earlier end
-- wins.
finish : WebSocket -> CloseInfo -> IO CloseInfo
finish ws ci = do
  mutexAcquire ws.lock
  s <- readIORef ws.state
  if s == stClosed
     then do Just old <- readIORef ws.info
               | Nothing => do mutexRelease ws.lock; pure ci
             mutexRelease ws.lock
             pure old
     else do
       transportShutdown ws.transport ShutBoth
       writeIORef ws.state stClosed
       writeIORef ws.info (Just ci)
       writeIORef ws.pendPong Nothing
       writeIORef ws.pendPing Nothing
       conditionBroadcast ws.cond
       n <- readIORef ws.ops
       tc <- readIORef ws.tclosed
       let doClose = n <= 0 && ws.isClient && not tc
       when doClose $ writeIORef ws.tclosed True
       mutexRelease ws.lock
       closeIf ws doClose
       pure ci

-- The connection ends without a close frame from the peer, because of
-- this side (a timeout, `abort`) or not.
abnormalBy : WebSocket -> (local : Bool) -> String -> IO CloseInfo
abnormalBy ws byThis why = do
  mutexAcquire ws.lock
  sc <- readIORef ws.sentCode
  l <- readIORef ws.local
  mutexRelease ws.lock
  finish ws (MkCloseInfo 1006 (fromString why) sc (l || byThis))

-- The connection ends without a close frame from the peer (it broke).
abnormal : WebSocket -> String -> IO CloseInfo
abnormal ws why = abnormalBy ws False why

||| End the connection at once, without the closing handshake (reported as
||| 1006 by both sides).  Threads blocked in `receive` or in a send return.
export
abort : WebSocket -> IO ()
abort ws = ignore (abnormalBy ws True "aborted")

--------------------------------------------------------------------------
-- Writing frames
--------------------------------------------------------------------------

-- Write the `n` low bytes of a number big-endian at `o`.
putBE : Buffer -> Int -> Int -> Int -> IO ()
putBE buf o n v =
  if n <= 0 then pure ()
  else do bufSetByte buf (o + n - 1) (cast (prim__and_Int v 0xFF))
          putBE buf o (n - 1) (prim__shr_Int v 8)

-- Write a frame header at the start of a buffer: its length.
putHeader : Buffer -> (b0 : Bits8) -> (masked : Bool) -> Bits32 -> (len : Int) -> IO Int
putHeader buf b0 masked key n = do
  bufSetByte buf 0 b0
  let m = the Bits8 (if masked then 0x80 else 0)
  at <- the (IO Int) $ if n < 126 then do bufSetByte buf 1 (prim__or_Bits8 m (cast n)); pure 2
        else if n < 65536 then do bufSetByte buf 1 (prim__or_Bits8 m 126)
                                  putBE buf 2 2 n
                                  pure 4
        else do bufSetByte buf 1 (prim__or_Bits8 m 127)
                putBE buf 2 8 n
                pure 10
  if masked then do putBE buf at 4 (cast key); pure (at + 4) else pure at

-- The next masking key of a client (from its pool of random bytes, which
-- is refilled from the system when it is used up).  Only the writer uses
-- the pool.
nextKey : WebSocket -> IO Bits32
nextKey ws = do
  p <- readIORef ws.poolPos
  p <- if p + 4 <= poolSize then pure p else do
         ok <- fillRandom ws.pool poolSize
         -- (a system without a random source cannot mask safely)
         when (not ok) $ assert_total $ idris_crash "Network.WebSocket: getentropy failed"
         pure 0
  writeIORef ws.poolPos (p + 4)
  fromPrim (prim__getBits32 ws.pool p)

-- The deadline of `rawSend` that is `sendTimeout` from the call.
withinSendTimeout : Int
withinSendTimeout = -2

-- A deadline for the operations that need one, from that of `rawSend`.
absoluteDeadline : WebSocket -> Int -> IO Int
absoluteDeadline ws dl = if dl == withinSendTimeout then deadlineAfterMs ws.config.sendTimeout else pure dl

-- Send one frame (the first byte of its header, and its payload) with the
-- right to write: 0, or minus an errno code.  A server sends the header and
-- the payload as two ranges of one system call; a client masks the payload
-- into a buffer of its own after the header.
--
-- A deadline of `withinSendTimeout` is `sendTimeout` from the call, made
-- only if the transport cannot take the frame at once.
rawSend : WebSocket -> Bits8 -> ByteString -> (deadline : Int) -> IO Int
rawSend ws b0 payload dl = do
  let n = lengthInt payload
  if not ws.isClient
     then do
       hl <- putHeader ws.hbuf b0 False 0 n
       if dl == withinSendTimeout
          then if n == 0 then transportSendAllWithin ws.transport ws.hbuf 0 hl ws.config.sendTimeout
               else transportSendAll2Within ws.transport ws.hbuf 0 hl (unsafeBuffer payload) (unsafeOffset payload) n
                                            ws.config.sendTimeout
          else if n == 0 then transportSendAll ws.transport ws.hbuf 0 hl dl
               else transportSendAll2 ws.transport ws.hbuf 0 hl (unsafeBuffer payload) (unsafeOffset payload) n dl
     else do
       key <- nextKey ws
       out <- bufNew (n + 14)
       hl <- putHeader out b0 True key n
       maskInto key 0 payload out hl
       if dl == withinSendTimeout
          then transportSendAllWithin ws.transport out 0 (hl + n) ws.config.sendTimeout
          else transportSendAll ws.transport out 0 (hl + n) dl

-- A write failed or timed out: the stream may hold part of a frame, so
-- nothing more can be sent; the connection is failed.
writeFailed : WebSocket -> Int -> IO WSError
writeFailed ws code = do
  let e = if code == timedOutCode then WSTimedOut else WSNetFailure (codeError code)
  _ <- abnormal ws ("send failed: " ++ show e)
  pure e

-- The opcode bytes of the control frames.
pongByte, pingByte, closeByte : Bits8
pongByte = 0x8A
pingByte = 0x89
closeByte = 0x88

-- Send a control frame if there is one: 0 or the failure.
sendMaybe : WebSocket -> Bits8 -> Maybe ByteString -> Int -> IO Int
sendMaybe ws b Nothing dl = pure 0
sendMaybe ws b (Just p) dl = rawSend ws b p dl

-- Give up the right to write, after sending the control frames that the
-- receiver left meanwhile: 0, or the failure of one of them.
releaseWriter : WebSocket -> (deadline : Int) -> IO Int
releaseWriter ws dl = do
  mutexAcquire ws.lock
  any <- readIORef ws.pendAny
  if not any then release else do
    writeIORef ws.pendAny False
    pp <- readIORef ws.pendPong
    pi <- readIORef ws.pendPing
    s <- readIORef ws.state
    if s == stOpen && (isJust pp || isJust pi)
       then do
         writeIORef ws.pendPong Nothing
         writeIORef ws.pendPing Nothing
         mutexRelease ws.lock
         r <- sendMaybe ws pongByte pp dl
         r <- if r < 0 then pure r else sendMaybe ws pingByte pi dl
         if r < 0
            then do _ <- writeFailed ws r
                    releaseAfterFailure ws
                    pure r
            else releaseWriter ws dl
       else release
  where
    release : IO Int
    release = do
      writeIORef ws.busy False
      c <- leaveLocked ws
      mutexRelease ws.lock
      closeIf ws c
      pure 0

-- What `waitWriter` gives when the right to write was not taken.
notTaken : Int
notTaken = -3

-- Wait (with the lock held) until nobody has the right to write, while
-- the state is the one asked for; then take it.  The deadline to write
-- with (a deadline of `withinSendTimeout` becomes one if it had to wait),
-- or `notTaken`.
waitWriter : WebSocket -> (anyState : Bool) -> (deadline : Int) -> IO Int
waitWriter ws anyState dl = do
  s <- readIORef ws.state
  if s == stClosed || (not anyState && s /= stOpen) then pure notTaken else do
    b <- readIORef ws.busy
    if not b
       then do writeIORef ws.busy True
               n <- readIORef ws.ops
               writeIORef ws.ops (n + 1)
               pure dl
       else if dl == withinSendTimeout
         then do dl' <- deadlineAfterMs ws.config.sendTimeout
                 waitWriter ws anyState dl'
       else if dl < 0
         then do waitFor ws (-1)
                 waitWriter ws anyState dl
         else do
           t <- nowNs
           if t >= dl then pure notTaken else do
             waitFor ws (max 1 ((dl - t) `div` 1000))
             waitWriter ws anyState dl

-- Send a data message (an opcode and its payload) as one frame or in
-- fragments.
sendFragments : WebSocket -> Bits8 -> ByteString -> (offset : Int) -> (frag : Int) -> Int -> IO Int
sendFragments ws op payload off frag dl = do
  let n = lengthInt payload - off
  let op' = if off == 0 then op else 0
  if n <= frag
     then rawSend ws (prim__or_Bits8 0x80 op') (dropInt off payload) dl
     else do
       r <- rawSend ws op' (sliceFromTo off (off + frag) payload) dl
       if r < 0 then pure r else do
         -- a pong that the receiver left goes out between the fragments
         mutexAcquire ws.lock
         pp <- readIORef ws.pendPong
         writeIORef ws.pendPong Nothing
         mutexRelease ws.lock
         r <- sendMaybe ws pongByte pp dl
         if r < 0 then pure r else sendFragments ws op payload (off + frag) frag dl

-- Send a message: the right to write for all its frames.
sendData : WebSocket -> Bits8 -> ByteString -> IO (Either WSError ())
sendData ws op payload = do
  -- (the deadline is made only if the frame must wait: see `rawSend`)
  let dl0 = if ws.config.sendTimeout > 0 then withinSendTimeout else -1
  mutexAcquire ws.lock
  dl1 <- waitWriter ws False dl0
  -- (another sender may hold the right to write until the deadline: then
  -- nothing was sent, and the connection goes on)
  if dl1 == notTaken
     then do st <- readIORef ws.state
             mutexRelease ws.lock
             pure (Left (if st == stOpen then WSTimedOut else WSClosed))
     else do
    mutexRelease ws.lock
    -- (a fragmented message has one deadline for all its frames)
    dl <- if ws.config.fragmentSize > 0 && lengthInt payload > ws.config.fragmentSize
             then absoluteDeadline ws dl1 else pure dl1
    let frag = ws.config.fragmentSize
    r <- if frag > 0 && lengthInt payload > frag
            then sendFragments ws op payload 0 frag dl
            else rawSend ws (prim__or_Bits8 0x80 op) payload dl
    if r < 0
       then do
         e <- writeFailed ws r
         releaseAfterFailure ws
         pure (Left e)
       else do
         r <- releaseWriter ws dl
         pure (if r < 0 then Left (if r == timedOutCode then WSTimedOut else WSNetFailure (codeError r))
                        else Right ())

||| Send a binary message.  Waits until the transport has taken it (see
||| "Threads" above), for at most `sendTimeout` from the call: when the
||| time runs out while another sender has the right to write, nothing is
||| sent and the result is `WSTimedOut`, but the connection goes on; when it
||| runs out in the middle of the message, the connection is failed.
export
sendBinary : WebSocket -> ByteString -> IO (Either WSError ())
sendBinary ws b = sendData ws 2 b

||| Send a text message.
export
sendText : WebSocket -> String -> IO (Either WSError ())
sendText ws s = sendData ws 1 (fromString s)

||| Send a text message given as bytes, which must be UTF-8
||| (`WSInvalidText` otherwise: they are checked).
export
sendTextBytes : WebSocket -> ByteString -> IO (Either WSError ())
sendTextBytes ws b = if validUtf8 b then sendData ws 1 b else pure (Left WSInvalidText)

||| Send a message (a text message as it is: its bytes are not checked).
export
sendMessage : WebSocket -> Message -> IO (Either WSError ())
sendMessage ws (TextMessage b) = sendData ws 1 b
sendMessage ws (BinaryMessage b) = sendData ws 2 b

||| Send a ping with a payload of at most 125 bytes.  The pong that answers
||| it is counted by the receiver (`pongCount`).
export
ping : WebSocket -> ByteString -> IO (Either WSError ())
ping ws b = if lengthInt b > 125 then pure (Left WSControlTooLong) else sendData ws 9 b

-- Send a control frame from the receiver: at once if nobody has the right
-- to write, or left for the writer that has it (only the latest pong and
-- ping are kept).
sendControl : WebSocket -> (isPong : Bool) -> ByteString -> IO ()
sendControl ws isPong payload = do
  mutexAcquire ws.lock
  s <- readIORef ws.state
  b <- readIORef ws.busy
  if s /= stOpen then mutexRelease ws.lock else
    if b
     then do writeIORef (if isPong then ws.pendPong else ws.pendPing) (Just payload)
             writeIORef ws.pendAny True
             mutexRelease ws.lock
     else do
       writeIORef ws.busy True
       n <- readIORef ws.ops
       writeIORef ws.ops (n + 1)
       mutexRelease ws.lock
       let dl = if ws.config.sendTimeout > 0 then withinSendTimeout else -1
       r <- rawSend ws (if isPong then pongByte else pingByte) payload dl
       if r < 0 then do _ <- writeFailed ws r; releaseAfterFailure ws
                else ignore (releaseWriter ws dl)

-- Send a close frame (the state has been set to closing): waits for the
-- right to write until the deadline.  Whether it went out.
sendCloseFrame : WebSocket -> ByteString -> (deadline : Int) -> IO Bool
sendCloseFrame ws payload dl = do
  mutexAcquire ws.lock
  dl1 <- waitWriter ws True dl
  mutexRelease ws.lock
  if dl1 == notTaken then pure False else do
    r <- rawSend ws closeByte payload dl
    mutexAcquire ws.lock
    writeIORef ws.busy False
    writeIORef ws.pendPong Nothing
    writeIORef ws.pendPing Nothing
    c <- leaveLocked ws
    mutexRelease ws.lock
    closeIf ws c
    pure (r >= 0)

-- The longest prefix of at most `n` bytes that ends at a code point
-- boundary of UTF-8.
utf8Prefix : Int -> ByteString -> ByteString
utf8Prefix n bs =
  if lengthInt bs <= n then bs else go n
  where
    go : Int -> ByteString
    go i = if i <= 0 then Data.ByteString.empty
           else if prim__and_Bits8 (unsafeIndex bs i) 0xC0 == 0x80 then go (i - 1)
           else takeInt i bs

-- The payload of a close frame of this side: a valid code (1000 for one
-- that may not be sent) and a reason cut to fit.
closeFramePayload : Bits16 -> ByteString -> (Bits16, ByteString)
closeFramePayload code reason =
  let c = if validCloseCode code then code else 1000 in
  (c, closePayload c (utf8Prefix 123 reason))

-- Start the closing handshake (if the connection is open): the state, and
-- the close frame.  Whether this call started it.
startClose : WebSocket -> Bits16 -> ByteString -> IO Bool
startClose ws code reason = do
  let (c, payload) = closeFramePayload code reason
  mutexAcquire ws.lock
  s <- readIORef ws.state
  if s /= stOpen then do mutexRelease ws.lock; pure False else do
    writeIORef ws.state stCloseSent
    writeIORef ws.sentCode (Just c)
    writeIORef ws.local True
    mutexRelease ws.lock
    dl <- deadlineAfterMs ws.config.closeTimeout
    writeIORef ws.closeDl dl
    ok <- sendCloseFrame ws payload dl
    when (not ok) $ do
      mutexAcquire ws.lock
      writeIORef ws.sentCode Nothing
      mutexRelease ws.lock
      ignore (abnormalBy ws True "the close frame could not be sent")
    pure True

--------------------------------------------------------------------------
-- Reading frames
--------------------------------------------------------------------------

-- How the connection ended (it has).
endedInfo : WebSocket -> IO CloseInfo
endedInfo ws = do
  i <- readIORef ws.info
  pure (fromMaybe (MkCloseInfo 1006 Data.ByteString.empty Nothing False) i)

-- What a step of the receiver gives.
data RecvResult = RMsg Message | RClosed CloseInfo | RTimeout

data Step = Again | Out RecvResult

-- The payload of a frame from the read buffer, unmasked, in a byte string
-- of its own.
payloadOf : Buffer -> Int -> Int -> Maybe Bits32 -> IO ByteString
payloadOf src off len key =
  if len == 0 then pure Data.ByteString.empty else do
    b <- bufNew len
    case key of
      Nothing => bufCopy src off len b 0
      Just k => maskInto k 0 (UnsafeBS src off len) b 0
    pure (UnsafeBS b 0 len)

-- Read and drop what comes until the end of the stream or the deadline.
drainUntilEnd : WebSocket -> Int -> IO ()
drainUntilEnd ws dl = do
  n <- transportRecv ws.transport ws.rbuf 0 ws.rsize dl
  if n > 0 then drainUntilEnd ws dl else pure ()

-- Fail the connection because of the peer: send a close frame with the
-- code (when the state lets this side send one), stop sending, read what
-- the peer still sends (its close frame, until it closes; for at most the
-- close timeout) so that the close frame is not lost to a reset, and end.
failConnection : WebSocket -> Bits16 -> String -> IO Step
failConnection ws code why = do
  mutexAcquire ws.lock
  s <- readIORef ws.state
  if s == stClosed then do i <- endedInfo ws; mutexRelease ws.lock; pure (Out (RClosed i)) else do
    writeIORef ws.state stCloseSent
    when (s == stOpen) $ do
      writeIORef ws.sentCode (Just code)
      writeIORef ws.local True
    mutexRelease ws.lock
    dl <- deadlineAfterMs ws.config.closeTimeout
    sentNow <- if s == stOpen then sendCloseFrame ws (closePayload code (fromString why)) dl
               else pure False
    transportShutdown ws.transport ShutWrite
    drainUntilEnd ws dl
    mutexAcquire ws.lock
    when (s == stOpen && not sentNow) $ writeIORef ws.sentCode Nothing
    sc <- readIORef ws.sentCode
    l <- readIORef ws.local
    mutexRelease ws.lock
    i <- finish ws (MkCloseInfo 1006 (fromString why) sc l)
    pure (Out (RClosed i))

-- The end of a closing handshake: a client waits for the server to close
-- the TCP connection (RFC 6455 section 7.1.1), then the connection ends.
endHandshake : WebSocket -> CloseInfo -> IO Step
endHandshake ws ci = do
  when ws.isClient $ do
    dl <- deadlineAfterMs ws.config.closeTimeout
    drainUntilEnd ws dl
  i <- finish ws ci
  pure (Out (RClosed i))

-- A close frame from the peer.
onClose : WebSocket -> ByteString -> IO Step
onClose ws payload =
  case parseClose payload of
    Left e => failConnection ws (closeErrorCode e) "invalid close frame"
    Right m => do
      let (code, reason) = fromMaybe (1005, Data.ByteString.empty) m
      mutexAcquire ws.lock
      s <- readIORef ws.state
      if s == stOpen
         then do
           -- the peer starts the closing: answer with its code
           writeIORef ws.state stCloseReceived
           let reply = case m of
                         Nothing => Data.ByteString.empty
                         Just (c, _) => closePayload c Data.ByteString.empty
           writeIORef ws.sentCode (map fst m)
           mutexRelease ws.lock
           dl <- deadlineAfterMs ws.config.closeTimeout
           ok <- sendCloseFrame ws reply dl
           endHandshake ws (MkCloseInfo code reason (if ok then map fst m else Nothing) False)
         else do
           sc <- readIORef ws.sentCode
           l <- readIORef ws.local
           mutexRelease ws.lock
           endHandshake ws (MkCloseInfo code reason sc l)

-- A complete message.
deliver : WebSocket -> Message -> IO Step
deliver ws m = do
  () <- if ws.timers && ws.config.idleTimeout > 0 then writeIORef ws.sawMessage True else pure ()
  s <- readIORef ws.state
  pure (if s /= stOpen then Again else Out (RMsg m))

textOp, binaryOp : Int
textOp = 1
binaryOp = 2

-- A text or binary frame: a whole message, or its first fragment.
dataFrame : WebSocket -> FrameHeader -> ByteString -> Int -> IO Step
dataFrame ws h payload op = do
  cur <- readIORef ws.msgOp
  if cur /= 0 then failConnection ws 1002 "new message inside a fragmented one" else
    if h.fin
       then if op == textOp
               then if validUtf8 payload then deliver ws (TextMessage payload)
                    else failConnection ws 1007 "invalid UTF-8"
               else deliver ws (BinaryMessage payload)
       else do
         let u = if op == textOp then feedUtf8 utf8Start payload else utf8Start
         if utf8Invalid u then failConnection ws 1007 "invalid UTF-8" else do
           writeIORef ws.msgOp op
           writeIORef ws.msgParts [payload]
           writeIORef ws.msgLen (lengthInt payload)
           writeIORef ws.msgUtf8 u
           pure Again

-- A whole frame.
onFrame : WebSocket -> FrameHeader -> ByteString -> IO Step
onFrame ws h payload =
  case h.opcode of
    Text => dataFrame ws h payload textOp
    Binary => dataFrame ws h payload binaryOp
    Continuation => do
      op <- readIORef ws.msgOp
      if op == 0 then failConnection ws 1002 "continuation without a message" else do
        len <- readIORef ws.msgLen
        let tot = len + lengthInt payload
        u <- if op == textOp then do
               u0 <- readIORef ws.msgUtf8
               pure (feedUtf8 u0 payload)
             else pure utf8Start
        if op == textOp && utf8Invalid u then failConnection ws 1007 "invalid UTF-8" else do
          parts <- readIORef ws.msgParts
          if not h.fin
             then do
               writeIORef ws.msgParts (payload :: parts)
               writeIORef ws.msgLen tot
               writeIORef ws.msgUtf8 u
               pure Again
             else do
               writeIORef ws.msgOp 0
               writeIORef ws.msgParts []
               writeIORef ws.msgLen 0
               writeIORef ws.msgUtf8 utf8Start
               if op == textOp && not (utf8Complete u)
                  then failConnection ws 1007 "invalid UTF-8"
                  else do
                    let whole = concat (reverse (payload :: parts))
                    deliver ws (if op == textOp then TextMessage whole else BinaryMessage whole)
    Ping => do sendControl ws True payload; pure Again
    Pong => do n <- readIORef ws.pongs; writeIORef ws.pongs (n + 1); pure Again
    Close => onClose ws payload

-- The deadline of the next read: the caller's, the closing handshake's,
-- and those of the keep-alive and idle timers.
readDeadline : WebSocket -> Int -> IO Int
readDeadline ws udl = do
  cd <- readIORef ws.closeDl
  let d = earlierDeadline udl cd
  if not ws.timers then pure d else do
    np <- readIORef ws.nextPing
    pd <- readIORef ws.pongDue
    ia <- readIORef ws.idleAt
    pure (earlierDeadline d (earlierDeadline np (earlierDeadline pd ia)))

-- A keep-alive or idle deadline (one may have come).
timerDeadline : WebSocket -> Int -> IO Step
timerDeadline ws t = do
  pd <- readIORef ws.pongDue
  np <- readIORef ws.nextPing
  ia <- readIORef ws.idleAt
  if pd >= 0 && t >= pd
    then do i <- abnormalBy ws True "no answer to a keep-alive ping"
            pure (Out (RClosed i))
    else if np >= 0 && t >= np && pd < 0
      then do
        seen <- readIORef ws.sawData
        if seen
           then do
             -- (bytes came since: the timer starts again from now)
             writeIORef ws.sawData False
             writeIORef ws.nextPing (t + ws.config.pingInterval * 1000000)
             pure Again
           else ping pd t
    else if np >= 0 && t >= np
      then ping pd t
      else if ia >= 0 && t >= ia
        then do
          seen <- readIORef ws.sawMessage
          if seen
             then do
               writeIORef ws.sawMessage False
               writeIORef ws.idleAt (t + ws.config.idleTimeout * 1000000)
               pure Again
             else do
               writeIORef ws.idleAt (-1)
               ignore (startClose ws 1001 "idle timeout")
               pure Again
        else pure Again
  where
    ping : Int -> Int -> IO Step
    ping pd t = do
        writeIORef ws.nextPing (t + ws.config.pingInterval * 1000000)
        -- (one ping at a time: none while one waits for its answer)
        when (pd < 0) $ do
          writeIORef ws.pongDue (t + ws.config.pongTimeout * 1000000)
          sendControl ws False Data.ByteString.empty
        pure Again

-- A read reached its deadline: which one?
onDeadline : WebSocket -> Int -> IO Step
onDeadline ws udl = do
  t <- nowNs
  cd <- readIORef ws.closeDl
  if udl >= 0 && t >= udl then pure (Out RTimeout) else
    if cd >= 0 && t >= cd
      then do i <- abnormalBy ws True "closing handshake timed out"
              pure (Out (RClosed i))
      else if not ws.timers then pure Again else timerDeadline ws t

-- Bytes came: the keep-alive timer starts again (when it comes).
sawBytes : WebSocket -> IO ()
sawBytes ws = do
  -- (the clock is not read here: `timerDeadline` moves the timer when it
  -- comes, if bytes came since it was set)
  writeIORef ws.sawData True
  writeIORef ws.pongDue (-1)

-- Read more bytes into the read buffer, for a frame of `need` bytes from
-- the current position.
fillBuffer : WebSocket -> Int -> Int -> IO Step
fillBuffer ws udl need = do
  pos <- readIORef ws.rpos
  end <- readIORef ws.rend
  -- (what is left moves to the start when the frame would not fit)
  end <- if pos > 0 && pos + need > ws.rsize
           then do bufCopy ws.rbuf pos (end - pos) ws.rbuf 0
                   writeIORef ws.rpos 0
                   writeIORef ws.rend (end - pos)
                   pure (end - pos)
           else pure end
  dl <- readDeadline ws udl
  n <- transportRecv ws.transport ws.rbuf end (ws.rsize - end) dl
  if n > 0
     then do
       writeIORef ws.rend (end + n)
       if ws.timers && ws.config.pingInterval > 0 then sawBytes ws else pure ()
       pure Again
     else if n == 0 then do
       i <- abnormal ws "the connection ended without a close frame"
       pure (Out (RClosed i))
     else if n == timedOutCode then onDeadline ws udl
     else do
       i <- abnormal ws ("receive failed: " ++ show (codeError n))
       pure (Out (RClosed i))

-- Read more of a frame that has a buffer of its own.
fillBig : WebSocket -> Int -> BigFrame -> IO Step
fillBig ws udl bf = do
  let len = bf.header.payloadLength
  dl <- readDeadline ws udl
  n <- transportRecv ws.transport bf.buf bf.filled (len - bf.filled) dl
  if n > 0
     then do
       if ws.timers && ws.config.pingInterval > 0 then sawBytes ws else pure ()
       let f = bf.filled + n
       if f < len then do writeIORef ws.big (Just ({ filled := f } bf)); pure Again else do
         writeIORef ws.big Nothing
         let raw = UnsafeBS bf.buf 0 len
         case bf.header.maskKey of
           Nothing => pure ()
           Just k => maskInto k 0 raw bf.buf 0
         onFrame ws bf.header raw
     else if n == 0 then do
       i <- abnormal ws "the connection ended without a close frame"
       pure (Out (RClosed i))
     else if n == timedOutCode then onDeadline ws udl
     else do
       i <- abnormal ws ("receive failed: " ++ show (codeError n))
       pure (Out (RClosed i))

-- The reason sent with the close frame for a frame that is not valid.
frameErrorReason : FrameError -> String
frameErrorReason ReservedBitSet = "reserved bit set"
frameErrorReason (ReservedOpcode v) = "reserved opcode " ++ show v
frameErrorReason FragmentedControl = "fragmented control frame"
frameErrorReason ControlTooLong = "control frame longer than 125 bytes"
frameErrorReason MaskMissing = "unmasked frame from a client"
frameErrorReason MaskUnexpected = "masked frame from a server"
frameErrorReason NonMinimalLength = "length not in its shortest form"
frameErrorReason LengthOverflow = "length out of range"
frameErrorReason PayloadTooLarge = "message too big"

-- One step of the receiver: a frame from the buffer, or one read.
readStep : WebSocket -> Int -> IO Step
readStep ws udl = do
  Nothing <- readIORef ws.big
    | Just bf => fillBig ws udl bf
  pos <- readIORef ws.rpos
  end <- readIORef ws.rend
  case decodeHeader ws.opts (UnsafeBS ws.rbuf pos (end - pos)) of
    NeedMore k => fillBuffer ws udl k
    Invalid e => failConnection ws (closeCodeFor e) (frameErrorReason e)
    Header h used => do
      let len = h.payloadLength
      let tot = used + len
      op <- readIORef ws.msgOp
      mlen <- readIORef ws.msgLen
      if h.opcode == Continuation && op /= 0 && mlen + len > ws.config.maxMessageSize
        then failConnection ws 1009 "message too big"
        else if tot <= end - pos
          then do
            let next = pos + tot
            if next == end then do writeIORef ws.rpos 0; writeIORef ws.rend 0
                           else writeIORef ws.rpos next
            p <- payloadOf ws.rbuf (pos + used) len h.maskKey
            onFrame ws h p
          else if tot <= ws.rsize then fillBuffer ws udl tot
          else do
            -- a frame larger than the buffer: a buffer of its own
            b <- bufNew len
            let have = end - pos - used
            bufCopy ws.rbuf (pos + used) have b 0
            writeIORef ws.rpos 0
            writeIORef ws.rend 0
            writeIORef ws.big (Just (MkBigFrame h b have))
            pure Again

readLoop : WebSocket -> Int -> IO RecvResult
readLoop ws udl = do
  s <- readStep ws udl
  case s of
    Again => readLoop ws udl
    Out r => pure r

-- Become the receiver (waiting for another one to finish), or `False` if
-- the connection has ended.
enterReader : WebSocket -> IO Bool
enterReader ws = do
  s <- readIORef ws.state
  if s == stClosed then pure False else do
    r <- readIORef ws.reading
    if r
       then do waitFor ws 100000
               enterReader ws
       else do writeIORef ws.reading True
               n <- readIORef ws.ops
               writeIORef ws.ops (n + 1)
               pure True

recvWith : WebSocket -> Int -> IO RecvResult
recvWith ws udl = do
  mutexAcquire ws.lock
  ok <- enterReader ws
  if not ok then do i <- endedInfo ws; mutexRelease ws.lock; pure (RClosed i) else do
    mutexRelease ws.lock
    r <- readLoop ws udl
    mutexAcquire ws.lock
    writeIORef ws.reading False
    c <- leaveLocked ws
    mutexRelease ws.lock
    closeIf ws c
    pure r

||| The next message, or how the connection ended (then and at every later
||| call).  Waits as long as it takes (the keep-alive and idle timers of the
||| configuration still run).  One thread at a time may receive.
export
receive : WebSocket -> IO (Either CloseInfo Message)
receive ws = do
  r <- recvWith ws (-1)
  case r of
    RMsg m => pure (Right m)
    RClosed i => pure (Left i)
    RTimeout => receive ws

||| `receive` with a deadline (an absolute time in nanoseconds, as
||| `deadlineAfterMs` makes): `Nothing` when it comes first.  The connection
||| stays as it was: a message of which a part has come is read on by the
||| next call.
export
receiveBefore : WebSocket -> (deadline : Int) -> IO (Maybe (Either CloseInfo Message))
receiveBefore ws dl = do
  r <- recvWith ws dl
  case r of
    RMsg m => pure (Just (Right m))
    RClosed i => pure (Just (Left i))
    RTimeout => pure Nothing

-- Wait (with the lock held) until the connection has ended or the deadline.
waitEnded : WebSocket -> Int -> IO Bool
waitEnded ws dl = do
  s <- readIORef ws.state
  if s == stClosed then pure True else do
    t <- nowNs
    if dl >= 0 && t >= dl then pure False else do
      waitFor ws (if dl < 0 then 100000 else max 1 ((dl - t) `div` 1000))
      waitEnded ws dl

||| Close the connection with the closing handshake: send a close frame with
||| the status code (one that may not be sent, see `validCloseCode`, is sent
||| as 1000) and the reason (cut to 123 bytes), and wait for the close frame
||| of the peer, for at most `closeTimeout`.  The messages that come
||| meanwhile are dropped.  If another thread is receiving, it gets the end
||| of the connection; otherwise this call reads the answer itself.  Returns
||| how the connection ended (at once if it has already).
export
closeWebSocket : WebSocket -> (code : Bits16) -> (reason : String) -> IO CloseInfo
closeWebSocket ws code reason = do
  _ <- startClose ws code (fromString reason)
  mutexAcquire ws.lock
  s <- readIORef ws.state
  if s == stClosed then do i <- endedInfo ws; mutexRelease ws.lock; pure i else do
    r <- readIORef ws.reading
    if r
       then do
         -- the receiver will see the answer
         cd <- readIORef ws.closeDl
         ok <- waitEnded ws (if cd < 0 then -1 else cd + 100000000)
         mutexRelease ws.lock
         when (not ok) $ ignore (abnormalBy ws True "closing handshake timed out")
         mutexAcquire ws.lock
         i <- endedInfo ws
         mutexRelease ws.lock
         pure i
       else do
         mutexRelease ws.lock
         cd <- readIORef ws.closeDl
         dl <- if cd >= 0 then pure cd else deadlineAfterMs ws.config.closeTimeout
         r <- recvWith ws dl
         case r of
           RClosed i => pure i
           _ => abnormalBy ws True "closing handshake timed out"

||| Wait until no thread uses the transport of a connection that has ended
||| (the senders and the receiver have returned), so that it can be closed.
export
waitUnused : WebSocket -> IO ()
waitUnused ws = do
  mutexAcquire ws.lock
  loop
  mutexRelease ws.lock
  where
    loop : IO ()
    loop = do
      n <- readIORef ws.ops
      if n <= 0 then pure () else do
        waitFor ws 100000
        loop

--------------------------------------------------------------------------
-- The server side of the handshake
--------------------------------------------------------------------------

||| How a server accepts connections.
public export
record AcceptOptions where
  constructor MkAcceptOptions
  ||| The subprotocols that the server speaks, the one it prefers first: the
  ||| first of them that the client offers is selected; none if the client
  ||| offers none of them.
  subprotocols : List ByteString
  ||| Is a request with this `Origin` (`Nothing` when there is none: not a
  ||| browser) allowed?  The request gets 403 otherwise.
  checkOrigin : Maybe ByteString -> Bool
  ||| More fields for the `101` response.
  headers : Headers
  ||| The limits and timeouts of the connections.
  config : WSConfig

||| No subprotocol, any origin, no more fields, the default configuration.
export
defaultAcceptOptions : AcceptOptions
defaultAcceptOptions = MkAcceptOptions [] (const True) emptyHeaders defaultWSConfig

websocketToken, upgradeToken, version13 : ByteString
websocketToken = "websocket"
upgradeToken = "upgrade"
version13 = "13"

-- The comma-separated elements of the values of a field, without their
-- whitespace, empty ones dropped.
fieldElements : ByteString -> Headers -> List ByteString
fieldElements name hs = concatMap split (lookupHeaders name hs)
  where
    split : ByteString -> List ByteString
    split v = filter (\e => lengthInt e > 0) (map trimOWS (forget (Data.ByteString.split 44 v)))

||| Does the request ask for a WebSocket (an `Upgrade` field with the token
||| `websocket`)?  For serving a path both as a page and as a WebSocket.
export
isWebSocketRequest : Request -> Bool
isWebSocketRequest req = headerHasToken hUpgrade websocketToken req.headers

||| What a valid opening handshake of a client agrees on.
public export
record Handshake where
  constructor MkHandshake
  ||| The `Sec-WebSocket-Key` of the client.
  key : ByteString
  ||| The subprotocol selected.
  subprotocol : Maybe ByteString

-- An error response with fields.
reject : Status -> List (ByteString, ByteString) -> String -> Response
reject st fields msg =
  foldl (\r, (n, v) => withHeader n v r) (textResponse st (msg ++ "\n")) fields

||| Check the opening handshake of a request (RFC 6455 section 4.2.1): the
||| method (`GET`, else 405), the version (HTTP/1.1 or later, else 400),
||| the `Upgrade` field (426 with `Upgrade: websocket` without the token
||| `websocket`), the `Connection` field (400 without the token `upgrade`),
||| `Sec-WebSocket-Version` (426 with `Sec-WebSocket-Version: 13` if it is
||| not 13), one valid `Sec-WebSocket-Key` (400) and the origin (403); and
||| select the subprotocol.  The extensions that the client offers are
||| ignored: none is accepted.
export
checkHandshake : AcceptOptions -> Request -> Either Response Handshake
checkHandshake o req = do
  let hs = req.headers
  when (req.method /= GET) $
    Left (reject statusMethodNotAllowed [("Allow", "GET")] "a WebSocket handshake is a GET request")
  when (req.version < http11) $
    Left (reject statusBadRequest [] "a WebSocket handshake needs HTTP/1.1")
  when (not (headerHasToken hUpgrade websocketToken hs)) $
    Left (reject statusUpgradeRequired [("Upgrade", "websocket"), ("Connection", "Upgrade")]
                 "this resource needs a WebSocket connection")
  when (not (headerHasToken hConnection upgradeToken hs)) $
    Left (reject statusBadRequest [] "the Connection field has no upgrade token")
  when (fieldElements hSecWebSocketVersion hs /= [version13]) $
    Left (reject statusUpgradeRequired [("Sec-WebSocket-Version", "13")]
                 "only version 13 of WebSocket is supported")
  key <- case lookupHeaders hSecWebSocketKey hs of
           [k] => let k' = trimOWS k in
                  if validClientKey k' then Right k'
                  else Left (reject statusBadRequest [] "invalid Sec-WebSocket-Key")
           _ => Left (reject statusBadRequest [] "one Sec-WebSocket-Key is needed")
  when (not (o.checkOrigin (lookupHeader "origin" hs))) $
    Left (reject statusForbidden [] "origin not allowed")
  let offered = fieldElements hSecWebSocketProtocol hs
  pure (MkHandshake key (find (\p => elem p offered) o.subprotocols))

||| The `101` response to a valid handshake, which runs a session on the
||| connection (see `acceptWebSocket`).
export
upgradeResponse : AcceptOptions -> Handshake -> (WebSocket -> IO ()) -> Response
upgradeResponse o h session =
  let proto = case h.subprotocol of
                Nothing => []
                Just p => [MkHeader "Sec-WebSocket-Protocol" p]
      fields = headersFromList ([MkHeader "Upgrade" "websocket", MkHeader "Connection" "Upgrade",
                                 MkHeader "Sec-WebSocket-Accept" (acceptKey h.key)] ++ proto ++
                                headersToList o.headers)
  in respond statusSwitchingProtocols fields (UpgradeBody (run o.config h.subprotocol))
  where
    run : WSConfig -> Maybe ByteString -> Conn -> IO ()
    run cfg proto c = do
      ws <- fromConn False cfg proto c
      -- A crash of the session closes the connection with 1011 (an
      -- unexpected condition), and is then raised again for the crash
      -- boundary of the server, which logs it.
      r <- catchCrash (session ws)
      case r of
        Right () => do
          _ <- closeWebSocket ws 1000 ""
          waitUnused ws
        Left info => do
          _ <- closeWebSocket ws 1011 "internal error"
          waitUnused ws
          assert_total $ idris_crash ("WebSocket session: " ++ show info
                                      ++ maybe "" ("\n" ++) info.backtrace)

||| Answer a request with a WebSocket connection: if the handshake is valid
||| (`checkHandshake`), a `101` response after which the session runs on the
||| connection, in the thread of the connection; the connection is closed
||| (with 1000, if the session did not close it) when the session returns
||| and no other thread uses it any more.  Otherwise the error response.
||| A crash of the session (see `System.Crash`) closes the connection with
||| 1011 instead, and the server logs it.
export
acceptWebSocket : AcceptOptions -> Request -> (WebSocket -> IO ()) -> Response
acceptWebSocket o req session =
  case checkHandshake o req of
    Left r => r
    Right h => upgradeResponse o h session

||| A route of `Network.HTTP.Router` for WebSocket connections on a path
||| pattern: a `GET` with a valid handshake runs the session with the
||| request and the captured segments.
export
websocketRoute : (pattern : String) -> AcceptOptions -> (Request -> Params -> WebSocket -> IO ()) ->
                 Route
websocketRoute p o session = route GET p (\req, ps => pure (acceptWebSocket o req (session req ps)))

--------------------------------------------------------------------------
-- The client side of the handshake
--------------------------------------------------------------------------

||| How a client connects.
public export
record ConnectOptions where
  constructor MkConnectOptions
  ||| The subprotocols to offer, the one preferred first.
  subprotocols : List ByteString
  ||| More fields for the request (`Origin`, `Authorization`, ...).
  headers : Headers
  ||| For resolving the host, connecting, TLS and the handshake.
  timeout : Int
  ||| How to make the TLS transport of a `wss://` URL (as for the HTTP
  ||| client).
  tlsConnect : Maybe TLSConnector
  ||| The size of the read buffer.
  bufferSize : Int
  ||| The limits and timeouts of the connection.
  config : WSConfig

||| No subprotocol, no more fields, 10 s, no TLS, a buffer of 4 KiB, the
||| default configuration.
export
defaultConnectOptions : ConnectOptions
defaultConnectOptions = MkConnectOptions [] emptyHeaders 10000 Nothing 4096 defaultWSConfig

wsBS, wssBS, httpBS', httpsBS' : ByteString
wsBS = "ws"
wssBS = "wss"
httpBS' = "http"
httpsBS' = "https"

||| The target of a `ws://` or `wss://` URL (as an `http` or `https` one).
export
parseWebSocketURL : String -> Either WSError Target
parseWebSocketURL s =
  case parseURI (fromString s) of
    Left e => Left (WSBadURL (show e))
    Right u => do
      when (isJust u.fragment) $ Left (WSBadURL "a WebSocket URL has no fragment")
      sch <- maybe (Left (WSBadURL "no scheme")) Right u.scheme
      http <- if eqLower sch wsBS then Right httpBS'
              else if eqLower sch wssBS then Right httpsBS'
              else Left (WSBadURL ("scheme " ++ toStringLossy sch ++ " is not ws or wss"))
      case uriTarget ({ scheme := Just http } u) of
        Left e => Left (WSBadURL (show e))
        Right t => Right t

-- Check the response to the handshake: the subprotocol.
checkResponse : ByteString -> List ByteString -> ClientResponse -> Either WSError (Maybe ByteString)
checkResponse key offered r = do
  let hs = r.headers
  when (r.status.code /= 101) $ Left (WSRejected r.status)
  when (not (headerHasToken hUpgrade websocketToken hs)) $
    Left (WSBadHandshake "no Upgrade: websocket")
  when (not (headerHasToken hConnection upgradeToken hs)) $
    Left (WSBadHandshake "no Connection: Upgrade")
  when (map trimOWS (lookupHeaders hSecWebSocketAccept hs) /= [acceptKey key]) $
    Left (WSBadHandshake "wrong Sec-WebSocket-Accept")
  when (not (isNil (fieldElements hSecWebSocketExtensions hs))) $
    Left (WSBadHandshake "an extension that was not offered")
  case fieldElements hSecWebSocketProtocol hs of
    [] => Right Nothing
    [p] => if elem p offered then Right (Just p)
           else Left (WSBadHandshake "a subprotocol that was not offered")
    _ => Left (WSBadHandshake "more than one subprotocol")

||| The opening handshake of a client on a connection made by hand: send
||| the request for a target (a path and a `Host` field) and check the
||| response; the connection is then a WebSocket connection of the client.
||| The connection is closed if the handshake fails.
export
clientHandshake : ConnectOptions -> Conn -> (hostField : ByteString) -> (path : ByteString) ->
                  (deadline : Int) -> IO (Either WSError WebSocket)
clientHandshake o c host path dl = do
  Just nonce <- randomBytes 16
    | Nothing => do closeConn c; pure (Left (WSBadHandshake "no random source"))
  let key = encodeKey nonce
  let protos = o.subprotocols
  let hs0 = addHeader "Host" host $
            addHeader "Upgrade" "websocket" $
            addHeader "Connection" "Upgrade" $
            addHeader "Sec-WebSocket-Key" key $
            addHeader "Sec-WebSocket-Version" "13" emptyHeaders
  let hs1 = if isNil protos then hs0
            else addHeader "Sec-WebSocket-Protocol" (Data.ByteString.intercalate ", " protos) hs0
  let hs = foldl (\acc, h => addHeader h.name h.value acc) hs1 (headersToList o.headers)
  Right () <- writeRequest c (MkClientRequest GET path hs NoRequestBody) dl
    | Left e => do closeConn c; pure (Left (WSHttpError e))
  Right resp <- readResponse c defaultLimits GET True dl
    | Left e => do closeConn c; pure (Left (WSHttpError e))
  case checkResponse key protos resp of
    Left e => do closeConn c; pure (Left e)
    Right p => Right <$> fromConn True o.config p c
  where
    encodeKey : ByteString -> ByteString
    encodeKey n = fromMaybe Data.ByteString.empty (clientKey n)

||| Connect to a `ws://` URL (or a `wss://` one, with `tlsConnect`), within
||| the timeout: resolve the host, connect, send the handshake with a random
||| key and the subprotocols offered, and check the response (101, the
||| `Upgrade` and `Connection` fields, `Sec-WebSocket-Accept`, a
||| subprotocol among those offered, no extension).
export
connectWebSocket : ConnectOptions -> (url : String) -> IO (Either WSError WebSocket)
connectWebSocket o url = do
  Right t <- pure (parseWebSocketURL url)
    | Left e => pure (Left e)
  dl <- deadlineAfterMs o.timeout
  Right s <- connectHost t.host t.port (if dl < 0 then Nothing else Just dl)
    | Left Timeout => pure (Left (WSHttpError TimedOut))
    | Left e => pure (Left (WSNetFailure e))
  ignore (setOption s NoDelay 1)
  tr <- the (IO (Either WSError Transport)) $
        if not t.secure then pure (Right (socketTransport s Nothing)) else
          case o.tlsConnect of
            Nothing => do
              ignore (close s)
              pure (Left (WSBadURL "wss needs a TLS transport: set tlsConnect of the ConnectOptions (see the tls library)"))
            Just tls => do
              Right tr <- tls t.host t.port s dl
                | Left msg => pure (Left (WSHttpError (OtherError ("TLS: " ++ msg))))
              pure (Right tr)
  case tr of
    Left e => pure (Left e)
    Right tr => do
      c <- newConn tr o.bufferSize
      clientHandshake o c t.hostField t.path dl
