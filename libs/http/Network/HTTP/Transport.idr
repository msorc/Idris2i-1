||| A byte stream for HTTP connections: a plain socket, or any stream that
||| provides operations over ranges of a `Buffer` with deadlines (a TLS
||| session, say).
|||
||| The operations have the shapes of the code layer of
||| `Network.Socket.Async` (`recvCode`, `sendAllCode`, `sendAll2Code`): they
||| return an `Int`, a count (or 0) when they succeed and minus an errno code
||| when they fail.  A deadline is an absolute time in nanoseconds on the
||| clock of `System.IO.Wait.now` (`deadlineIn` makes one), or a negative
||| number for none; an operation that reaches its deadline returns
||| `-ETIMEDOUT` (`timedOutCode`), one on a transport that was closed
||| meanwhile `-EBADF`.  `codeError` of `Network.Socket.Async` turns a code
||| into a `NetError`.
|||
||| A `Transport` is either a socket (`socketTransport`), whose operations
||| are direct calls of the system with no allocation on the way, or a
||| record of functions (`customTransport` of a `TransportOps`), which
||| another library fills in with its own.  (A record of functions is not
||| used for sockets: on the RefC back end, calling a function kept in a
||| record applies its closure an argument at a time, which allocates a
||| partial application for each argument.)
|||
||| A transport is used by one thread at a time for reading and one at a
||| time for writing (they may be different threads).
module Network.HTTP.Transport

import Data.Buffer
import public Network.Socket.Async
import System.IO.Fd
import Network.HTTP.Internal.Bytes

%default covering

||| The operations of a byte stream that is not a plain socket.
public export
record TransportOps where
  constructor MkTransportOps
  ||| Receive at most `len` bytes into the buffer from `offset`, waiting
  ||| until some come or until the deadline: the number of bytes, 0 at the
  ||| end of the stream, or minus an errno code.
  recv : Buffer -> (offset, len : Int) -> (deadline : Int) -> IO Int
  ||| Send all `len` bytes of the buffer from `offset`: 0, or minus an
  ||| errno code (some of the bytes may have been sent then).
  sendAll : Buffer -> (offset, len : Int) -> (deadline : Int) -> IO Int
  ||| Send all of two ranges, one after the other (a head and a body),
  ||| with one system call when it can: 0, or minus an errno code.
  sendAll2 : Buffer -> (offset1, len1 : Int) -> Buffer -> (offset2, len2 : Int) ->
             (deadline : Int) -> IO Int
  ||| End one or both directions of the stream (for TLS, `ShutWrite` sends
  ||| the closing alert).  A thread that waits in `recv` when the reading
  ||| side is shut down must get the end of the stream (0).  Errors are
  ||| ignored.
  shutdown : ShutdownHow -> IO ()
  ||| Close the stream and release what it holds.  Called once, after the
  ||| last operation has returned.
  close : IO ()
  ||| The address of the peer, if known.
  peer : Maybe SockAddr
  ||| Does the stream protect what it carries (TLS)?
  secure : Bool

||| A byte stream: a socket, or a stream with operations of its own.
export
data Transport : Type where
  SocketT : AsyncSocket -> Maybe SockAddr -> Transport
  OpsT : TransportOps -> (protocol : Maybe String) -> Transport

||| The transport of a connected stream socket of `Network.Socket.Async`
||| (not secure), with the address of the peer if the caller knows it
||| (`acceptFrom` gives it).  `transportClose` closes the socket.
export
socketTransport : AsyncSocket -> (peer : Maybe SockAddr) -> Transport
socketTransport = SocketT

||| The transport of a stream with operations of its own (TLS, a test
||| double).
export
customTransport : TransportOps -> Transport
customTransport ops = OpsT ops Nothing

||| The transport of a stream with operations of its own, over which an
||| application protocol was agreed on when it was set up (with ALPN for
||| TLS: `"h2"`, `"http/1.1"`), or `Nothing` if none was.
export
customTransportWithProtocol : TransportOps -> (protocol : Maybe String) -> Transport
customTransportWithProtocol = OpsT

||| The application protocol agreed on for the stream when it was set up
||| (with ALPN for TLS), if any; always `Nothing` for a socket.
export
transportProtocol : Transport -> Maybe String
transportProtocol (SocketT _ _) = Nothing
transportProtocol (OpsT _ p) = p

