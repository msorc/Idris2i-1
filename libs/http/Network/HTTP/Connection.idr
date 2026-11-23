||| The input and output of an HTTP/1.1 connection over a `Transport`:
||| reading heads and bodies, writing heads and bodies.  The server
||| (`Network.HTTP.Server`) and the client (`Network.HTTP.Client`) are built
||| on it, and a protocol that takes a connection over (WebSocket, say)
||| keeps reading with `readSome`.
|||
||| # Buffers
|||
||| A connection has one scratch buffer (`bufferSize` bytes) that it reads
||| into and writes heads from.  The bytes that a read brings are copied out
||| of it into a byte string of their exact size, so that the slices that the
||| head parser makes of them (the method, the target, the names and values
||| of the fields) never see the scratch buffer change, and a slice that a
||| handler keeps holds only the bytes of its own message, not a buffer of
||| the connection.  A body that is larger than the scratch buffer is read
||| straight into a buffer of its own instead (`readAll` with a known
||| length, `readChunk` when much of a body is left), without the copy.
|||
||| The bytes that were read but not used yet (the start of a pipelined
||| request, or of a body) stay in the connection for the next read.
|||
||| A head and a small body are sent with one system call: the head is
||| written into the scratch buffer and the body copied after it when it
||| fits, or sent with it as a second range of the same `sendAll2`.
|||
||| A connection is used by one thread at a time.
module Network.HTTP.Connection

import Data.Buffer
import public Data.ByteString
import Data.ByteString.Builder
import Data.ByteString.Internal
import Data.IORef
import Data.List
import Data.Maybe
import Network.HTTP.Chunked
import Network.HTTP.Internal.Bytes
import public Network.HTTP.Parser
import public Network.HTTP.Transport
import public Network.HTTP.Types
import System.IO.Fd

%default covering

--------------------------------------------------------------------------
-- Errors
--------------------------------------------------------------------------

||| What can go wrong while reading or writing a message.
public export
data HttpError
  = ||| The peer closed the connection before a message started: the
    ||| normal end of a persistent connection.
    ConnectionClosed
  | ||| No byte of a message came before the deadline (an idle persistent
    ||| connection).
    IdleTimeout
  | ||| The stream ended in the middle of a message.
    UnexpectedEnd
  | ||| A deadline came in the middle of a message.
    TimedOut
  | ||| The transport failed (a reset connection, say).
    NetFailure NetError
  | ||| A head that is not valid or is beyond the limits.
    BadHead HeadError
  | ||| A chunked body that is not valid.
    BadChunks ChunkError
  | ||| A body larger than the limit.
    BodyTooLarge
  | ||| A body written with a declared length got more or fewer bytes.
    BodyLengthMismatch
  | ||| A URL that the client cannot use (with the reason).
    BadURL String
  | ||| A scheme that the client has no transport for (with the reason).
    UnsupportedScheme String
  | ||| More redirects than the client was allowed to follow.
    TooManyRedirects
  | ||| Another failure, described.
    OtherError String

||| A message for logs.
export
Show HttpError where
  show ConnectionClosed = "connection closed"
  show IdleTimeout = "idle timeout"
  show UnexpectedEnd = "unexpected end of stream"
  show TimedOut = "timed out"
  show (NetFailure e) = show e
  show (BadHead e) = "bad message head: " ++ show e
  show (BadChunks e) = "bad chunked body: " ++ show e
  show BodyTooLarge = "body too large"
  show BodyLengthMismatch = "body length does not match its Content-Length"
  show (BadURL s) = "bad URL: " ++ s
  show (UnsupportedScheme s) = s
  show TooManyRedirects = "too many redirects"
  show (OtherError s) = s

||| The same kind of error (and the same details for the ones that have
||| codes).
export
Eq HttpError where
  ConnectionClosed == ConnectionClosed = True
  IdleTimeout == IdleTimeout = True
  UnexpectedEnd == UnexpectedEnd = True
  TimedOut == TimedOut = True
  NetFailure a == NetFailure b = a == b
  BadHead a == BadHead b = a == b
  BadChunks a == BadChunks b = a == b
  BodyTooLarge == BodyTooLarge = True
  BodyLengthMismatch == BodyLengthMismatch = True
  BadURL a == BadURL b = a == b
  UnsupportedScheme a == UnsupportedScheme b = a == b
  TooManyRedirects == TooManyRedirects = True
  OtherError a == OtherError b = a == b
  _ == _ = False

||| The error of a negative code of a transport: `TimedOut` for
||| `-ETIMEDOUT`, `NetFailure` for the others.
export
codeToError : Int -> HttpError
codeToError n = if n == timedOutCode then TimedOut else NetFailure (codeError n)

