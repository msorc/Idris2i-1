||| HTTP/2 connections (RFC 9113): the state machine of a connection and of
||| its streams over a `Conn`, for the server (`Network.HTTP.Server` serves
||| its handlers through it) and for the client (`Network.HTTP.Client`).
|||
||| # Threads
|||
||| A connection has
|||
|||  * a reader: the thread that runs `runServer` (or the one that
|||    `startClient` forks), which reads and decodes every frame, keeps the
|||    HPACK decoder (in frame order), and updates the state of the
|||    connection and of its streams;
|||  * a writer, forked at the start, which takes what the other threads
|||    queue (control frames, field lists, DATA) and writes it in queue
|||    order: frames never interleave, and the HPACK encoder is used only by
|||    the writer, in the order in which the blocks go out;
|||  * on the server, a thread per stream that runs the handler (on the
|||    client, the threads that make requests).
|||
||| All the state is under one lock per connection.  A thread that reads a
||| body waits on the condition of its stream; a thread that writes a body
||| waits on the condition of the connection until the windows of the peer
||| and the outbound buffers have room (or until its write timeout).
|||
||| # Flow control
|||
||| Received DATA is credited back to the peer (WINDOW_UPDATE) when the
||| application reads it, half a window at a time, so a handler that does
||| not read its body stops the peer once the window of its stream is
||| full, instead of making the server buffer without bound.  DATA is sent
||| within the windows of the peer, in frames of at most its
||| `SETTINGS_MAX_FRAME_SIZE`; what is queued for the writer is bounded per
||| stream and per connection (`streamBufferSize`, `connectionBufferSize`).
|||
||| # A reset stream
|||
||| When the peer resets a stream (RST_STREAM), the reads of its body fail
||| (`OtherError "stream reset ..."`), its writes fail, and what was queued
||| for it is dropped.  The thread that runs its handler is not stopped (the
||| runtime cannot stop a thread): it goes on until it returns, and each of
||| its later reads and writes of the stream fails at once.
|||
||| # Limits
|||
||| See `H2Config`: the number of streams at a time (REFUSED_STREAM beyond
||| it), the size of a header list (431) and of a header block with its
||| CONTINUATION frames (ENHANCE_YOUR_CALM beyond it), the control frames
||| queued for a peer that does not read them, resets and empty frames per
||| second (both ENHANCE_YOUR_CALM), and the settings timeout.
module Network.HTTP2.Connection

import Data.Buffer
import Data.ByteString
import Data.ByteString.Builder
import Data.ByteString.Internal
import Data.IORef
import Data.List
import Data.Maybe
import Data.SortedMap
import Network.HTTP.Connection
import Network.HTTP.Internal.Bytes
import Network.HTTP.Transport
import Network.HTTP.Types
import public Network.HTTP2.Config
import public Network.HTTP2.Frame
import public Network.HTTP2.HPACK
import System.Concurrency

%default covering

--------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------

-- The state of a stream (under the lock of the connection).
record SState where
  constructor MkSState
  -- the peer ended its side (END_STREAM), or the stream was reset
  remoteEnded : Bool
  -- we ended our side (END_STREAM queued)
  localEnded : Bool
  -- reset (by either side): its queued frames are dropped
  reset : Bool
  -- what is received from now on is dropped (and credited)
  ignoreInput : Bool
  -- the handler (or the client request) is done with the stream
  done : Bool
  -- the received DATA not read yet (front, and back in reverse)
  inFront : List ByteString
  inBack : List ByteString
  inBytes : Int
  -- what the peer may still send, and what was read but not credited
  recvWindow : Int
  unacked : Int
  -- what we may still send, and what is queued for the writer
  sendWindow : Int
  queued : Int
  -- received DATA bytes, and the content-length of the message if any
  received : Int
  contentLength : Maybe Int
  trailers : Headers
  -- why reading fails
  failure : Maybe HttpError
  -- (client) the head of the response: the status and the fields
  response : Maybe (Int, Headers)

||| A stream of a connection.
export
record H2Stream where
  constructor MkStream
  sid : Int
  st : IORef SState
  cond : Condition

-- What the writer writes.
data Out
  = OFrame Frame
  | OHeaders H2Stream (List HeaderField) Bool
  | OData H2Stream ByteString Bool
  | -- a new limit of the dynamic table of the peer's decoder
    OTableSize Int
  | -- bytes as they are (the preface of a client)
    ORaw ByteString

-- The state of a connection (under its lock).
record CState where
  constructor MkCState
  streams : SortedMap Int H2Stream
  -- the highest stream id that the peer opened, and the next of ours
  lastPeer : Int
  nextLocal : Int
  -- the streams (of the peer on a server, ours on a client) that count
  -- towards the limit, and the handler threads that run
  openCount : Int
  handlers : Int
  sendWindow : Int
  recvWindow : Int
  unacked : Int
  peer : Settings
  -- the queue, the last first; the control frames and DATA bytes in it
  queue : List Out
  ctrl : Int
  queuedBytes : Int
  -- the writer is to end once the queue is empty
  closing : Bool
  -- the transport failed or the connection ended: no more I/O
  dead : Bool
  writerDone : Bool
  goawaySent : Bool
  -- (client) the last stream that the peer said it will process
  goawayRecv : Maybe Int
  settingsAcked : Bool
  -- the counts of the current second, and when it began
  resets : Int
  empties : Int
  windowStart : Int
  -- why the connection ended, if it did
  endError : Maybe ErrorCode
  -- the streams that were closed last (between 128 and 256 of them, and
  -- how many), whose late frames are ignored
  recentlyClosed : List Int
  closedCount : Int

||| An HTTP/2 connection.
export
record H2Conn where
  constructor MkH2Conn
  cfg : H2Config
  isServer : Bool
  conn : Conn
  lock : Mutex
  outCond : Condition
  flowCond : Condition
  st : IORef CState
  enc : IORef EncoderState
  dec : IORef DecoderState
  ||| Each write must be done within this time (ms; 0 for none).
  writeTimeout : Int
  ||| Each read of a body must bring something within this time.
  readTimeout : Int
  ||| How long a connection without streams stays open.
  idleTimeout : Int
  log : String -> IO ()

newSState : (sendWindow, recvWindow : Int) -> SState
newSState sw rw = MkSState False False False False False [] [] 0 rw 0 sw 0 0 Nothing emptyHeaders Nothing Nothing

newStream : Int -> SState -> IO H2Stream
newStream i s = [| MkStream (pure i) (newIORef s) makeCondition |]

--------------------------------------------------------------------------
-- Locking and queueing (the callers hold the lock where it says so)
--------------------------------------------------------------------------

lockC : H2Conn -> IO ()
lockC c = mutexAcquire c.lock

unlockC : H2Conn -> IO ()
unlockC c = mutexRelease c.lock

getC : H2Conn -> IO CState
getC c = readIORef c.st

putC : H2Conn -> CState -> IO ()
putC c s = writeIORef c.st s

-- Queue an item (lock held).
enqueue : H2Conn -> Out -> IO ()
enqueue c o = do
  s <- getC c
  if s.closing then pure () else do
    putC c ({ queue $= (o ::) } s)
    conditionSignal c.outCond

-- Queue a control frame (lock held): False if the peer has too many
-- waiting already.
enqueueControl : H2Conn -> Frame -> IO Bool
enqueueControl c f = do
  s <- getC c
  if s.closing then pure True else do
    let n = s.ctrl + 1
    putC c ({ queue $= (OFrame f ::), ctrl := n } s)
    conditionSignal c.outCond
    pure (n <= c.cfg.maxQueuedControlFrames)