||| The socket under a transport made by `socketTransport`.
export
transportSocket : Transport -> Maybe AsyncSocket
transportSocket (SocketT s _) = Just s
transportSocket (OpsT _ _) = Nothing

--------------------------------------------------------------------------
-- The socket operations, in IO, without the closures of `HasIO`
--------------------------------------------------------------------------

netC : String -> String
netC fn = "C:\{fn}, libidris2i_1_support, idris_net_async.h"

%foreign netC "idrnet_async_recv"
prim__recv : Int -> Buffer -> Int -> Int -> PrimIO Int

%foreign netC "idrnet_async_send"
prim__send : Int -> Buffer -> Int -> Int -> PrimIO Int

%foreign netC "idrnet_async_send2"
prim__send2 : Int -> Buffer -> Int -> Int -> Buffer -> Int -> Int -> PrimIO Int

-- The wait of System.IO.Wait without its `Maybe` and result type: a
-- deadline below 0 is none; 1 ready, 0 deadline, -errno.
%foreign "RefC:idris2i_1_ioWait"
         "C__collect_safe:idris2i_1_fdWaitBlocking, libidris2i_1_support, idris_fd.h"
         "C:idris2i_1_fdWaitBlocking, libidris2i_1_support, idris_fd.h"
prim__wait : (fd : Int) -> (event : Int) -> (deadline : Int64) -> PrimIO Int

%foreign "RefC:idris2i_1_monotonicNanoseconds"
         "C:idris2i_1_fdMonotonicNanoseconds, libidris2i_1_support, idris_fd.h"
prim__nowNs : PrimIO Int64

negEAgain : Int
negEAgain = negate eagain

negEInval : Int
negEInval = negate einval

||| `-ETIMEDOUT`: the code of an operation that reached its deadline.
export
timedOutCode : Int
timedOutCode = negate etimedout

-- Wait for the descriptor: 1 to try again, or the code to give up with.
waitCode : Int -> Int -> Int -> IO Int
waitCode fd ev deadline = do
  w <- fromPrim (prim__wait fd ev (cast deadline))
  pure (if w == 1 then 1 else if w == 0 then timedOutCode else w)

inRange : Buffer -> Int -> Int -> Bool
inRange buf offset len = offset >= 0 && len >= 0 && offset <= bufSize buf - len

recvLoop : Int -> Buffer -> Int -> Int -> Int -> IO Int
recvLoop fd buf offset len deadline = do
  r <- fromPrim (prim__recv fd buf offset len)
  if r /= negEAgain then pure r else do
    w <- waitCode fd 1 deadline
    if w == 1 then recvLoop fd buf offset len deadline else pure w

sendAllLoop : Int -> Buffer -> Int -> Int -> Int -> IO Int
sendAllLoop fd buf offset len deadline =
  if len <= 0 then pure 0 else do
    r <- fromPrim (prim__send fd buf offset len)
    if r == negEAgain
       then do w <- waitCode fd 2 deadline
               if w == 1 then sendAllLoop fd buf offset len deadline else pure w
       else if r < 0 then pure r
       else sendAllLoop fd buf (offset + r) (len - r) deadline

send2Loop : Int -> Buffer -> Int -> Int -> Buffer -> Int -> Int -> Int -> IO Int
send2Loop fd b1 o1 l1 b2 o2 l2 deadline =
  if l1 <= 0 then sendAllLoop fd b2 o2 l2 deadline else do
    r <- fromPrim (prim__send2 fd b1 o1 l1 b2 o2 l2)
    if r == negEAgain
      then do w <- waitCode fd 2 deadline
              if w == 1 then send2Loop fd b1 o1 l1 b2 o2 l2 deadline else pure w
      else if r < 0 then pure r
      else if r >= l1
        then sendAllLoop fd b2 (o2 + (r - l1)) (l2 - (r - l1)) deadline
        else send2Loop fd b1 (o1 + r) (l1 - r) b2 o2 l2 deadline

-- A deadline `ms` milliseconds from now, or none (-1).
msDeadline : Int -> IO Int
msDeadline ms = if ms <= 0 then pure (-1) else do
  t <- fromPrim prim__nowNs
  pure (cast t + ms * 1000000)