--------------------------------------------------------------------------
-- Connections
--------------------------------------------------------------------------

||| A connection: a transport, its scratch buffer and the bytes read but not
||| used yet.
export
record Conn where
  constructor MkConn
  transport : Transport
  buf : Buffer
  bufSize : Int
  pending : IORef ByteString

emptyBS : ByteString
emptyBS = Data.ByteString.empty

-- A new buffer (of a size that is not negative).
allocBuffer : Int -> IO Buffer
allocBuffer n = do
  bufNew (max 0 n)

||| A connection over a transport, with a scratch buffer of `bufferSize`
||| bytes (at least 512; 4096 is a good size).
export
newConn : Transport -> (bufferSize : Int) -> IO Conn
newConn t size = do
  let n = max 512 size
  b <- allocBuffer n
  p <- newIORef emptyBS
  pure (MkConn t b n p)

||| The transport of the connection.
export
connTransport : Conn -> Transport
connTransport c = c.transport

||| The size of the scratch buffer.
export
connBufferSize : Conn -> Int
connBufferSize c = c.bufSize

||| The scratch buffer of the connection (`connBufferSize` bytes), for a
||| protocol that takes the connection over after an upgrade and reads the
||| transport with its own code (`Network.WebSocket`).  The reads and writes
||| of the connection itself must not be used any more then: they use it too.
export
connScratch : Conn -> Buffer
connScratch c = c.buf

||| Close the transport.  The connection must not be used afterwards.
export
closeConn : Conn -> IO ()
closeConn c = transportClose c.transport

-- Copy `n` bytes of a buffer from an offset into a byte string of their
-- own.
copyOut : Buffer -> Int -> Int -> IO ByteString
copyOut b o n = do
  nb <- allocBuffer n
  bufCopy b o n nb 0
  pure (UnsafeBS nb 0 n)

||| Put bytes back in front of what the next read gives (the bytes after a
||| message, which belong to the next one).
export
unread : Conn -> ByteString -> IO ()
unread c bs =
  if lengthInt bs == 0 then pure () else do
    p <- readIORef c.pending
    writeIORef c.pending (if lengthInt p == 0 then bs else bs <+> p)

||| The bytes read but not used yet (they stay in the connection).
export
pendingBytes : Conn -> IO ByteString
pendingBytes c = readIORef c.pending

||| The next bytes of the stream: those read but not used yet if there are
||| some, or what one read of the transport gives, waiting until the
||| deadline.  An empty byte string is the end of the stream.
export
readSome : Conn -> (deadline : Int) -> IO (Either HttpError ByteString)
readSome c dl = do
  p <- readIORef c.pending
  if lengthInt p > 0
     then do writeIORef c.pending emptyBS
             pure (Right p)
     else do
       n <- transportRecv c.transport c.buf 0 c.bufSize dl
       if n < 0 then pure (Left (codeToError n))
         else if n == 0 then pure (Right emptyBS)
         else do bs <- copyOut c.buf 0 n
                 pure (Right bs)

-- At most `want` bytes: the pending ones if there are some, or one read
-- straight into a buffer of their own of at most `want` bytes (no copy).
readFresh : Conn -> (want : Int) -> (deadline : Int) -> IO (Either HttpError ByteString)
readFresh c want dl = do
  p <- readIORef c.pending
  if lengthInt p > 0
     then if lengthInt p <= want
             then do writeIORef c.pending emptyBS
                     pure (Right p)
             else do writeIORef c.pending (dropInt want p)
                     pure (Right (takeInt want p))
     else if want <= c.bufSize
       then do
         n <- transportRecv c.transport c.buf 0 want dl
         if n < 0 then pure (Left (codeToError n))
           else if n == 0 then pure (Right emptyBS)
           else do bs <- copyOut c.buf 0 n
                   pure (Right bs)
       else do
         b <- allocBuffer want
         n <- transportRecv c.transport b 0 want dl
         if n < 0 then pure (Left (codeToError n))
           else pure (Right (UnsafeBS b 0 n))

--------------------------------------------------------------------------
-- Heads
--------------------------------------------------------------------------

headLoop : Conn -> HeadParser a -> Int -> IO (Either HttpError a)
headLoop c p dl = do
  Right bs <- readSome c dl
    | Left e => pure (Left e)
  if lengthInt bs == 0 then pure (Left UnexpectedEnd) else
    case feed p bs of
      NeedMore p' => headLoop c p' dl
      Done h rest => do unread c rest; pure (Right h)
      Failed e => pure (Left (BadHead e))