-- Start a new second for the abuse counters if this one is over (lock
-- held).
tickWindow : H2Conn -> IO ()
tickWindow c = do
  t <- nowNs
  s <- getC c
  when (t - s.windowStart > 1000000000) $ putC c ({ resets := 0, empties := 0, windowStart := t } s)

-- Count an empty frame (lock held): False beyond the limit.
countEmpty : H2Conn -> IO Bool
countEmpty c = do
  tickWindow c
  s <- getC c
  putC c ({ empties $= (+ 1) } s)
  pure (s.empties + 1 <= c.cfg.maxEmptyFramesPerSecond)

-- Count a reset of a stream in progress (lock held): False beyond the
-- limit.
countReset : H2Conn -> IO Bool
countReset c = do
  tickWindow c
  s <- getC c
  putC c ({ resets $= (+ 1) } s)
  pure (s.resets + 1 <= c.cfg.maxResetsPerSecond)

modifyS : H2Stream -> (SState -> SState) -> IO ()
modifyS s f = modifyIORef s.st f

-- Take a stream out of the connection once both sides are done with it
-- (lock held).
maybeRemove : H2Conn -> H2Stream -> IO ()
maybeRemove c s = do
  ss <- readIORef s.st
  when ((ss.remoteEnded || ss.ignoreInput) && (ss.localEnded || ss.reset)) $ do
    cs <- getC c
    case lookup s.sid cs.streams of
      Nothing => pure ()
      Just _ =>
        let (l, k) = if cs.closedCount >= 256 then (take 128 cs.recentlyClosed, 128)
                     else (cs.recentlyClosed, cs.closedCount) in
        putC c ({ streams $= delete s.sid, openCount $= (\n => n - 1),
                  recentlyClosed := s.sid :: l, closedCount := k + 1 } cs)

-- Credit the peer for `n` bytes of the connection that were read or
-- dropped (lock held).
creditConn : H2Conn -> Int -> IO ()
creditConn c n = when (n > 0) $ do
  cs <- getC c
  let u = cs.unacked + n
  if u >= c.cfg.connectionWindowSize `div` 2
     then do putC c ({ unacked := 0, recvWindow $= (+ u) } cs)
             enqueue c (OFrame (WindowUpdate 0 u))
     else putC c ({ unacked := u } cs)

-- Credit the peer for `n` bytes of a stream that were read (lock held).
creditStream : H2Conn -> H2Stream -> Int -> IO ()
creditStream c s n = when (n > 0) $ do
  ss <- readIORef s.st
  let u = ss.unacked + n
  if not ss.remoteEnded && not ss.ignoreInput && u >= c.cfg.initialWindowSize `div` 2
     then do writeIORef s.st ({ unacked := 0, recvWindow $= (+ u) } ss)
             enqueue c (OFrame (WindowUpdate s.sid u))
     else writeIORef s.st ({ unacked := u } ss)

-- Fail the reads of a stream and wake up its threads (lock held).
failStream : H2Conn -> H2Stream -> HttpError -> IO ()
failStream c s e = do
  modifyS s (\ss => { failure := Just (fromMaybe e ss.failure), remoteEnded := True } ss)
  conditionBroadcast s.cond

-- Reset a stream (lock held): queue RST_STREAM, drop what is queued.
resetStream : H2Conn -> H2Stream -> ErrorCode -> IO Bool
resetStream c s code = do
  ss <- readIORef s.st
  if ss.reset then pure True else do
    writeIORef s.st ({ reset := True, ignoreInput := True, localEnded := True } ss)
    creditConn c ss.inBytes
    failStream c s (OtherError ("stream reset: " ++ show code))
    conditionBroadcast c.flowCond
    ok <- enqueueControl c (RstStream s.sid code)
    maybeRemove c s
    pure ok

-- End the connection (lock held): GOAWAY with the code unless one was
-- sent, then the writer ends once it has written the queue; every stream
-- fails.
endConn : H2Conn -> ErrorCode -> String -> IO ()
endConn c code msg = do
  cs <- getC c
  when (not cs.goawaySent) $
    enqueue c (OFrame (GoAway cs.lastPeer code (fromString msg)))
  cs <- getC c
  putC c ({ goawaySent := True, closing := True, endError := Just (fromMaybe code cs.endError) } cs)
  conditionSignal c.outCond
  traverse_ (\s => failStream c s UnexpectedEnd) (values cs.streams)
  conditionBroadcast c.flowCond

--------------------------------------------------------------------------
-- The writer
--------------------------------------------------------------------------

-- The frames of a header block: HEADERS then CONTINUATION frames of at
-- most `size` bytes.
headerFrames : Int -> Bool -> Int -> ByteString -> Builder
headerFrames sid endStream size block =
  let n = lengthInt block in
  if n <= size then encodeFrame (Headers sid endStream True Nothing Nothing block)
   else encodeFrame (Headers sid endStream False Nothing Nothing (takeInt size block))
       <+> conts (dropInt size block)
  where
    conts : ByteString -> Builder
    conts b = let m = lengthInt b in
              if m <= size then encodeFrame (Continuation sid True b)
               else encodeFrame (Continuation sid False (takeInt size b)) <+> conts (assert_smaller b (dropInt size b))

-- What the writer does with one item: its bytes, and the DATA bytes it
-- frees.
record Written where
  constructor MkWritten
  bytes : Builder
  size : Int