-- The loops with a timeout rather than a deadline: the deadline is made
-- (the clock read) only when the socket is not ready.
sendAllLoopWithin : Int -> Buffer -> Int -> Int -> (ms : Int) -> IO Int
sendAllLoopWithin fd buf offset len ms =
  if len <= 0 then pure 0 else do
    r <- fromPrim (prim__send fd buf offset len)
    if r == negEAgain
       then do dl <- msDeadline ms
               w <- waitCode fd 2 dl
               if w == 1 then sendAllLoop fd buf offset len dl else pure w
       else if r < 0 then pure r
       else if r >= len then pure 0
       else do dl <- msDeadline ms
               sendAllLoop fd buf (offset + r) (len - r) dl

send2LoopWithin : Int -> Buffer -> Int -> Int -> Buffer -> Int -> Int -> (ms : Int) -> IO Int
send2LoopWithin fd b1 o1 l1 b2 o2 l2 ms =
  if l1 <= 0 then sendAllLoopWithin fd b2 o2 l2 ms else do
    r <- fromPrim (prim__send2 fd b1 o1 l1 b2 o2 l2)
    if r >= 0 && r == l1 + l2 then pure 0
      else if r < 0 && r /= negEAgain then pure r
      else do
        dl <- msDeadline ms
        if r == negEAgain
           then do w <- waitCode fd 2 dl
                   if w == 1 then send2Loop fd b1 o1 l1 b2 o2 l2 dl else pure w
           else if r >= l1
             then sendAllLoop fd b2 (o2 + (r - l1)) (l2 - (r - l1)) dl
             else send2Loop fd b1 (o1 + r) (l1 - r) b2 o2 l2 dl

--------------------------------------------------------------------------
-- Operations
--------------------------------------------------------------------------

-- (The operations are written with the world token by hand, so that the
-- exported functions take it as an argument and call the socket loops
-- directly; written as `IO` actions chosen by a case, each call would
-- allocate the closure of the action.)

sockRecv : Int -> Buffer -> Int -> Int -> Int -> IO Int
sockRecv fd b o n d = do
  -- (a bind first: an `IO` function whose body chooses between actions
  -- that are not all `do` blocks is compiled to one that returns a
  -- closure; after a bind, the choice calls them directly)
  () <- pure ()
  if inRange b o n then recvLoop fd b o n d else pure negEInval

sockSendAll : Int -> Buffer -> Int -> Int -> Int -> IO Int
sockSendAll fd b o n d = do
  () <- pure ()
  if inRange b o n then sendAllLoop fd b o n d else pure negEInval

sockSendAll2 : Int -> Buffer -> Int -> Int -> Buffer -> Int -> Int -> Int -> IO Int
sockSendAll2 fd b1 o1 n1 b2 o2 n2 d = do
  () <- pure ()
  if inRange b1 o1 n1 && inRange b2 o2 n2 then send2Loop fd b1 o1 n1 b2 o2 n2 d else pure negEInval

recvP : Transport -> Buffer -> Int -> Int -> Int -> PrimIO Int
recvP (SocketT s _) b o n d w = toPrim (sockRecv s.fd b o n d) w
recvP (OpsT ops _) b o n d w = toPrim (ops.recv b o n d) w

sendAllP : Transport -> Buffer -> Int -> Int -> Int -> PrimIO Int
sendAllP (SocketT s _) b o n d w = toPrim (sockSendAll s.fd b o n d) w
sendAllP (OpsT ops _) b o n d w = toPrim (ops.sendAll b o n d) w

sendAll2P : Transport -> Buffer -> Int -> Int -> Buffer -> Int -> Int -> Int -> PrimIO Int
sendAll2P (SocketT s _) b1 o1 n1 b2 o2 n2 d w = toPrim (sockSendAll2 s.fd b1 o1 n1 b2 o2 n2 d) w
sendAll2P (OpsT ops _) b1 o1 n1 b2 o2 n2 d w = toPrim (ops.sendAll2 b1 o1 n1 b2 o2 n2 d) w

||| Receive at most `len` bytes into the buffer from `offset`, waiting until
||| some come or until the deadline: the number of bytes, 0 at the end of
||| the stream, or minus an errno code (`-EINVAL` when the range is not in
||| the buffer).  No allocation for a socket.
export
transportRecv : Transport -> Buffer -> (offset, len : Int) -> (deadline : Int) -> IO Int
transportRecv t b o n d = fromPrim (recvP t b o n d)