||| Read a head with a parser.  The first bytes must come before
||| `firstDeadline` (`IdleTimeout` otherwise, or `ConnectionClosed` if the
||| stream ends before them); once they came, the rest of the head must
||| come within `headTimeoutMs` milliseconds (`TimedOut` otherwise; 0 for no
||| limit).  The bytes after the head stay in the connection.
export
readHead : Conn -> HeadParser a -> (firstDeadline : Int) -> (headTimeoutMs : Int) ->
           IO (Either HttpError a)
readHead c p firstDl tmo = do
  r <- readSome c firstDl
  case r of
    Left TimedOut => pure (Left IdleTimeout)
    Left e => pure (Left e)
    Right bs =>
      if lengthInt bs == 0 then pure (Left ConnectionClosed) else
        case feed p bs of
          Done h rest => do unread c rest; pure (Right h)
          Failed e => pure (Left (BadHead e))
          NeedMore p' => do
            dl <- deadlineAfterMs tmo
            headLoop c p' dl

--------------------------------------------------------------------------
-- Reading bodies
--------------------------------------------------------------------------

-- Where a body reader is.
data BState
  = -- A body of known length: the bytes left.
    Remaining Int
  | -- A chunked body.
    InChunks ChunkDecoder
  | -- Data decoded already, delivered before going on with the state.
    Pieces (List ByteString) BState
  | -- A body that ends with the stream.
    ToClose
  | -- The body has ended, with these trailer fields.
    Ended Headers
  | -- Reading failed.
    Broken HttpError

||| Where the pieces of a body come from when they are not read from a
||| `Conn` (the DATA frames of an HTTP/2 stream, say): see `sourceReader`.
public export
record BodySource where
  constructor MkBodySource
  ||| The next piece (never empty), `Nothing` at the end of the body, or
  ||| an error (and the same error at every later call).
  next : IO (Either HttpError (Maybe ByteString))
  ||| The trailer fields, once the body has ended.
  trailers : IO Headers

||| A body being read, one piece at a time.  The pieces are byte strings
||| that belong to the reader of the body (no buffer is reused under them).
export
data BodyReader : Type where
  -- The body of a message without one.
  NoBodyReader : BodyReader
  -- A body of known length that came whole with the head (it is no longer
  -- in the connection): its bytes, and 0 before they are read, 1 after,
  -- 2 once a read failed because they are more than the limit.
  ReadyReader : ByteString -> (state : IORef Int) -> BodyReader
  -- A body from a source: the bytes delivered, whether it has ended, and
  -- the error that ended it.
  SourceReader : BodySource -> (got : IORef Int) -> (ended : IORef Bool) ->
                 (failure : IORef (Maybe HttpError)) -> BodyReader
  Reader : (conn : Conn) -> (st : IORef BState) -> (got : IORef Int) ->
           (limit : Int) -> (deadline : IO Int) ->
           (before : IORef (Maybe (IO (Either HttpError ())))) -> BodyReader

||| The reader of an empty body.
export
noBody : BodyReader
noBody = NoBodyReader

||| The reader of a body whose pieces come from a source.  `limit` does
||| not apply to it: the source enforces what it must (`readAll` still
||| takes its own limit).
export
sourceReader : BodySource -> IO BodyReader
sourceReader src = [| SourceReader (pure src) (newIORef 0) (newIORef False) (newIORef Nothing) |]

-- The next piece of a source, counted and remembered.
sourceNext : BodySource -> IORef Int -> IORef Bool -> IORef (Maybe HttpError) ->
             IO (Either HttpError (Maybe ByteString))
sourceNext src got ended failure = do
  Nothing <- readIORef failure
    | Just e => pure (Left e)
  r <- src.next
  case r of
    Right (Just bs) => do modifyIORef got (+ lengthInt bs); pure r
    Right Nothing => do writeIORef ended True; pure r
    Left e => do writeIORef failure (Just e); pure r

||| The limits of the decoder of chunked bodies.
export
chunkLimits : ChunkLimits
chunkLimits = defaultChunkLimits

||| A reader of a body with a framing, on a connection.  The `deadline`
||| action gives the deadline of each read (so that it can be a time after
||| the read before, or a fixed one).  `limit` is the most bytes that a
||| chunked or until-close body may have (negative for no limit; a body of
||| known length is checked by the caller).  `before` runs before the first
||| read (a server sends `100 Continue` there); if it fails, so does the
||| read.
export
bodyReader : Conn -> BodyFraming -> (limit : Int) -> (deadline : IO Int) ->
             (before : Maybe (IO (Either HttpError ()))) -> IO BodyReader