-- Encode the items (the oldest first) of a batch.  Items of streams that
-- were reset are dropped (the windows that their DATA took come back).
encodeItems : H2Conn -> Int -> List Out -> Builder -> Int -> IO (Builder, Int)
encodeItems c fsize [] acc n = pure (acc, n)
encodeItems c fsize (o :: os) acc n =
  case o of
    OFrame f => encodeItems c fsize os (acc <+> encodeFrame f) n
    ORaw b => encodeItems c fsize os (acc <+> byteString b) n
    OTableSize t => do
      modifyIORef c.enc (setEncoderTableLimit t)
      encodeItems c fsize os acc n
    OHeaders s fields end => do
      ss <- readIORef s.st
      if ss.reset then encodeItems c fsize os acc n else do
        e <- readIORef c.enc
        let (blk, e') = encodeHeaderBlock e fields
        writeIORef c.enc e'
        encodeItems c fsize os (acc <+> headerFrames s.sid end fsize (toByteString blk)) n
    OData s bs end => do
      ss <- readIORef s.st
      if ss.reset then encodeItems c fsize os acc n else
        encodeItems c fsize os (acc <+> encodeFrame (DataFrame s.sid end Nothing bs)) n

-- The DATA items of a batch, for the accounting after the write.
dataItems : List Out -> List (H2Stream, Int)
dataItems [] = []
dataItems (OData s bs _ :: os) = (s, lengthInt bs) :: dataItems os
dataItems (_ :: os) = dataItems os

-- Give back the room that the DATA of a batch took in the buffers (lock
-- held); for streams that were reset, the windows too.
release : H2Conn -> List (H2Stream, Int) -> IO ()
release c [] = pure ()
release c ((s, n) :: rest) = do
  ss <- readIORef s.st
  writeIORef s.st ({ queued $= (\q => q - n) } ss)
  cs <- getC c
  putC c ({ queuedBytes $= (\q => q - n), sendWindow $= (if ss.reset then (+ n) else id) } cs)
  release c rest

-- Wait for the queue, take it, write it; again until the connection ends.
writerLoop : H2Conn -> IO ()
writerLoop c = do
  lockC c
  waitWork
  cs <- getC c
  if isNil cs.queue
     then do
       -- closing, and everything is out
       putC c ({ writerDone := True } cs)
       conditionBroadcast c.flowCond
       unlockC c
     else do
       let items = reverse cs.queue
       putC c ({ queue := [], ctrl := 0 } cs)
       let fsize = cs.peer.maxFrameSize
       unlockC c
       (b, _) <- encodeItems c fsize items empty 0
       let bs = toByteString b
       dl <- deadlineAfterMs c.writeTimeout
       r <- transportSendAll (connTransport c.conn) (unsafeBuffer bs) (unsafeOffset bs) (lengthInt bs) dl
       lockC c
       release c (dataItems items)
       conditionBroadcast c.flowCond
       if r < 0
          then do
            cs <- getC c
            putC c ({ dead := True, closing := True, writerDone := True, queue := [] } cs)
            traverse_ (\s => failStream c s (codeToError r)) (values cs.streams)
            conditionBroadcast c.flowCond
            unlockC c
            -- wake up the reader
            transportShutdown (connTransport c.conn) ShutBoth
          else do
            unlockC c
            writerLoop c
  where
    waitWork : IO ()
    waitWork = do
      cs <- getC c
      if not (isNil cs.queue) || cs.closing then pure () else do
        conditionWait c.outCond c.lock
        waitWork

--------------------------------------------------------------------------
-- Sending (from the threads of the streams)
--------------------------------------------------------------------------

-- Wait on the condition of the connection until a deadline (lock held):
-- False once the deadline has passed.
waitFlow : H2Conn -> Int -> IO Bool
waitFlow c dl =
  if dl < 0 then do conditionWait c.flowCond c.lock; pure True else do
    t <- nowNs
    if t >= dl then pure False else do
      conditionWaitTimeout c.flowCond c.lock (max 1 ((dl - t) `div` 1000))
      pure True

streamGone : HttpError
streamGone = OtherError "the stream was reset or the connection ended"

||| Queue the head of a message on a stream: a field list (names in lower
||| case, pseudo-header fields first), with END_STREAM if there is no
||| body.
export
sendHeaders : H2Conn -> H2Stream -> List HeaderField -> (endStream : Bool) -> IO (Either HttpError ())
sendHeaders c s fields end = do
  lockC c
  cs <- getC c
  ss <- readIORef s.st
  if cs.closing || ss.reset || ss.localEnded
     then do unlockC c; pure (Left streamGone)
     else do
       when end $ writeIORef s.st ({ localEnded := True } ss)
       enqueue c (OHeaders s fields end)
       when end $ maybeRemove c s
       unlockC c
       pure (Right ())

-- Send bytes of a body from an offset, within the windows and the
-- buffers, and END_STREAM with the last frame if asked.
sendLoop : H2Conn -> H2Stream -> ByteString -> Int -> Bool -> Int -> IO (Either HttpError ())
sendLoop c s bs off end dl = do
  let n = lengthInt bs - off
  cs <- getC c
  ss <- readIORef s.st
  if cs.closing || ss.reset || ss.localEnded then pure (Left streamGone)
   else if n <= 0
    then do
      when end $ do
        writeIORef s.st ({ localEnded := True } ss)
        enqueue c (OData s Data.ByteString.empty True)
        maybeRemove c s
      pure (Right ())
   else do
    let room = min (c.cfg.streamBufferSize - ss.queued) (c.cfg.connectionBufferSize - cs.queuedBytes)
    let k = min n (min (min ss.sendWindow cs.sendWindow) (min cs.peer.maxFrameSize room))
    if k <= 0
       then do
         ok <- waitFlow c dl
         if ok then sendLoop c s bs off end dl else pure (Left TimedOut)
       else do
         let last = end && k == n
         writeIORef s.st ({ sendWindow $= (\w => w - k), queued $= (+ k), localEnded := last } ss)
         putC c ({ sendWindow $= (\w => w - k), queuedBytes $= (+ k) } cs)
         enqueue c (OData s (sliceFromTo off (off + k) bs) last)
         when last $ maybeRemove c s
         if k == n then pure (Right ()) else sendLoop c s bs (off + k) end dl

||| Send bytes of a body on a stream (waiting for the windows of the peer,
||| for at most the write timeout), with END_STREAM after them if asked.
||| A timeout resets the stream (CANCEL).
export
sendData : H2Conn -> H2Stream -> ByteString -> (endStream : Bool) -> IO (Either HttpError ())
sendData c s bs end = do
  dl <- deadlineAfterMs c.writeTimeout
  lockC c
  r <- sendLoop c s bs 0 end dl
  case r of
    Left TimedOut => ignore (resetStream c s Cancel)
    _ => pure ()
  unlockC c
  pure r

||| A writer of the body of a stream (DATA frames; `finishBody` sends
||| END_STREAM): exactly `length` bytes if it is given.
export
dataWriter : H2Conn -> H2Stream -> (length : Maybe Int) -> IO BodyWriter
dataWriter c s len = sinkWriter len (\bs => sendData c s bs False) (sendData c s Data.ByteString.empty True)

||| Reset a stream with an error code (when it was not reset yet).
export
cancelStream : H2Conn -> H2Stream -> ErrorCode -> IO ()
cancelStream c s code = do
  lockC c
  ignore (resetStream c s code)
  unlockC c

--------------------------------------------------------------------------
-- Receiving (from the threads of the streams)
--------------------------------------------------------------------------

-- The next piece of the body of a stream (lock held).
nextPiece : H2Conn -> H2Stream -> Int -> IO (Either HttpError (Maybe ByteString))
nextPiece c s dl = do
  ss <- readIORef s.st
  case ss.inFront of
    (x :: xs) => do
      writeIORef s.st ({ inFront := xs, inBytes $= (\b => b - lengthInt x) } ss)
      creditStream c s (lengthInt x)
      creditConn c (lengthInt x)
      pure (Right (Just x))
    [] =>
      if not (isNil ss.inBack)
         then do writeIORef s.st ({ inFront := reverse ss.inBack, inBack := [] } ss)
                 nextPiece c s dl
       else case ss.failure of
        Just e => pure (Left e)
        Nothing =>
          if ss.remoteEnded then pure (Right Nothing) else do
            t <- nowNs
            if dl >= 0 && t >= dl then pure (Left TimedOut) else do
              if dl < 0 then conditionWait s.cond c.lock
                        else conditionWaitTimeout s.cond c.lock (max 1 ((dl - t) `div` 1000))
              nextPiece c s dl

||| The reader of the body of a stream, which credits the peer as it reads.
export
streamBody : H2Conn -> H2Stream -> IO BodyReader
streamBody c s = sourceReader (MkBodySource next trailers)
  where
    next : IO (Either HttpError (Maybe ByteString))
    next = do
      dl <- deadlineAfterMs c.readTimeout
      lockC c
      r <- nextPiece c s dl
      unlockC c
      pure r
    trailers : IO Headers
    trailers = do
      lockC c
      ss <- readIORef s.st
      unlockC c
      pure ss.trailers

--------------------------------------------------------------------------
-- Header fields
--------------------------------------------------------------------------

isPseudo : ByteString -> Bool
isPseudo n = lengthInt n > 0 && unsafeIndex n 0 == 58

-- A name in lower case without other bytes than those of a token (RFC
-- 9113 section 8.2.1).
validName : ByteString -> Int -> Int -> Bool
validName n i len =
  if i >= len then True
   else let w = unsafeIndex n i in
       if w >= 65 && w <= 90 then False
        else if isTChar w then validName n (i + 1) len
        else False

-- No NUL, CR or LF, and no leading or trailing space or tab.
validValue : ByteString -> Int -> Int -> Bool
validValue v i len =
  if i >= len then True
   else let w = unsafeIndex v i in
       if w == 0 || w == 10 || w == 13 then False else validValue v (i + 1) len

okValue : ByteString -> Bool
okValue v =
  let n = lengthInt v in
  validValue v 0 n && (n == 0 || (not (isOWS (unsafeIndex v 0)) && not (isOWS (unsafeIndex v (n - 1)))))

connectionSpecific : ByteString -> Bool
connectionSpecific n =
  n == hConnection || n == "keep-alive" || n == "proxy-connection" || n == hTransferEncoding || n == "upgrade"

||| The pseudo-header fields of a request, and its other fields.
public export
record H2Request where
  constructor MkH2Request
  method : ByteString
  scheme : Maybe ByteString
  authority : Maybe ByteString
  path : Maybe ByteString
  ||| The other fields (names in lower case), `cookie` fields joined.
  fields : Headers
  contentLength : Maybe Int

-- Check the regular fields of a message (trailers too): the fields as
-- Headers (the last first), the cookies, and the content-length.
checkFields : List HeaderField -> List Header -> List ByteString -> Maybe Int ->
              Either String (List Header, List ByteString, Maybe Int)
checkFields [] acc cookies cl = Right (acc, cookies, cl)
checkFields (f :: fs) acc cookies cl =
  let n = f.name
      v = f.value
  in if isPseudo n then Left "pseudo-header field after a regular field"
     else if lengthInt n == 0 || not (validName n 0 (lengthInt n)) then Left "field name not valid (or not in lower case)"
     else if not (okValue v) then Left "field value not valid"
     else if connectionSpecific n then Left "connection-specific field"
     else if n == "te" && v /= "trailers" then Left "te other than trailers"
     else if n == "cookie" then checkFields fs acc (v :: cookies) cl
     else if n == hContentLength
       then let k = parseDecimal v in
            if k < 0 then Left "content-length not valid"
             else case cl of
                   Just k' => if k' /= k then Left "two content-length values" else checkFields fs acc cookies cl
                   Nothing => checkFields fs (MkHeader n v :: acc) cookies (Just k)
     else checkFields fs (MkHeader n v :: acc) cookies cl

-- The fields with the cookies joined (RFC 9113 section 8.2.3).
withCookies : List Header -> List ByteString -> Headers
withCookies acc [] = headersFromListRev acc
withCookies acc cs = headersFromListRev (MkHeader "cookie" (intercalate "; " (reverse cs)) :: acc)

-- The pseudo-header fields of a request (section 8.3.1).
record Pseudo where
  constructor MkPseudo
  method, scheme, authority, path : Maybe ByteString

pMethod, pScheme, pAuthority, pPath : ByteString
pMethod = ":method"
pScheme = ":scheme"
pAuthority = ":authority"
pPath = ":path"

pseudoRequest : List HeaderField -> Pseudo -> Either String (Pseudo, List HeaderField)
pseudoRequest [] p = Right (p, [])
pseudoRequest (f :: fs) p =
  if not (isPseudo f.name) then Right (p, f :: fs) else
    let v = Just f.value
        n = f.name in
    if n == pPath then (if isJust p.path then Left "two :path" else pseudoRequest fs ({ path := v } p))
    else if n == pMethod then (if isJust p.method then Left "two :method" else pseudoRequest fs ({ method := v } p))
    else if n == pScheme then (if isJust p.scheme then Left "two :scheme" else pseudoRequest fs ({ scheme := v } p))
    else if n == pAuthority then (if isJust p.authority then Left "two :authority" else pseudoRequest fs ({ authority := v } p))
    else Left ("pseudo-header field " ++ toStringLossy n ++ " in a request")

||| Check the header list of a request (RFC 9113 section 8.3.1): the
||| head, or why the request is malformed.
export
checkRequest : List HeaderField -> Either String H2Request
checkRequest fs = do
  (p, rest) <- pseudoRequest fs (MkPseudo Nothing Nothing Nothing Nothing)
  m <- maybe (Left "no :method") Right p.method
  if m == "CONNECT"
     then when (isJust p.scheme || isJust p.path || isNothing p.authority) $ Left "CONNECT with :scheme or :path, or without :authority"
     else do
       when (isNothing p.scheme) $ Left "no :scheme"
       case p.path of
         Nothing => Left "no :path"
         Just x => when (lengthInt x == 0) $ Left "empty :path"
  (acc, cookies, cl) <- checkFields rest [] [] Nothing
  pure (MkH2Request m p.scheme p.authority p.path (withCookies acc cookies) cl)

-- The status of a response, and its other fields.
checkResponse : List HeaderField -> Either String (Int, Headers, Maybe Int)
checkResponse (f :: fs) =
  if f.name /= ":status" then Left "no :status first" else do
    let code = parseDecimal f.value
    when (code < 100 || code > 999 || lengthInt f.value /= 3) $ Left ":status not valid"
    (acc, cookies, cl) <- checkFields fs [] [] Nothing
    pure (code, withCookies acc cookies, cl)
checkResponse [] = Left "no :status"

-- Trailers: no pseudo-header fields.
checkTrailers : List HeaderField -> Either String Headers
checkTrailers fs = do
  (acc, cookies, _) <- checkFields fs [] [] Nothing
  pure (withCookies acc cookies)

||| The fields of a message for HTTP/2: names in lower case, without the
||| fields that are specific to an HTTP/1.1 connection (and `te` other
||| than `trailers`).
export
toFields : Headers -> List HeaderField
toFields hs = mapMaybe conv (headersToList hs)
  where
    conv : Header -> Maybe HeaderField
    conv h = let n = lowerAscii h.name in
             if connectionSpecific n || n == hHost || (n == "te" && h.value /= "trailers") then Nothing
              else Just (MkHeaderField n h.value False)

--------------------------------------------------------------------------
-- Making connections
--------------------------------------------------------------------------

ourSettings : H2Config -> Bool -> List (SettingId, Bits32)
ourSettings cfg server =
  (if server then [] else [(EnablePush, 0)]) ++
  [ (MaxConcurrentStreams, cast cfg.maxConcurrentStreams)
  , (InitialWindowSize, cast cfg.initialWindowSize)
  , (MaxHeaderListSize, cast cfg.maxHeaderListSize)
  , (HeaderTableSize, cast cfg.headerTableSize) ]

newH2Conn : H2Config -> Bool -> Conn -> (writeTimeout, readTimeout, idleTimeout : Int) ->
            (String -> IO ()) -> IO H2Conn
newH2Conn cfg server c wt rt it log = do
  t <- nowNs
  let cs = MkCState empty 0 1 0 0 65535 65535 0 defaultSettings [] 0 0 False False False False
                    Nothing False 0 0 t Nothing [] 0
  [| MkH2Conn (pure cfg) (pure server) (pure c) makeMutex makeCondition makeCondition
              (newIORef cs) (newIORef (newEncoder 4096 True))
              (newIORef (newDecoder cfg.headerTableSize cfg.maxHeaderListSize))
              (pure wt) (pure rt) (pure it) (pure log) |]

-- Queue our SETTINGS and the larger window of the connection, and start
-- the writer.
start : H2Conn -> IO ()
start c = do
  lockC c
  enqueue c (OFrame (SettingsFrame False (ourSettings c.cfg c.isServer)))
  let extra = c.cfg.connectionWindowSize - 65535
  when (extra > 0) $ do
    enqueue c (OFrame (WindowUpdate 0 extra))
    cs <- getC c
    putC c ({ recvWindow := c.cfg.connectionWindowSize } cs)
  unlockC c
  _ <- fork (writerLoop c)
  pure ()

-- Wait (at most until the deadline, or for ever if it is below 0) for the
-- writer to end: True if it has.
waitWriter : H2Conn -> Int -> IO Bool
waitWriter c dl = do
  lockC c
  r <- go
  unlockC c
  pure r
  where
    go : IO Bool
    go = do
      cs <- getC c
      if cs.writerDone then pure True else do
        ok <- waitFlow c dl
        if ok then go else pure False

--------------------------------------------------------------------------
-- The reader
--------------------------------------------------------------------------

-- A header block being received: its stream, END_STREAM, the fragments
-- (the last first), their size and number.
record Block where
  constructor MkBlock
  sid : Int
  endStream : Bool
  frags : List ByteString
  size : Int
  count : Int

-- What the reader does next.
data Step = Go | Stop

-- What happens to the stream of a complete header block.
record Handlers where
  constructor MkHandlers
  -- (server) a new request: run it (in a thread of its own)
  onRequest : H2Stream -> H2Request -> IO ()
  -- (server) a request whose header list was too large (answer 431)
  onTooLarge : H2Stream -> IO ()

-- A connection error: GOAWAY and stop.
connError : H2Conn -> ErrorCode -> String -> IO Step
connError c code msg = do
  lockC c
  endConn c code msg
  unlockC c
  pure Stop

-- Reset a stream from the reader; a connection error if the peer has too
-- many control frames waiting.
streamError : H2Conn -> H2Stream -> ErrorCode -> IO Step
streamError c s code = do
  lockC c
  ok <- resetStream c s code
  unlockC c
  if ok then pure Go else connError c EnhanceYourCalm "too many queued control frames"

-- RST_STREAM for a stream that the connection does not keep.
rstId : H2Conn -> Int -> ErrorCode -> IO Step
rstId c i code = do
  lockC c
  ok <- enqueueControl c (RstStream i code)
  unlockC c
  if ok then pure Go else connError c EnhanceYourCalm "too many queued control frames"

lookupStream : H2Conn -> Int -> IO (Maybe H2Stream)
lookupStream c i = do
  lockC c
  cs <- getC c
  unlockC c
  pure (lookup i cs.streams)

-- Is the stream id one of those the peer opens (odd for a client)?
peerId : H2Conn -> Int -> Bool
peerId c i = if c.isServer then i `mod` 2 == 1 else i `mod` 2 == 0

pushPiece : ByteString -> List ByteString -> List ByteString
pushPiece p xs = if lengthInt p > 0 then p :: xs else xs

-- DATA on a stream.
onData : H2Conn -> Int -> Bool -> Int -> ByteString -> IO Step
onData c i end flowLen payload = do
  lockC c
  cs <- getC c
  if flowLen > cs.recvWindow
     then do unlockC c; connError c FlowControlError "DATA beyond the window of the connection"
     else do
       putC c ({ recvWindow $= (\w => w - flowLen) } cs)
       let n = lengthInt payload
       -- (padding is credited at once)
       creditConn c (flowLen - n)
       emptyOk <- if n == 0 && not end then countEmpty c else pure True
       if not emptyOk then do unlockC c; connError c EnhanceYourCalm "too many empty frames" else do
         case lookup i cs.streams of
           Nothing => do
             creditConn c n
             unlockC c
             if i > cs.lastPeer && peerId c i
                then connError c ProtocolError "DATA on an idle stream"
                else if elem i cs.recentlyClosed || not (peerId c i) then pure Go
                else connError c StreamClosed "DATA on a closed stream"
           Just s => do
             ss <- readIORef s.st
             if ss.ignoreInput then do creditConn c n; unlockC c; pure Go
              else if ss.remoteEnded then do creditConn c n; unlockC c; streamError c s StreamClosed
              else if flowLen > ss.recvWindow then do creditConn c n; unlockC c; streamError c s FlowControlError
              else do
               let got = ss.received + n
               let ss' = { recvWindow $= (\w => w - flowLen), received := got,
                           inBack := pushPiece payload ss.inBack, inBytes $= (+ n),
                           remoteEnded := end } ss
               let bad = case ss.contentLength of
                           Just cl => got > cl || (end && got /= cl)
                           Nothing => False
               writeIORef s.st ss'
               creditStream c s (flowLen - n)
               conditionBroadcast s.cond
               when end $ maybeRemove c s
               unlockC c
               if bad then streamError c s ProtocolError else pure Go