||| Send all `len` bytes of the buffer from `offset`: 0, or minus an errno
||| code.  No allocation for a socket.
export
transportSendAll : Transport -> Buffer -> (offset, len : Int) -> (deadline : Int) -> IO Int
transportSendAll t b o n d = fromPrim (sendAllP t b o n d)

||| Send all of two ranges, one after the other, with one system call when
||| the socket takes them all: 0, or minus an errno code.  No allocation
||| for a socket.
export
transportSendAll2 : Transport -> Buffer -> (offset1, len1 : Int) ->
                    Buffer -> (offset2, len2 : Int) -> (deadline : Int) -> IO Int
transportSendAll2 t b1 o1 n1 b2 o2 n2 d = fromPrim (sendAll2P t b1 o1 n1 b2 o2 n2 d)

||| `transportSendAll` with a timeout in milliseconds (0 or less for none)
||| rather than a deadline: for a socket, the clock is read only if the
||| socket cannot take the bytes at once.
export
transportSendAllWithin : Transport -> Buffer -> (offset, len : Int) -> (timeoutMs : Int) -> IO Int
transportSendAllWithin t b o n ms = do
  () <- pure ()
  case t of
    SocketT s _ => if inRange b o n then sendAllLoopWithin s.fd b o n ms else pure negEInval
    OpsT ops _ => do d <- msDeadline ms; ops.sendAll b o n d

||| `transportSendAll2` with a timeout in milliseconds (see
||| `transportSendAllWithin`).
export
transportSendAll2Within : Transport -> Buffer -> (offset1, len1 : Int) ->
                          Buffer -> (offset2, len2 : Int) -> (timeoutMs : Int) -> IO Int
transportSendAll2Within t b1 o1 n1 b2 o2 n2 ms = do
  () <- pure ()
  case t of
    SocketT s _ => if inRange b1 o1 n1 && inRange b2 o2 n2
                      then send2LoopWithin s.fd b1 o1 n1 b2 o2 n2 ms else pure negEInval
    OpsT ops _ => do d <- msDeadline ms; ops.sendAll2 b1 o1 n1 b2 o2 n2 d

||| End one or both directions of the stream.  A thread that waits for the
||| stream when its reading side is shut down sees the end of the stream.
export
transportShutdown : Transport -> ShutdownHow -> IO ()
transportShutdown (SocketT s _) how = ignore (shutdown s how)
transportShutdown (OpsT ops _) how = ops.shutdown how

||| Close the stream (the socket of a socket transport).  Call it once,
||| when no operation is running any more.
export
transportClose : Transport -> IO ()
transportClose (SocketT s _) = ignore (close s)
transportClose (OpsT ops _) = ops.close

||| The address of the peer, if known.
export
transportPeer : Transport -> Maybe SockAddr
transportPeer (SocketT _ p) = p
transportPeer (OpsT ops _) = ops.peer

||| Is the stream secure (TLS)?
export
transportSecure : Transport -> Bool
transportSecure (SocketT _ _) = False
transportSecure (OpsT ops _) = ops.secure

||| The operations of any transport as a record (a library that wraps a
||| transport, TLS over a socket say, can call them).
export
transportOps : Transport -> TransportOps
transportOps t =
  MkTransportOps (transportRecv t) (transportSendAll t) (transportSendAll2 t)
                 (transportShutdown t) (transportClose t) (transportPeer t) (transportSecure t)

--------------------------------------------------------------------------
-- Deadlines
--------------------------------------------------------------------------

||| `System.IO.Wait.now` (nanoseconds on the clock of the deadlines), in IO.
export
nowNs : IO Int
nowNs = do t <- fromPrim prim__nowNs; pure (cast t)

||| A deadline `ms` milliseconds from now, or none (-1) for 0 or less.
export
deadlineAfterMs : (ms : Int) -> IO Int
deadlineAfterMs ms = if ms <= 0 then pure (-1) else do
  t <- nowNs
  pure (t + ms * 1000000)

||| The earlier of two deadlines (a negative one is none).
export
earlierDeadline : Int -> Int -> Int
earlierDeadline a b = if a < 0 then b else if b < 0 then a else min a b