bodyReader c f limit dl before =
  case f of
    NoBody => pure NoBodyReader
    ContentLength 0 => pure NoBodyReader
    ContentLength n => do
      -- (a body that came whole with the head needs no reads: nor a
      -- `100 Continue`, which the client did not wait for)
      p <- readIORef c.pending
      if lengthInt p >= n
         then do writeIORef c.pending (if lengthInt p == n then emptyBS else dropInt n p)
                 st <- newIORef 0
                 pure (ReadyReader (takeInt n p) st)
         else make (Remaining n)
    Chunked => make (InChunks (chunkDecoder chunkLimits))
    UntilClose => make ToClose
  where
    make : BState -> IO BodyReader
    make s = do
      st <- newIORef s
      got <- newIORef 0
      b <- newIORef before
      pure (Reader c st got limit dl b)

-- How much to read at a time when much of a body is left.
bigRead : Int
bigRead = 65536

runBefore : IORef (Maybe (IO (Either HttpError ()))) -> IO (Either HttpError ())
runBefore ref = do
  Just act <- readIORef ref
    | Nothing => pure (Right ())
  writeIORef ref Nothing
  act

-- One step of reading: the next piece, Nothing at the end.
stepRead : Conn -> IORef BState -> IORef Int -> Int -> IO Int -> BState ->
           IO (Either HttpError (Maybe ByteString))