-- A complete header block of a stream.
onBlock : H2Conn -> Handlers -> Block -> IO Step
onBlock c h b = do
  let block = concat (reverse b.frags)
  d <- readIORef c.dec
  case decodeHeaderBlock d block of
    Left (HeaderListTooLarge d') => do
      writeIORef c.dec d'
      tooLarge
    Left e => connError c CompressionError (show e)
    Right (fields, d') => do
      writeIORef c.dec d'
      withFields fields
  where
    -- The stream of a new request, if it may be opened (lock taken and
    -- released here).
    openStream : Int -> IO (Either Step (Maybe H2Stream))
    openStream i = do
      lockC c
      cs <- getC c
      if not (peerId c i) || i <= cs.lastPeer
         then do unlockC c
                 Left <$> connError c ProtocolError "HEADERS opening a stream with a wrong id"
         else do
           putC c ({ lastPeer := i } cs)
           if cs.goawaySent then do unlockC c; pure (Right Nothing)
            else if cs.openCount >= c.cfg.maxConcurrentStreams || cs.handlers >= 2 * c.cfg.maxConcurrentStreams
             then do
               ok <- enqueueControl c (RstStream i RefusedStream)
               -- (the handlers of streams that the peer reset are still
               -- running: refusing more counts as resets)
               calm <- if cs.handlers >= 2 * c.cfg.maxConcurrentStreams then countReset c else pure True
               unlockC c
               if not calm then Left <$> connError c EnhanceYourCalm "too many streams reset"
                else if ok then pure (Right Nothing)
                else Left <$> connError c EnhanceYourCalm "too many queued control frames"
             else do
               s <- newStream i (newSState cs.peer.initialWindowSize c.cfg.initialWindowSize)
               modifyS s { remoteEnded := b.endStream }
               cs <- getC c
               putC c ({ streams $= insert i s, openCount $= (+ 1), handlers $= (+ 1) } cs)
               unlockC c
               pure (Right (Just s))

    tooLarge : IO Step
    tooLarge = do
      Just s <- lookupStream c b.sid
        | Nothing => if c.isServer
                       then do r <- openStream b.sid
                               case r of
                                 Left st => pure st
                                 Right Nothing => pure Go
                                 Right (Just s) => do h.onTooLarge s; pure Go
                       else rstId c b.sid ProtocolError
      streamError c s ProtocolError

    trailers : H2Stream -> List HeaderField -> IO Step
    trailers s fields = do
      lockC c
      ss <- readIORef s.st
      if ss.ignoreInput then do unlockC c; pure Go
       else if ss.remoteEnded then do unlockC c; streamError c s StreamClosed
       else if not b.endStream then do unlockC c; streamError c s ProtocolError
       else case checkTrailers fields of
        Left _ => do unlockC c; streamError c s ProtocolError
        Right hs => do
          let bad = maybe False (/= ss.received) ss.contentLength
          writeIORef s.st ({ trailers := hs, remoteEnded := True } ss)
          conditionBroadcast s.cond
          maybeRemove c s
          unlockC c
          if bad then streamError c s ProtocolError else pure Go

    response : H2Stream -> List HeaderField -> IO Step
    response s fields = do
      lockC c
      ss <- readIORef s.st
      case checkResponse fields of
        Left _ => do unlockC c; streamError c s ProtocolError
        Right (code, hs, cl) =>
          if code < 200
             then do unlockC c; pure Go  -- an interim response: ignored
             else do
               writeIORef s.st ({ response := Just (code, hs), contentLength := cl,
                                  remoteEnded := b.endStream } ss)
               conditionBroadcast s.cond
               when b.endStream $ maybeRemove c s
               unlockC c
               pure Go

    withFields : List HeaderField -> IO Step
    withFields fields = do
      Just s <- lookupStream c b.sid
        | Nothing =>
            if not c.isServer then rstId c b.sid StreamClosed else do
              cs <- getC c
              -- (a stream that was closed lately: its frames are ignored;
              -- one that was never opened is an error)
              if b.sid <= cs.lastPeer && peerId c b.sid
                then (if elem b.sid cs.recentlyClosed then pure Go
                      else connError c ProtocolError "HEADERS on a stream that was skipped or closed long ago")
                else do
                r <- openStream b.sid
                case r of
                  Left st => pure st
                  Right Nothing => pure Go
                  Right (Just s) =>
                    case checkRequest fields of
                      Left _ => do
                        lockC c
                        modifyS s { done := True }
                        cs <- getC c
                        putC c ({ handlers $= (\n => n - 1) } cs)
                        unlockC c
                        streamError c s ProtocolError
                      Right rh => do
                        lockC c
                        modifyS s { contentLength := rh.contentLength }
                        unlockC c
                        if b.endStream && maybe False (/= 0) rh.contentLength
                           then streamError c s ProtocolError
                           else do h.onRequest s rh; pure Go
      ss <- readIORef s.st
      if c.isServer || isJust ss.response then trailers s fields else response s fields

-- SETTINGS from the peer.
onSettings : H2Conn -> List (SettingId, Bits32) -> IO Step
onSettings c ps = do
  lockC c
  cs <- getC c
  let old = cs.peer
  let new = applySettings ps old
  let delta = new.initialWindowSize - old.initialWindowSize
  overflow <- if delta == 0 then pure False else do
                rs <- traverse (\s => do
                        ss <- readIORef s.st
                        let w = ss.sendWindow + delta
                        writeIORef s.st ({ sendWindow := w } ss)
                        pure (w > maxWindowSize)) (values cs.streams)
                pure (any id rs)
  putC c ({ peer := new } cs)
  when (new.headerTableSize /= old.headerTableSize) $ enqueue c (OTableSize (min 65536 new.headerTableSize))
  ok <- enqueueControl c (SettingsFrame True [])
  conditionBroadcast c.flowCond
  unlockC c
  if overflow then connError c FlowControlError "SETTINGS_INITIAL_WINDOW_SIZE makes a window too large"
   else if not ok then connError c EnhanceYourCalm "too many queued control frames"
   else pure Go

onWindowUpdate : H2Conn -> Int -> Int -> IO Step
onWindowUpdate c 0 inc = do
  lockC c
  cs <- getC c
  let w = cs.sendWindow + inc
  putC c ({ sendWindow := w } cs)
  conditionBroadcast c.flowCond
  unlockC c
  if w > maxWindowSize then connError c FlowControlError "connection window above 2^31-1" else pure Go
onWindowUpdate c i inc = do
  Just s <- lookupStream c i
    | Nothing => do
        cs <- getC c
        if i > (if peerId c i then cs.lastPeer else cs.nextLocal - 2)
           then connError c ProtocolError "WINDOW_UPDATE on an idle stream"
           else pure Go
  lockC c
  ss <- readIORef s.st
  let w = ss.sendWindow + inc
  writeIORef s.st ({ sendWindow := w } ss)
  conditionBroadcast c.flowCond
  unlockC c
  if w > maxWindowSize then streamError c s FlowControlError else pure Go

onRst : H2Conn -> Int -> ErrorCode -> IO Step
onRst c i code = do
  Just s <- lookupStream c i
    | Nothing => do
        cs <- getC c
        if i > (if peerId c i then cs.lastPeer else cs.nextLocal - 2)
           then connError c ProtocolError "RST_STREAM on an idle stream"
           else pure Go
  lockC c
  ss <- readIORef s.st
  writeIORef s.st ({ reset := True, ignoreInput := True, localEnded := True, remoteEnded := True } ss)
  creditConn c ss.inBytes
  failStream c s (OtherError ("stream reset by the peer: " ++ show code))
  conditionBroadcast c.flowCond
  ok <- if ss.done then pure True else countReset c
  maybeRemove c s
  unlockC c
  if ok then pure Go else connError c EnhanceYourCalm "too many streams reset"

-- One frame.  `blk` is the header block in progress, if any.
onFrame : H2Conn -> Handlers -> Maybe Block -> Frame -> IO (Step, Maybe Block)
onFrame c h (Just b) (Continuation i end frag) =
  if i /= b.sid then (\s => (s, Nothing)) <$> connError c ProtocolError "CONTINUATION of another stream" else do
    let b' = { frags $= (frag ::), size $= (+ lengthInt frag), count $= (+ 1) } b
    if b'.size > c.cfg.maxHeaderBlockSize || b'.count > c.cfg.maxContinuations
       then (\s => (s, Nothing)) <$> connError c EnhanceYourCalm "header block too large"
       else do
         emptyOk <- if lengthInt frag == 0 && not end
                       then do lockC c; ok <- countEmpty c; unlockC c; pure ok
                       else pure True
         if not emptyOk then (\s => (s, Nothing)) <$> connError c EnhanceYourCalm "too many empty frames"
          else if end then (\s => (s, Nothing)) <$> onBlock c h b'
          else pure (Go, Just b')
onFrame c h (Just b) _ = (\s => (s, Nothing)) <$> connError c ProtocolError "a frame inside a header block"
onFrame c h Nothing f = case f of
  DataFrame i end pad payload =>
    let flow = lengthInt payload + maybe 0 (+ 1) pad in
    (\s => (s, Nothing)) <$> onData c i end flow payload
  Headers i end endH _ _ frag =>
    let b = MkBlock i end [frag] (lengthInt frag) 0 in
    if lengthInt frag > c.cfg.maxHeaderBlockSize
      then (\s => (s, Nothing)) <$> connError c EnhanceYourCalm "header block too large"
     else if endH then (\s => (s, Nothing)) <$> onBlock c h b
     else do
      emptyOk <- if lengthInt frag == 0
                    then do lockC c; ok <- countEmpty c; unlockC c; pure ok
                    else pure True
      if emptyOk then pure (Go, Just b)
                 else (\s => (s, Nothing)) <$> connError c EnhanceYourCalm "too many empty frames"
  PriorityFrame _ _ => pure (Go, Nothing)
  RstStream i code => (\s => (s, Nothing)) <$> onRst c i code
  SettingsFrame True _ => do
    lockC c
    cs <- getC c
    putC c ({ settingsAcked := True } cs)
    unlockC c
    pure (Go, Nothing)
  SettingsFrame False ps => (\s => (s, Nothing)) <$> onSettings c ps
  PushPromise _ _ _ _ _ =>
    (\s => (s, Nothing)) <$> connError c ProtocolError (if c.isServer then "PUSH_PROMISE from a client" else "PUSH_PROMISE, which this client disabled")
  Ping False opaque => do
    lockC c
    ok <- enqueueControl c (Ping True opaque)
    unlockC c
    if ok then pure (Go, Nothing)
          else (\s => (s, Nothing)) <$> connError c EnhanceYourCalm "too many queued control frames"
  Ping True _ => pure (Go, Nothing)
  GoAway lastId code _ => do
    lockC c
    cs <- getC c
    putC c ({ goawayRecv := Just lastId } cs)
    -- (client) the streams above it were not processed
    when (not c.isServer) $
      traverse_ (\s => when (s.sid > lastId) $ failStream c s (OtherError "GOAWAY: not processed"))
                (values cs.streams)
    conditionBroadcast c.flowCond
    unlockC c
    pure (Go, Nothing)
  WindowUpdate i inc => (\s => (s, Nothing)) <$> onWindowUpdate c i inc
  Continuation _ _ _ => (\s => (s, Nothing)) <$> connError c ProtocolError "CONTINUATION without HEADERS"
  UnknownFrame _ _ _ payload =>
    if lengthInt payload > 0 then pure (Go, Nothing) else do
      lockC c
      ok <- countEmpty c
      unlockC c
      if ok then pure (Go, Nothing) else (\s => (s, Nothing)) <$> connError c EnhanceYourCalm "too many empty frames"

-- The deadline of the next read: the settings timeout while our SETTINGS
-- are not acknowledged, and the idle timeout (when it comes, the
-- connection ends if it has no stream; otherwise the reader reads again,
-- so that a connection whose last stream ended while the reader waited is
-- found idle within twice the timeout).
readDeadline : H2Conn -> Int -> IO Int
readDeadline c settingsDl = do
  lockC c
  cs <- getC c
  unlockC c
  idle <- deadlineAfterMs c.idleTimeout
  pure (earlierDeadline idle (if cs.settingsAcked then -1 else settingsDl))

-- Read more bytes after `buf` (at least `need` more): Nothing at the end
-- of the stream or after an error; the deadline reached gives `buf` back
-- unchanged, with False.
readMore : H2Conn -> ByteString -> Int -> Int -> IO (Maybe (ByteString, Bool))
readMore c buf need dl = do
  p <- pendingBytes c.conn
  if lengthInt p > 0
     then do
       ignore (readSome c.conn 0)
       pure (Just (if lengthInt buf == 0 then p else buf <+> p, True))
     else do
       let have = lengthInt buf
       if need <= connBufferSize c.conn
         then do
           -- (a read into the scratch buffer of the connection, copied out)
           r <- readSome c.conn dl
           case r of
             Left TimedOut => pure (Just (buf, False))
             Left _ => pure Nothing
             Right bs =>
               if lengthInt bs == 0 then pure Nothing
               else pure (Just (if have == 0 then bs else buf <+> bs, True))
         else do
           -- (the rest of a large frame, straight into a buffer of its size)
           let cap = have + need
           b <- bufNew cap
           bufCopy (unsafeBuffer buf) (unsafeOffset buf) have b 0
           r <- transportRecv (connTransport c.conn) b have need dl
           if r == timedOutCode then pure (Just (buf, False))
            else if r <= 0 then pure Nothing
            else pure (Just (UnsafeBS b 0 (have + r), True))

-- The read loop.
readLoop : H2Conn -> Handlers -> Int -> Maybe Block -> ByteString -> IO ()
readLoop c h settingsDl blk buf =
  case decodeFrame minMaxFrameSize buf of
    Decoded f rest => do
      (step, blk') <- onFrame c h blk f
      case step of
        Go => readLoop c h settingsDl blk' rest
        Stop => pure ()
    Failed (ConnectionError code msg) _ => ignore (connError c code msg)
    Failed (StreamError i code msg) rest => do
      Just s <- lookupStream c i
        | Nothing => do
            st <- rstId c i code
            case st of
              Go => readLoop c h settingsDl blk rest
              Stop => pure ()
      st <- streamError c s code
      case st of
        Go => readLoop c h settingsDl blk rest
        Stop => pure ()
    NeedMore n => do
      lockC c
      cs <- getC c
      unlockC c
      if cs.closing then pure ()
       else if cs.goawaySent && cs.openCount == 0 && cs.handlers == 0
         then do
           -- drained
           lockC c
           endConn c NoError ""
           unlockC c
       else do
        dl <- readDeadline c settingsDl
        Just (buf', got) <- readMore c buf n dl
          | Nothing => do
              lockC c
              endConn c NoError ""
              unlockC c
        if got then readLoop c h settingsDl blk buf' else do
          -- the deadline
          lockC c
          cs <- getC c
          unlockC c
          t <- nowNs
          if not cs.settingsAcked && t >= settingsDl
             then ignore (connError c SettingsTimeout "SETTINGS not acknowledged")
             else if cs.openCount == 0 && cs.handlers == 0
               then ignore (connError c NoError "idle")
               else readLoop c h settingsDl blk buf'

-- After the connection ended: let the writer write what is left (the
-- GOAWAY), end the writing side, and read what the peer still sends for a
-- little while, so that the GOAWAY is not lost to a reset.
finish : H2Conn -> IO ()
finish c = do
  dl <- deadlineAfterMs (if c.writeTimeout > 0 then min c.writeTimeout 5000 else 5000)
  done <- waitWriter c dl
  -- (the writer must be gone before the transport is closed, or it could
  -- write to the next connection that gets the descriptor: one that is
  -- stuck is woken up by the end of the stream)
  when (not done) $ do
    transportShutdown (connTransport c.conn) ShutBoth
    ignore (waitWriter c (-1))
  lockC c
  cs <- getC c
  putC c ({ dead := True } cs)
  traverse_ (\s => failStream c s UnexpectedEnd) (values cs.streams)
  conditionBroadcast c.flowCond
  unlockC c
  transportShutdown (connTransport c.conn) ShutWrite
  ldl <- deadlineAfterMs 1000
  linger ldl 0
  where
    linger : Int -> Int -> IO ()
    linger dl n =
      if n > 65536 then pure () else do
        Right bs <- readSome c.conn dl
          | Left _ => pure ()
        if lengthInt bs == 0 then pure () else linger dl (n + lengthInt bs)

--------------------------------------------------------------------------
-- Servers
--------------------------------------------------------------------------

||| What a server gives an HTTP/2 connection.
public export
record ServerSide where
  constructor MkServerSide
  config : H2Config
  writeTimeout : Int
  readTimeout : Int
  idleTimeout : Int
  ||| The deadline of the preface, and of the first SETTINGS frame.
  prefaceTimeout : Int
  log : String -> IO ()
  ||| Runs once the connection is set up, with the function that drains
  ||| it (GOAWAY, then the end once its streams are done), which the
  ||| server calls when it stops.
  onStart : IO () -> IO ()
  ||| Serves a request, in the thread of its stream (forked by the
  ||| connection); `streamDone` must be called at the end.
  serveStream : H2Conn -> H2Stream -> H2Request -> IO ()
  ||| Answers a request whose header list was too large (431), in the
  ||| thread of the reader.
  tooLarge : H2Conn -> H2Stream -> IO ()

||| The stream id.
export
streamId : H2Stream -> Int
streamId s = s.sid

||| The configuration of the connection.
export
h2Config : H2Conn -> H2Config
h2Config c = c.cfg

-- The PING that wakes up the reader of a connection that drains (the
-- answer of the peer does).  (Shutting down the reading side of the
-- transport would do it too, but a TLS session cut in the middle of a
-- record makes OpenSSL send an alert to the peer.)
drainPing : ByteString
drainPing = "draining"

||| The end of the work of a handler on its stream: the stream is reset if
||| its response did not end (INTERNAL_ERROR), or if the request body was
||| not read to its end (NO_ERROR, so that the client stops sending it).
export
streamDone : H2Conn -> H2Stream -> IO ()
streamDone c s = do
  lockC c
  ss <- readIORef s.st
  writeIORef s.st ({ done := True } ss)
  cs <- getC c
  putC c ({ handlers $= (\n => n - 1) } cs)
  if ss.reset then pure ()
   else if not ss.localEnded then ignore (resetStream c s InternalError)
   else if not ss.remoteEnded
    then do
      ignore (enqueueControl c (RstStream s.sid NoError))
      writeIORef s.st ({ ignoreInput := True, done := True } ss)
      creditConn c ss.inBytes
   else pure ()
  maybeRemove c s
  cs <- getC c
  -- a connection that drains ends with its last stream: a PING wakes up
  -- the reader (with its answer), which then ends the connection
  when (cs.goawaySent && cs.openCount == 0 && cs.handlers == 0 && not cs.closing) $
    enqueue c (OFrame (Ping False drainPing))
  unlockC c

-- Drain: GOAWAY with the last stream id, no new streams, the end once the
-- streams are done.
drain : H2Conn -> IO ()
drain c = do
  lockC c
  cs <- getC c
  when (not cs.goawaySent) $ do
    enqueue c (OFrame (GoAway cs.lastPeer NoError "shutting down"))
    putC c ({ goawaySent := True } cs)
  cs <- getC c
  when (cs.openCount == 0 && cs.handlers == 0 && not cs.closing) $
    enqueue c (OFrame (Ping False drainPing))
  unlockC c

||| Serve an HTTP/2 connection whose client preface may be in `Conn`
||| already: the preface, the exchange of SETTINGS, then the frames, until
||| the connection ends.  Returns when it has ended (the caller closes the
||| transport).
export
runServer : ServerSide -> Conn -> IO ()
runServer side conn = do
  c <- newH2Conn side.config True conn side.writeTimeout side.readTimeout side.idleTimeout side.log
  pdl <- deadlineAfterMs side.prefaceTimeout
  Just rest <- preface c Data.ByteString.empty pdl
    | Nothing => pure ()
  start c
  side.onStart (drain c)
  let handlers = MkHandlers (\s, rh => ignore (fork (side.serveStream c s rh)))
                            (side.tooLarge c)
  -- the first frame must be SETTINGS
  Just (first, rest') <- firstSettings c rest pdl
    | Nothing => do lockC c; endConn c ProtocolError "no SETTINGS first"; unlockC c; finish c
  (step, _) <- onFrame c handlers Nothing first
  sdl <- deadlineAfterMs side.config.settingsTimeout
  case step of
    Go => readLoop c handlers sdl Nothing rest'
    Stop => pure ()
  finish c
  where
    preface : H2Conn -> ByteString -> Int -> IO (Maybe ByteString)
    preface c buf dl = case checkPreface buf of
      PrefaceOk rest => pure (Just rest)
      PrefaceBad => pure Nothing
      PrefaceNeedMore n => do
        Just (buf', got) <- readMore c buf n dl
          | Nothing => pure Nothing
        if got then preface c buf' dl else pure Nothing

    firstSettings : H2Conn -> ByteString -> Int -> IO (Maybe (Frame, ByteString))
    firstSettings c buf dl = case decodeFrame minMaxFrameSize buf of
      Decoded f@(SettingsFrame False _) rest => pure (Just (f, rest))
      NeedMore n => do
        Just (buf', got) <- readMore c buf n dl
          | Nothing => pure Nothing
        if got then firstSettings c buf' dl else pure Nothing
      _ => pure Nothing

--------------------------------------------------------------------------
-- Clients
--------------------------------------------------------------------------

||| Errors of a request that the server did not process (a stream above
||| the last one of its GOAWAY, or refused): the request can be sent again
||| on another connection.
export
notProcessed : HttpError -> Bool
notProcessed (OtherError m) = m == "GOAWAY: not processed" || m == "stream reset by the peer: REFUSED_STREAM"
notProcessed _ = False

clientHandlers : Handlers
clientHandlers = MkHandlers (\_, _ => pure ()) (\_ => pure ())

||| Start a client connection over a connected `Conn` (TLS with ALPN `h2`,
||| or prior knowledge): the preface and our SETTINGS go out, and a thread
||| of its own reads the frames until the connection ends, then closes
||| the transport.
export
startClient : H2Config -> Conn -> (writeTimeout, readTimeout, idleTimeout : Int) ->
              (String -> IO ()) -> IO H2Conn
startClient cfg conn wt rt it log = do
  c <- newH2Conn cfg False conn wt rt it log
  lockC c
  enqueue c (ORaw connectionPreface)
  unlockC c
  start c
  sdl <- deadlineAfterMs cfg.settingsTimeout
  _ <- fork (do readLoop c clientHandlers sdl Nothing Data.ByteString.empty
                finish c
                closeConn conn)
  pure c

||| Can the connection take another request (it has not ended, and the
||| server has not sent GOAWAY)?
export
h2Usable : H2Conn -> IO Bool
h2Usable c = do
  lockC c
  cs <- getC c
  unlockC c
  pure (not cs.closing && not cs.dead && isNothing cs.goawayRecv)

||| Open a stream with the head of a request (pseudo-header fields first),
||| waiting until the deadline if the server's limit of streams is
||| reached.
export
openRequest : H2Conn -> List HeaderField -> (endStream : Bool) -> (deadline : Int) ->
              IO (Either HttpError H2Stream)
openRequest c fields end dl = do
  lockC c
  r <- go
  unlockC c
  pure r
  where
    go : IO (Either HttpError H2Stream)
    go = do
      cs <- getC c
      if cs.closing || cs.dead || isJust cs.goawayRecv
         then pure (Left (OtherError "GOAWAY: not processed"))
       else if cs.openCount >= fromMaybe 1000000 cs.peer.maxConcurrentStreams
        then do
          ok <- waitFlow c dl
          if ok then go else pure (Left TimedOut)
       else do
        let i = cs.nextLocal
        s <- newStream i (newSState cs.peer.initialWindowSize c.cfg.initialWindowSize)
        modifyS s { localEnded := end }
        putC c ({ nextLocal := i + 2, streams $= insert i s, openCount $= (+ 1) } cs)
        enqueue c (OHeaders s fields end)
        pure (Right s)

||| Wait (until the deadline) for the head of the response on a stream:
||| the status and the fields.
export
awaitResponse : H2Conn -> H2Stream -> (deadline : Int) -> IO (Either HttpError (Int, Headers))
awaitResponse c s dl = do
  lockC c
  r <- go
  unlockC c
  pure r
  where
    go : IO (Either HttpError (Int, Headers))
    go = do
      ss <- readIORef s.st
      case ss.response of
        Just r => pure (Right r)
        Nothing => case ss.failure of
          Just e => pure (Left e)
          Nothing => do
            t <- nowNs
            if dl >= 0 && t >= dl then pure (Left TimedOut) else do
              if dl < 0 then conditionWait s.cond c.lock
                        else conditionWaitTimeout s.cond c.lock (max 1 ((dl - t) `div` 1000))
              go

||| The client is done with a stream: it is reset (CANCEL) if the
||| response has not ended.
export
closeStream : H2Conn -> H2Stream -> IO ()
closeStream c s = do
  lockC c
  ss <- readIORef s.st
  writeIORef s.st ({ done := True } ss)
  if ss.reset then pure ()
   else if not ss.remoteEnded || not ss.localEnded then ignore (resetStream c s Cancel)
   else pure ()
  maybeRemove c s
  unlockC c

||| End a connection gracefully: GOAWAY, then the end once its streams are
||| done.
export
closeH2 : H2Conn -> IO ()
closeH2 = drain