stepRead c st got limit dl s =
  case s of
    Ended _ => pure (Right Nothing)
    Broken e => pure (Left e)
    Pieces [] next => do writeIORef st next
                         stepRead c st got limit dl next
    Pieces (x :: xs) next => do
      writeIORef st (Pieces xs next)
      deliver x
    Remaining n =>
      if n <= 0 then do writeIORef st (Ended emptyHeaders); pure (Right Nothing) else do
        d <- dl
        Right bs <- readFresh c (min n bigRead) d
          | Left e => failWith e
        if lengthInt bs == 0 then failWith UnexpectedEnd else do
          let left = n - lengthInt bs
          writeIORef st (if left <= 0 then Ended emptyHeaders else Remaining left)
          deliverCounted bs
    ToClose => do
      d <- dl
      Right bs <- readFresh c bigRead d
        | Left e => failWith e
      if lengthInt bs == 0
         then do writeIORef st (Ended emptyHeaders); pure (Right Nothing)
         else deliver bs
    InChunks dec => do
      d <- dl
      Right bs <- readFresh c bigRead d
        | Left e => failWith e
      if lengthInt bs == 0 then failWith UnexpectedEnd else
        case decodeChunks dec bs of
          ChunkFailed e => failWith (BadChunks e)
          More ps dec' => do
            writeIORef st (Pieces ps (InChunks dec'))
            stepRead c st got limit dl (Pieces ps (InChunks dec'))
          End ps trailers rest => do
            unread c rest
            writeIORef st (Pieces ps (Ended trailers))
            stepRead c st got limit dl (Pieces ps (Ended trailers))
  where
    failWith : HttpError -> IO (Either HttpError (Maybe ByteString))
    failWith e = do writeIORef st (Broken e); pure (Left e)

    deliverCounted : ByteString -> IO (Either HttpError (Maybe ByteString))
    deliverCounted bs = do
      modifyIORef got (+ lengthInt bs)
      pure (Right (Just bs))

    deliver : ByteString -> IO (Either HttpError (Maybe ByteString))
    deliver bs = do
      g <- readIORef got
      let g' = g + lengthInt bs
      if limit >= 0 && g' > limit then failWith BodyTooLarge else do
        writeIORef got g'
        pure (Right (Just bs))

||| The next piece of the body (never empty), or `Nothing` at its end.  After
||| an error, every read gives that error again.
export
readChunk : BodyReader -> IO (Either HttpError (Maybe ByteString))
readChunk r = do
  -- (a bind first: an `IO` function whose body chooses between actions
  -- that are not all `do` blocks is compiled to one that returns a
  -- closure; after a bind, the choice calls them directly)
  () <- pure ()
  case r of
    NoBodyReader => pure (Right Nothing)
    ReadyReader bs st => do
      s <- readIORef st
      case s of
        0 => do writeIORef st 1; pure (Right (Just bs))
        1 => pure (Right Nothing)
        _ => pure (Left BodyTooLarge)
    SourceReader src got ended failure => sourceNext src got ended failure
    Reader c st got limit dl before => do
      Right () <- runBefore before
        | Left e => do writeIORef st (Broken e); pure (Left e)
      s <- readIORef st
      stepRead c st got limit dl s

-- Read a body of known length into a buffer of its size.
fillExact : Conn -> Buffer -> Int -> Int -> IO Int -> IO (Either HttpError ())
fillExact c b at n dl =
  if at >= n then pure (Right ()) else do
    d <- dl
    r <- transportRecv c.transport b at (n - at) d
    if r < 0 then pure (Left (codeToError r))
      else if r == 0 then pure (Left UnexpectedEnd)
      else fillExact c b (at + r) n dl

collect : BodyReader -> List ByteString -> IO (Either HttpError (List ByteString))
collect r acc = do
  Right (Just bs) <- readChunk r
    | Right Nothing => pure (Right (reverse acc))
    | Left e => pure (Left e)
  collect r (bs :: acc)

||| The whole body, if it has at most `limit` bytes (`BodyTooLarge`
||| otherwise).  A body of known length is read into one buffer of its size
||| (or is a slice of the bytes read with the head, when they hold all of
||| it); a chunked one is put together from its pieces.
export
readAll : BodyReader -> (limit : Int) -> IO (Either HttpError ByteString)
readAll NoBodyReader _ = pure (Right emptyBS)
readAll (ReadyReader bs st) limit = do
  s <- readIORef st
  case s of
    0 => if limit >= 0 && lengthInt bs > limit
            then do writeIORef st 2; pure (Left BodyTooLarge)
            else do writeIORef st 1; pure (Right bs)
    1 => pure (Right emptyBS)
    _ => pure (Left BodyTooLarge)
readAll (SourceReader src got ended failure) limit = go 0 []
  where
    go : Int -> List ByteString -> IO (Either HttpError ByteString)
    go sofar acc = do
      Right (Just bs) <- sourceNext src got ended failure
        | Right Nothing => pure (Right (concat (reverse acc)))
        | Left e => pure (Left e)
      let t = sofar + lengthInt bs
      if limit >= 0 && t > limit
         then do writeIORef failure (Just BodyTooLarge); pure (Left BodyTooLarge)
         else go t (bs :: acc)
readAll r@(Reader c st got _ dl before) limit = do
  Right () <- runBefore before
    | Left e => do writeIORef st (Broken e); pure (Left e)
  s <- readIORef st
  case s of
    Remaining n =>
      if limit >= 0 && n > limit then do writeIORef st (Broken BodyTooLarge); pure (Left BodyTooLarge) else do
        p <- readIORef c.pending
        if lengthInt p >= n
           then do writeIORef c.pending (dropInt n p)
                   writeIORef st (Ended emptyHeaders)
                   modifyIORef got (+ n)
                   pure (Right (takeInt n p))
           else do
             b <- allocBuffer n
             let k = lengthInt p
             bufCopy (unsafeBuffer p) (unsafeOffset p) k b 0
             writeIORef c.pending emptyBS
             Right () <- fillExact c b k n dl
               | Left e => do writeIORef st (Broken e); pure (Left e)
             writeIORef st (Ended emptyHeaders)
             modifyIORef got (+ n)
             pure (Right (UnsafeBS b 0 n))
    _ => do
      Right pieces <- collectLimited r limit
        | Left e => pure (Left e)
      pure (Right (concat pieces))
  where
    collectLimited : BodyReader -> Int -> IO (Either HttpError (List ByteString))
    collectLimited rd lim = go 0 []
      where
        go : Int -> List ByteString -> IO (Either HttpError (List ByteString))
        go sofar acc = do
          Right (Just bs) <- readChunk rd
            | Right Nothing => pure (Right (reverse acc))
            | Left e => pure (Left e)
          let t = sofar + lengthInt bs
          if lim >= 0 && t > lim
             then do writeIORef st (Broken BodyTooLarge); pure (Left BodyTooLarge)
             else go t (bs :: acc)

||| Read and drop the rest of the body, if it has at most `maxBytes` bytes
||| left (as far as can be told: a body of known length that has more left
||| is not read at all).  True if the body has ended (and the connection can
||| carry the next message).
export
drain : BodyReader -> (maxBytes : Int) -> IO Bool
drain NoBodyReader _ = pure True
drain (ReadyReader _ st) _ = do
  s <- readIORef st
  if s == 2 then pure False else do writeIORef st 1; pure True
drain (SourceReader src got ended failure) maxBytes = go 0
  where
    go : Int -> IO Bool
    go n = do
      r <- sourceNext src got ended failure
      case r of
        Right Nothing => pure True
        Left _ => pure False
        Right (Just bs) =>
          let n' = n + lengthInt bs in
          if n' > maxBytes then pure False else go n'
drain (Reader c st got lim dl before) maxBytes = do
  s <- readIORef st
  case s of
    Ended _ => pure True
    Broken _ => pure False
    Remaining n => if n > maxBytes then pure False else go 0
    _ => go 0
  where
    go : Int -> IO Bool
    go n = do
      r <- readChunk (Reader c st got lim dl before)
      case r of
        Right Nothing => pure True
        Left _ => pure False
        Right (Just bs) =>
          let n' = n + lengthInt bs in
          if n' > maxBytes then pure False else go n'

||| Run the action that comes before the first read of the body (a server
||| sends `100 Continue` there), if it has not run yet.
export
startBody : BodyReader -> IO (Either HttpError ())
startBody NoBodyReader = pure (Right ())
startBody (ReadyReader _ _) = pure (Right ())
startBody (SourceReader _ _ _ _) = pure (Right ())
startBody (Reader _ st _ _ _ before) = do
  Right () <- runBefore before
    | Left e => do writeIORef st (Broken e); pure (Left e)
  pure (Right ())

||| Has the body been read to its end?
export
bodyEnded : BodyReader -> IO Bool
bodyEnded r = do
  () <- pure ()
  case r of
    NoBodyReader => pure True
    ReadyReader _ st => do
      s <- readIORef st
      pure (s == 1)
    SourceReader _ _ ended _ => readIORef ended
    Reader _ st _ _ _ _ => do
      Ended _ <- readIORef st
        | _ => pure False
      pure True

||| Did reading the body fail (so that the connection cannot carry another
||| message)?
export
bodyFailed : BodyReader -> IO Bool
bodyFailed r = do
  () <- pure ()
  case r of
    NoBodyReader => pure False
    ReadyReader _ st => do
      s <- readIORef st
      pure (s == 2)
    SourceReader _ _ _ failure => do
      f <- readIORef failure
      pure (isJust f)
    Reader _ st _ _ _ _ => do
      Broken _ <- readIORef st
        | _ => pure False
      pure True

||| Has reading the body started (or has the action before the first read
||| run)?  False for a message without a body.
export
bodyStarted : BodyReader -> IO Bool
bodyStarted NoBodyReader = pure False
bodyStarted (ReadyReader _ _) = pure True
bodyStarted (SourceReader _ _ _ _) = pure True
bodyStarted (Reader _ _ _ _ _ before) = do
  Nothing <- readIORef before
    | Just _ => pure False
  pure True

||| The trailer fields of a chunked body that was read to its end (none
||| otherwise).
export
bodyTrailers : BodyReader -> IO Headers
bodyTrailers NoBodyReader = pure emptyHeaders
bodyTrailers (ReadyReader _ _) = pure emptyHeaders
bodyTrailers (SourceReader src _ ended _) = do
  True <- readIORef ended
    | False => pure emptyHeaders
  src.trailers
bodyTrailers (Reader _ st _ _ _ _) = do
  Ended hs <- readIORef st
    | _ => pure emptyHeaders
  pure hs

||| How many bytes of the body have been delivered so far.
export
bodyBytesRead : BodyReader -> IO Int
bodyBytesRead NoBodyReader = pure 0
bodyBytesRead (ReadyReader bs st) = do
  s <- readIORef st
  pure (if s == 1 then lengthInt bs else 0)
bodyBytesRead (SourceReader _ got _ _) = readIORef got
bodyBytesRead (Reader _ _ got _ _ _) = readIORef got

--------------------------------------------------------------------------
-- Writing
--------------------------------------------------------------------------

||| Copy a byte string into a buffer at an offset (the caller checked that
||| it fits); the offset after it.
export
putBytes : Buffer -> Int -> ByteString -> IO Int
putBytes dst at (UnsafeBS b o n) = do
  bufCopy b o n dst at
  pure (at + n)

||| One byte at an offset; the offset after it.
export
putByte : Buffer -> Int -> Bits8 -> IO Int
putByte dst at w = do bufSetByte dst at w; pure (at + 1)

||| The number of decimal digits of a number that is not negative.
export
decimalLength : Int -> Int
decimalLength n = go 1 n
  where
    go : Int -> Int -> Int
    go k m = if m < 10 then k else go (k + 1) (assert_smaller m (quot10 m))

-- Write the digits of `m` from index `i` down.
writeDecimal : Buffer -> Int -> Int -> IO ()
writeDecimal dst i m = do
  -- (a statement without `()` before an `if` makes the rest a closure)
  () <- bufSetByte dst i (cast (48 + rem10 m))
  if m < 10 then pure () else writeDecimal dst (i - 1) (quot10 m)

||| A number that is not negative in decimal at an offset; the offset after
||| it.
export
putDecimal : Buffer -> Int -> Int -> IO Int
putDecimal dst at n = do
  -- (a `let` before the first action would make the action a closure)
  () <- writeDecimal dst (at + decimalLength n - 1) n
  pure (at + decimalLength n)

hexLength : Int -> Int
hexLength n = go 1 n
  where
    go : Int -> Int -> Int
    go k m = if m < 16 then k else go (k + 1) (assert_smaller m (assert_total (prim__div_Int m 16)))

hexDigit : Int -> Bits8
hexDigit d = if d < 10 then cast (48 + d) else cast (87 + d)

writeHex : Buffer -> Int -> Int -> IO ()
writeHex dst i m = do
  () <- bufSetByte dst i (hexDigit (assert_total (prim__mod_Int m 16)))
  if m < 16 then pure () else writeHex dst (i - 1) (assert_total (prim__div_Int m 16))

-- A number that is not negative in hexadecimal; the offset after it.
putHex : Buffer -> Int -> Int -> IO Int
putHex dst at n = do
  () <- writeHex dst (at + hexLength n - 1) n
  pure (at + hexLength n)

||| Send bytes, waiting until the deadline.
export
sendBytes : Conn -> ByteString -> (deadline : Int) -> IO (Either HttpError ())
sendBytes c (UnsafeBS b o n) dl = do
  () <- pure ()
  if n == 0 then pure (Right ()) else do
    r <- transportSendAll c.transport b o n dl
    pure (if r < 0 then Left (codeToError r) else Right ())

||| Send the first `headLen` bytes of a buffer (a head written there) and
||| then a body, with one system call: if the buffer is the scratch buffer
||| and the body fits after the head, it is copied there and sent with it
||| in one range; otherwise the two are sent as two ranges.
export
sendHeadAndBody : Conn -> (head : Buffer) -> (headLen : Int) -> (body : ByteString) ->
                  (deadline : Int) -> IO (Either HttpError ())
sendHeadAndBody c hb hlen body dl = do
  let blen = lengthInt body
  r <- if blen == 0
          then transportSendAll c.transport hb 0 hlen dl
          else if hlen + blen <= c.bufSize
            then do
              bufCopy (unsafeBuffer body) (unsafeOffset body) blen hb hlen
              transportSendAll c.transport hb 0 (hlen + blen) dl
            else transportSendAll2 c.transport hb 0 hlen (unsafeBuffer body) (unsafeOffset body) blen dl
  pure (if r < 0 then Left (codeToError r) else Right ())

||| A buffer for a head of `n` bytes: the scratch buffer if it fits there, a
||| new one otherwise.
export
headBuffer : Conn -> (n : Int) -> IO Buffer
headBuffer c n = if n <= c.bufSize then pure c.buf else bufNew n

-- How a body is written.
data WMode
  = WChunked
  | WRaw
  | WDiscard
  | -- Pieces given to a function, and a function that ends the body.
    WSink (ByteString -> IO (Either HttpError ())) (IO (Either HttpError ()))

||| A body being written, a piece at a time: in the chunked coding, as raw
||| bytes (of a declared length, or up to the end of the connection), or
||| not at all (the body of a response to `HEAD`, which only counts).
export
record BodyWriter where
  constructor MkBodyWriter
  conn : Conn
  mode : WMode
  -- The bytes that may still be written (raw with a declared length), or
  -- -1.
  remaining : IORef Int
  -- A chunk was sent whose closing CRLF is still to be sent.
  needCRLF : IORef Bool
  failure : IORef (Maybe HttpError)
  written : IORef Int
  deadline : IO Int

||| A writer of a body in the chunked coding.
export
chunkedWriter : Conn -> (deadline : IO Int) -> IO BodyWriter
chunkedWriter c dl =
  [| MkBodyWriter (pure c) (pure WChunked) (newIORef (-1)) (newIORef False)
                  (newIORef Nothing) (newIORef 0) (pure dl) |]

||| A writer of raw bytes: exactly `length` bytes if it is given, up to the
||| end of the connection otherwise.
export
rawWriter : Conn -> (length : Maybe Int) -> (deadline : IO Int) -> IO BodyWriter
rawWriter c len dl =
  [| MkBodyWriter (pure c) (pure WRaw) (newIORef (maybe (-1) id len)) (newIORef False)
                  (newIORef Nothing) (newIORef 0) (pure dl) |]

-- The connection of the writers that have none (a sink): it is never
-- used.
nullOps : TransportOps
nullOps = MkTransportOps (\_, _, _, _ => pure (negate ebadf)) (\_, _, _, _ => pure (negate ebadf))
                         (\_, _, _, _, _, _, _ => pure (negate ebadf)) (\_ => pure ()) (pure ())
                         Nothing False

nullConn : IO Conn
nullConn = do
  b <- allocBuffer 0
  p <- newIORef emptyBS
  pure (MkConn (customTransport nullOps) b 0 p)

||| A writer of a body whose pieces go to a function (the DATA frames of
||| an HTTP/2 stream, say): exactly `length` bytes if it is given (more is
||| `BodyLengthMismatch`, as fewer is at `finishBody`).  `finish` ends the
||| body; neither function is called again after a failure.
export
sinkWriter : (length : Maybe Int) -> (write : ByteString -> IO (Either HttpError ())) ->
             (finish : IO (Either HttpError ())) -> IO BodyWriter
sinkWriter len write finish = do
  c <- nullConn
  [| MkBodyWriter (pure c) (pure (WSink write finish)) (newIORef (maybe (-1) id len)) (newIORef False)
                  (newIORef Nothing) (newIORef 0) (pure (pure (-1))) |]

||| A writer that sends nothing and counts the bytes (for `HEAD`).
export
discardWriter : Conn -> IO BodyWriter
discardWriter c =
  [| MkBodyWriter (pure c) (pure WDiscard) (newIORef (-1)) (newIORef False)
                  (newIORef Nothing) (newIORef 0) (pure (pure (-1))) |]

crlfBS : ByteString
crlfBS = "\r\n"

lastChunkBS : ByteString
lastChunkBS = "0\r\n\r\n"

crlfLastChunkBS : ByteString
crlfLastChunkBS = "\r\n0\r\n\r\n"

fail : BodyWriter -> HttpError -> IO (Either HttpError ())
fail w e = do writeIORef w.failure (Just e); pure (Left e)

result : BodyWriter -> Int -> IO (Either HttpError ())
result w r = if r < 0 then fail w (codeToError r) else pure (Right ())

||| Write the next piece of the body.  Once a write failed, every later one
||| fails with the same error.  An empty piece writes nothing.
export
writeBody : BodyWriter -> ByteString -> IO (Either HttpError ())
writeBody w bs = do
  Nothing <- readIORef w.failure
    | Just e => pure (Left e)
  let n = lengthInt bs
  if n == 0 then pure (Right ()) else do
    modifyIORef w.written (+ n)
    case w.mode of
      WDiscard => pure (Right ())
      WSink write _ => do
        left <- readIORef w.remaining
        if left >= 0 && n > left then fail w BodyLengthMismatch else do
          if left >= 0 then writeIORef w.remaining (left - n) else pure ()
          Right () <- write bs
            | Left e => fail w e
          pure (Right ())
      WRaw => do
        left <- readIORef w.remaining
        if left >= 0 && n > left then fail w BodyLengthMismatch else do
          if left >= 0 then writeIORef w.remaining (left - n) else pure ()
          d <- w.deadline
          r <- transportSendAll w.conn.transport (unsafeBuffer bs) (unsafeOffset bs) n d
          result w r
      WChunked => do
        let c = w.conn
        crlf <- readIORef w.needCRLF
        at <- if crlf then putBytes c.buf 0 crlfBS else pure 0
        at <- putHex c.buf at n
        at <- putBytes c.buf at crlfBS
        d <- w.deadline
        if at + n + 2 <= c.bufSize
           then do
             at <- putBytes c.buf at bs
             at <- putBytes c.buf at crlfBS
             writeIORef w.needCRLF False
             r <- transportSendAll c.transport c.buf 0 at d
             result w r
           else do
             writeIORef w.needCRLF True
             r <- transportSendAll2 c.transport c.buf 0 at (unsafeBuffer bs) (unsafeOffset bs) n d
             result w r

||| Write the output of a builder as the next piece of the body.
export
writeBuilder : BodyWriter -> Builder -> IO (Either HttpError ())
writeBuilder w b = writeBody w (toByteString b)

||| How many bytes of the body have been written (or counted).
export
bodyBytesWritten : BodyWriter -> IO Int
bodyBytesWritten w = readIORef w.written

||| End the body: the last chunk (with no trailer fields) in the chunked
||| coding; for a declared length, `BodyLengthMismatch` if fewer bytes were
||| written.  Fails if a write failed before.
export
finishBody : BodyWriter -> IO (Either HttpError ())
finishBody w = do
  Nothing <- readIORef w.failure
    | Just e => pure (Left e)
  case w.mode of
    WDiscard => pure (Right ())
    WSink _ finish => do
      left <- readIORef w.remaining
      if left > 0 then fail w BodyLengthMismatch else do
        Right () <- finish
          | Left e => fail w e
        pure (Right ())
    WRaw => do
      left <- readIORef w.remaining
      if left > 0 then fail w BodyLengthMismatch else pure (Right ())
    WChunked => do
      crlf <- readIORef w.needCRLF
      d <- w.deadline
      Right () <- sendBytes w.conn (if crlf then crlfLastChunkBS else lastChunkBS) d
        | Left e => fail w e
      pure (Right ())

||| Did a write of the body fail?
export
writerFailed : BodyWriter -> IO Bool
writerFailed w = isJust <$> readIORef w.failure
