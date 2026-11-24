||| Non-blocking sockets for many threads.
|||
||| The sockets of this module are non-blocking.  An operation that cannot
||| go on at once waits for the socket (`System.IO.Wait`): on the RefC back
||| end the green thread parks in the scheduler while the other threads of
||| its worker run, so a program can serve thousands of connections with a
||| thread each.  On the Chez and Racket back ends, whose threads are OS
||| threads, a wait blocks its thread in poll(2), and closing a socket does
||| not wake up a thread that waits for it.  The JavaScript back ends do not
||| support this module.
|||
||| Every waiting operation takes an optional deadline: an absolute time in
||| nanoseconds on the clock of `System.IO.Wait.now` (`deadlineIn` makes
||| one).  Addresses are numeric (`Network.Socket.Address`): `connectHost`
||| resolves a name first, with `Network.Socket.DNS`.
|||
||| There are two layers:
|||
||| * the functions that return `Either NetError a` (`recv`, `send`,
|||   `accept`, ...);
||| * for loops that call them very often, the same operations returning a
|||   plain `Int` code (`recvCode`, `sendCode`, ...) with no allocation on
|||   the way: a count, or minus an errno code, `-ETIMEDOUT` when the
|||   deadline came first and `-EBADF` when the socket was closed while the
|||   thread waited.  `codeError` turns a negative code into a `NetError`.
|||   `tryRecv` and `trySend` do not wait at all.
|||
||| Rules:
|||
||| * Close a socket of this module with `close` (it wakes up the threads
|||   that wait for it, and makes the reactor of RefC forget it), never with
|||   `Network.Socket.close` or `System.File`.
||| * Do not hand a socket over to code that blocks (`fdopen`, C code)
|||   without `makeBlocking` first.
||| * Writes to a socket whose peer is gone fail with `EPIPE` (or
|||   `ECONNRESET`) instead of raising SIGPIPE.
||| * Several threads may wait for one socket (all are woken up); a thread
|||   that reads and one that writes at the same time are fine.
module Network.Socket.Async

import Data.Buffer
import Data.List
import public Network.Socket.Address
import Network.Socket.DNS
import public System.IO.Wait
import System.IO.Fd

%default total

-- ---------------------------------------------------------------------------
-- The C functions (support/c/idris_net_async.h)

netC : String -> String
netC fn = "C:\{fn}, libidris2i_1_support, idris_net_async.h"

%foreign netC "idrnet_async_socket"
prim__socket : Int -> Int -> PrimIO Int

%foreign netC "idrnet_async_bind"
prim__bind : Int -> Int -> String -> Int -> PrimIO Int

%foreign netC "idrnet_async_listen"
prim__listen : Int -> Int -> PrimIO Int

%foreign netC "idrnet_async_connect"
prim__connect : Int -> Int -> String -> Int -> PrimIO Int

%foreign netC "idrnet_async_connect_result"
prim__connectResult : Int -> PrimIO Int

%foreign netC "idrnet_async_accept"
prim__accept : Int -> PrimIO Int

%foreign netC "idrnet_async_accept_addr"
prim__acceptAddr : Int -> Buffer -> PrimIO Int

%foreign netC "idrnet_async_recv"
prim__recv : Int -> Buffer -> Int -> Int -> PrimIO Int

%foreign netC "idrnet_async_send"
prim__send : Int -> Buffer -> Int -> Int -> PrimIO Int

%foreign netC "idrnet_async_send2"
prim__send2 : Int -> Buffer -> Int -> Int -> Buffer -> Int -> Int -> PrimIO Int

%foreign netC "idrnet_async_recvfrom"
prim__recvFrom : Int -> Buffer -> Int -> Int -> Buffer -> PrimIO Int

%foreign netC "idrnet_async_sendto"
prim__sendTo : Int -> Buffer -> Int -> Int -> Int -> String -> Int -> PrimIO Int

%foreign netC "idrnet_async_shutdown"
prim__shutdown : Int -> Int -> PrimIO Int

%foreign netC "idrnet_async_setopt"
prim__setOpt : Int -> Int -> Int -> PrimIO Int

%foreign netC "idrnet_async_getopt"
prim__getOpt : Int -> Int -> PrimIO Int

%foreign netC "idrnet_async_getname"
prim__getName : Int -> Int -> Buffer -> PrimIO Int

%foreign netC "idrnet_async_addr_family"
prim__addrFamily : Buffer -> PrimIO Int

%foreign netC "idrnet_async_addr_port"
prim__addrPort : Buffer -> PrimIO Int

%foreign netC "idrnet_async_addr_host"
prim__addrHost : Buffer -> PrimIO String

%foreign netC "idrnet_async_make_blocking"
prim__makeBlocking : Int -> PrimIO Int

%foreign netC "idrnet_async_strerror"
prim__strerror : Int -> PrimIO String

%foreign netC "idrnet_async_EINPROGRESS"
prim__einprogress : PrimIO Int

%foreign netC "idrnet_async_ETIMEDOUT"
prim__etimedout : PrimIO Int

%foreign netC "idrnet_async_EPIPE"
prim__epipe : PrimIO Int

%foreign netC "idrnet_async_ECONNRESET"
prim__econnreset : PrimIO Int

%foreign netC "idrnet_async_ECONNREFUSED"
prim__econnrefused : PrimIO Int

%foreign netC "idrnet_async_ENOTCONN"
prim__enotconn : PrimIO Int

-- The wait of System.IO.Wait, without its `Maybe` and result type: a
-- deadline below 0 is none; 1 ready, 0 deadline, -errno.
%foreign "RefC:idris2i_1_ioWait"
         "C__collect_safe:idris2i_1_fdWaitBlocking, libidris2i_1_support, idris_fd.h"
         "C:idris2i_1_fdWaitBlocking, libidris2i_1_support, idris_fd.h"
prim__wait : (fd : Int) -> (event : Int) -> (deadline : Int64) -> PrimIO Int

-- ---------------------------------------------------------------------------
-- Errors

||| The errno code `EINPROGRESS`.
export
einprogress : Int
einprogress = unsafePerformIO $ primIO prim__einprogress

||| The errno code `ETIMEDOUT`: the code of a deadline that came first.
export
etimedout : Int
etimedout = unsafePerformIO $ primIO prim__etimedout

||| The errno code `EPIPE`: a write after the peer closed its end.
export
epipe : Int
epipe = unsafePerformIO $ primIO prim__epipe

||| The errno code `ECONNRESET`.
export
econnreset : Int
econnreset = unsafePerformIO $ primIO prim__econnreset

||| The errno code `ECONNREFUSED`.
export
econnrefused : Int
econnrefused = unsafePerformIO $ primIO prim__econnrefused

||| The errno code `ENOTCONN`.
export
enotconn : Int
enotconn = unsafePerformIO $ primIO prim__enotconn

negEAgain : Int
negEAgain = negate eagain

negETimedOut : Int
negETimedOut = negate etimedout

negEBadF : Int
negEBadF = negate ebadf

negEInProgress : Int
negEInProgress = negate einprogress

||| What went wrong.
public export
data NetError
  = ||| The deadline came first (or the system gave up: `ETIMEDOUT`).
    Timeout
  | ||| The socket was closed (with `close`, maybe by another thread while
    ||| this one waited for it): `EBADF`.
    Closed
  | ||| Another error of the system: its errno code and message.
    SysError Int String
  | ||| A name could not be resolved: the message of getaddrinfo(3).
    ResolveError String

export
Show NetError where
  show Timeout = "timed out"
  show Closed = "socket closed"
  show (SysError e msg) = msg ++ " (errno " ++ show e ++ ")"
  show (ResolveError msg) = "cannot resolve: " ++ msg

export
Eq NetError where
  Timeout == Timeout = True
  Closed == Closed = True
  SysError a _ == SysError b _ = a == b
  ResolveError a == ResolveError b = a == b
  _ == _ = False

||| The message of an errno code.
export
errnoMessage : Int -> String
errnoMessage e = unsafePerformIO $ primIO $ prim__strerror e

||| The error of a negative code of `recvCode` and the like.
export
codeError : (code : Int) -> NetError
codeError code
    = if code == negETimedOut then Timeout
      else if code == negEBadF then Closed
      else SysError (negate code) (errnoMessage (negate code))

||| Did the peer go away (`EPIPE`, `ECONNRESET`)?
export
isPeerGone : NetError -> Bool
isPeerGone (SysError e _) = e == epipe || e == econnreset
isPeerGone _ = False

-- `Right x` for a code that is not negative, the error otherwise.
%inline
fromCode : Int -> (Int -> a) -> Either NetError a
fromCode r f = if r < 0 then Left (codeError r) else Right (f r)

%inline
deadlineCode : Maybe Int -> Int
deadlineCode Nothing = -1
deadlineCode (Just d) = if d < 0 then 0 else d

-- ---------------------------------------------------------------------------
-- Sockets

||| A non-blocking socket (its descriptor: there is nothing else to it).
public export
record AsyncSocket where
  constructor MkAsyncSocket
  ||| The file descriptor.
  fd : Int

export
Show AsyncSocket where
  show s = "socket " ++ show s.fd

||| The kind of a socket.
public export
data SockType = StreamSocket | DatagramSocket

||| A new non-blocking socket, closed when the program runs another one.
export
socket : HasIO io => Family -> SockType -> io (Either NetError AsyncSocket)
socket fam ty
    = do r <- primIO $ prim__socket (familyCode fam)
                                    (case ty of
                                       StreamSocket => 1
                                       DatagramSocket => 2)
         pure $ fromCode r MkAsyncSocket

||| Close the socket: the threads that wait for it are woken up (their
||| operation fails with `Closed`), and the reactor forgets it.  Never close
||| the descriptor another way.
export
close : HasIO io => AsyncSocket -> io (Either NetError ())
close s = do r <- closeFd s.fd
             pure $ fromCode r (const ())

||| Restore the blocking mode of the socket and make the reactor forget it,
||| before handing it over to code that blocks (`fdopen`, C code).  The
||| socket must not be used with this module afterwards.
export
makeBlocking : HasIO io => AsyncSocket -> io (Either NetError ())
makeBlocking s = do r <- primIO $ prim__makeBlocking s.fd
                    pure $ fromCode r (const ())

||| The direction to shut down.
public export
data ShutdownHow = ShutRead | ShutWrite | ShutBoth

||| shutdown(2): `ShutWrite` sends the end of the stream to the peer while
||| the socket can still read.
export
shutdown : HasIO io => AsyncSocket -> ShutdownHow -> io (Either NetError ())
shutdown s how
    = do r <- primIO $ prim__shutdown s.fd (case how of
                                              ShutRead => 0
                                              ShutWrite => 1
                                              ShutBoth => 2)
         pure $ fromCode r (const ())

-- ---------------------------------------------------------------------------
-- Options

||| The socket options.  Their values are `Int`s: 1 and 0 for the ones that
||| are on or off; bytes for `RecvBuffer` and `SendBuffer` (the system may
||| round or double them); seconds for `Linger`, -1 meaning off.
public export
data SockOption
  = ||| SO_REUSEADDR: bind to a port that a closed connection still holds.
    ReuseAddr
  | ||| SO_REUSEPORT: several sockets listening on one port (where the
    ||| system has it; `ENOPROTOOPT` otherwise).
    ReusePort
  | ||| TCP_NODELAY: send small segments at once (no Nagle).
    NoDelay
  | ||| SO_KEEPALIVE.
    KeepAlive
  | ||| SO_RCVBUF.
    RecvBuffer
  | ||| SO_SNDBUF.
    SendBuffer
  | ||| SO_LINGER: how long `close` waits for unsent data, -1 when it does
    ||| not wait (the default); 0 resets the connection at close.
    Linger
  | ||| IPV6_V6ONLY: an IPv6 socket that does not take IPv4 connections.
    V6Only
  | ||| SO_BROADCAST: a datagram socket may send to broadcast addresses.
    Broadcast

optionCode : SockOption -> Int
optionCode ReuseAddr = 1
optionCode ReusePort = 2
optionCode NoDelay = 3
optionCode KeepAlive = 4
optionCode RecvBuffer = 5
optionCode SendBuffer = 6
optionCode Linger = 7
optionCode V6Only = 8
optionCode Broadcast = 9

||| Set an option (see `SockOption` for the values).
export
setOption : HasIO io => AsyncSocket -> SockOption -> Int -> io (Either NetError ())
setOption s opt v
    = do r <- primIO $ prim__setOpt s.fd (optionCode opt) v
         pure $ fromCode r (const ())

||| The value of an option (see `SockOption`).
export
getOption : HasIO io => AsyncSocket -> SockOption -> io (Either NetError Int)
getOption s opt
    = do r <- primIO $ prim__getOpt s.fd (optionCode opt)
         pure $ case opt of
                  Linger => fromCode r (\v => if v == 0 then -1 else v - 1)
                  _ => fromCode r id

-- ---------------------------------------------------------------------------
-- Addresses

-- The size of a buffer of a socket address (IDRNET_ASYNC_ADDR_SIZE).
addrBufferSize : Int
addrBufferSize = 128

-- (covering: newBuffer fails only when out of memory)
newAddrBuffer : HasIO io => io (Either NetError Buffer)
newAddrBuffer
    = do Just b <- newBuffer addrBufferSize
           | Nothing => pure (Left (SysError einval "cannot allocate a buffer"))
         pure (Right b)

decodeAddr : HasIO io => Buffer -> io (Either NetError SockAddr)
decodeAddr b
    = do fam <- primIO $ prim__addrFamily b
         case familyOfCode fam of
           Nothing => pure (Left (SysError einval "address of an unknown family"))
           Just f => do port <- primIO $ prim__addrPort b
                        host <- primIO $ prim__addrHost b
                        pure (Right (mkSockAddr f host port))

getName : HasIO io => Int -> AsyncSocket -> io (Either NetError SockAddr)
getName peer s
    = do Right b <- newAddrBuffer
           | Left e => pure (Left e)
         r <- primIO $ prim__getName s.fd peer b
         if r < 0 then pure (Left (codeError r)) else decodeAddr b

||| The address the socket is bound to (getsockname(2)): the port a socket
||| bound to port 0 got, say.
export
localAddress : HasIO io => AsyncSocket -> io (Either NetError SockAddr)
localAddress = getName 0

||| The address of the peer (getpeername(2)).
export
peerAddress : HasIO io => AsyncSocket -> io (Either NetError SockAddr)
peerAddress = getName 1

||| Bind the socket to a numeric address ("" for the host binds to any
||| address of the family).
export
bind : HasIO io => AsyncSocket -> SockAddr -> io (Either NetError ())
bind s a
    = do r <- primIO $ prim__bind s.fd (familyCode (addrFamily a)) (addrHost a) (addrPort a)
         pure $ fromCode r (const ())

||| listen(2), with the length of the queue of connections not accepted yet
||| (the system may cap it: `/proc/sys/net/core/somaxconn` on Linux).
export
listen : HasIO io => AsyncSocket -> (backlog : Int) -> io (Either NetError ())
listen s backlog
    = do r <- primIO $ prim__listen s.fd backlog
         pure $ fromCode r (const ())

||| A stream socket listening on a numeric address: made with `ReuseAddr`
||| (not for a Unix socket), bound, and listening with the given backlog.
||| Port 0 picks a free port: see `localAddress`.  The socket is closed when
||| a step fails.
export
listenOn : HasIO io => SockAddr -> (backlog : Int) -> io (Either NetError AsyncSocket)
listenOn a backlog
    = do Right s <- socket (addrFamily a) StreamSocket
           | Left e => pure (Left e)
         Right () <- the (io (Either NetError ())) $ case addrFamily a of
                       Unix => pure (Right ())
                       _ => setOption s ReuseAddr 1
           | Left e => do ignore (close s); pure (Left e)
         Right () <- bind s a
           | Left e => do ignore (close s); pure (Left e)
         Right () <- listen s backlog
           | Left e => do ignore (close s); pure (Left e)
         pure (Right s)

-- ---------------------------------------------------------------------------
-- The loops: try, wait on EAGAIN, try again

-- Wait for `fd`: 1 to try again, or the code to give up with.
%inline
waitCode : Int -> Int -> Int -> IO Int
waitCode fd ev deadline
    = do w <- primIO $ prim__wait fd ev (cast deadline)
         pure $ if w == 1 then 1
                else if w == 0 then negETimedOut
                else w

-- Is the range in the buffer?  -EINVAL otherwise.
%inline
checkRange : Buffer -> Int -> Int -> IO Bool
checkRange buf offset len
    = do size <- rawSize buf
         pure (offset >= 0 && len >= 0 && offset <= size - len)

covering
recvLoop : Int -> Buffer -> Int -> Int -> Int -> IO Int
recvLoop fd buf offset len deadline
    = do r <- primIO $ prim__recv fd buf offset len
         if r /= negEAgain then pure r else do
           w <- waitCode fd 1 deadline
           if w == 1 then recvLoop fd buf offset len deadline else pure w

covering
sendLoop : Int -> Buffer -> Int -> Int -> Int -> IO Int
sendLoop fd buf offset len deadline
    = do r <- primIO $ prim__send fd buf offset len
         if r /= negEAgain then pure r else do
           w <- waitCode fd 2 deadline
           if w == 1 then sendLoop fd buf offset len deadline else pure w

covering
sendAllLoop : Int -> Buffer -> Int -> Int -> Int -> IO Int
sendAllLoop fd buf offset len deadline
    = if len <= 0 then pure 0 else do
        r <- sendLoop fd buf offset len deadline
        if r < 0 then pure r else sendAllLoop fd buf (offset + r) (len - r) deadline

covering
recvExactlyLoop : Int -> Buffer -> Int -> Int -> Int -> Int -> IO Int
recvExactlyLoop fd buf offset len deadline done
    = if len <= 0 then pure done else do
        r <- recvLoop fd buf offset len deadline
        if r < 0 then pure r
          else if r == 0 then pure done
          else recvExactlyLoop fd buf (offset + r) (len - r) deadline (done + r)

-- ---------------------------------------------------------------------------
-- Receiving and sending: codes

||| One recv(2) into `len` bytes of the buffer from `offset`, without
||| waiting: the number of bytes (0 at the end of the stream), `-EAGAIN`
||| when there is nothing to read yet (see `System.IO.Fd.wouldBlock`; wait
||| with `waitReadable`), or minus an errno code (`-EINVAL` when the range is
||| not in the buffer).
export
tryRecv : HasIO io => AsyncSocket -> Buffer -> (offset, len : Int) -> io Int
tryRecv s buf offset len
    = liftIO $ do True <- checkRange buf offset len
                    | False => pure (negate einval)
                  primIO $ prim__recv s.fd buf offset len

||| One send(2) of `len` bytes of the buffer from `offset`, without
||| waiting: the number of bytes sent, `-EAGAIN` when nothing can be sent
||| yet, or minus an errno code.
export
trySend : HasIO io => AsyncSocket -> Buffer -> (offset, len : Int) -> io Int
trySend s buf offset len
    = liftIO $ do True <- checkRange buf offset len
                    | False => pure (negate einval)
                  primIO $ prim__send s.fd buf offset len

||| Receive at most `len` bytes into the buffer from `offset`, waiting until
||| some come or until the deadline (an absolute time on the clock of
||| `now`; negative for none): the number of bytes (0 at the end of the
||| stream), or minus an errno code: `-ETIMEDOUT` at the deadline, `-EBADF`
||| when the socket was closed meanwhile, `-EINVAL` when the range is not in
||| the buffer.  No allocation when data is there.
export covering
recvCode : HasIO io => AsyncSocket -> Buffer -> (offset, len : Int) ->
           (deadline : Int) -> io Int
recvCode s buf offset len deadline
    = liftIO $ do True <- checkRange buf offset len
                    | False => pure (negate einval)
                  recvLoop s.fd buf offset len deadline

||| Send at most `len` bytes of the buffer from `offset`, waiting until some
||| can be sent: the number of bytes sent (maybe fewer than `len`), or minus
||| an errno code, as for `recvCode`.
export covering
sendCode : HasIO io => AsyncSocket -> Buffer -> (offset, len : Int) ->
           (deadline : Int) -> io Int
sendCode s buf offset len deadline
    = liftIO $ do True <- checkRange buf offset len
                    | False => pure (negate einval)
                  sendLoop s.fd buf offset len deadline

||| Send all `len` bytes of the buffer from `offset`: 0, or minus an errno
||| code, as for `recvCode` (some of the bytes may have been sent then).
export covering
sendAllCode : HasIO io => AsyncSocket -> Buffer -> (offset, len : Int) ->
              (deadline : Int) -> io Int
sendAllCode s buf offset len deadline
    = liftIO $ do True <- checkRange buf offset len
                    | False => pure (negate einval)
                  sendAllLoop s.fd buf offset len deadline

||| Receive `len` bytes into the buffer from `offset`, unless the stream
||| ends first: the number of bytes received (`len`, or fewer at the end of
||| the stream), or minus an errno code, as for `recvCode`.
export covering
recvExactlyCode : HasIO io => AsyncSocket -> Buffer -> (offset, len : Int) ->
                  (deadline : Int) -> io Int
recvExactlyCode s buf offset len deadline
    = liftIO $ do True <- checkRange buf offset len
                    | False => pure (negate einval)
                  recvExactlyLoop s.fd buf offset len deadline 0

-- ---------------------------------------------------------------------------
-- Receiving and sending

||| Receive at most `len` bytes into the buffer from `offset`, waiting until
||| some come or until the deadline: the number of bytes, 0 at the end of
||| the stream (the peer closed or shut down its end).
export covering
recv : HasIO io => AsyncSocket -> Buffer -> (offset, len : Int) ->
       (deadline : Maybe Int) -> io (Either NetError Int)
recv s buf offset len deadline
    = do r <- recvCode s buf offset len (deadlineCode deadline)
         pure $ fromCode r id

||| Send at most `len` bytes of the buffer from `offset`, waiting until
||| some can be sent: the number of bytes sent, maybe fewer than `len` (see
||| `sendAll`).
export covering
send : HasIO io => AsyncSocket -> Buffer -> (offset, len : Int) ->
       (deadline : Maybe Int) -> io (Either NetError Int)
send s buf offset len deadline
    = do r <- sendCode s buf offset len (deadlineCode deadline)
         pure $ fromCode r id

||| Send all `len` bytes of the buffer from `offset`.
export covering
sendAll : HasIO io => AsyncSocket -> Buffer -> (offset, len : Int) ->
          (deadline : Maybe Int) -> io (Either NetError ())
sendAll s buf offset len deadline
    = do r <- sendAllCode s buf offset len (deadlineCode deadline)
         pure $ fromCode r (const ())

||| Receive `len` bytes into the buffer from `offset`, unless the stream
||| ends first: the number of bytes received, `len` or fewer at the end of
||| the stream.
export covering
recvExactly : HasIO io => AsyncSocket -> Buffer -> (offset, len : Int) ->
              (deadline : Maybe Int) -> io (Either NetError Int)
recvExactly s buf offset len deadline
    = do r <- recvExactlyCode s buf offset len (deadlineCode deadline)
         pure $ fromCode r id

covering
send2Loop : Int -> Buffer -> Int -> Int -> Buffer -> Int -> Int -> Int -> IO Int
send2Loop fd b1 o1 l1 b2 o2 l2 deadline
    = if l1 <= 0 then sendAllLoop fd b2 o2 l2 deadline else do
        r <- primIO $ prim__send2 fd b1 o1 l1 b2 o2 l2
        if r == negEAgain
          then do w <- waitCode fd 2 deadline
                  if w == 1 then send2Loop fd b1 o1 l1 b2 o2 l2 deadline else pure w
          else if r < 0 then pure r
          else if r >= l1
            then sendAllLoop fd b2 (o2 + (r - l1)) (l2 - (r - l1)) deadline
            else send2Loop fd b1 (o1 + r) (l1 - r) b2 o2 l2 deadline

||| Send all of two ranges, one after the other (a head and a body, say),
||| with one system call (sendmsg(2)) when the socket takes them all: 0, or
||| minus an errno code, as for `recvCode`.
export covering
sendAll2Code : HasIO io => AsyncSocket ->
               Buffer -> (offset1, len1 : Int) ->
               Buffer -> (offset2, len2 : Int) ->
               (deadline : Int) -> io Int
sendAll2Code s b1 o1 l1 b2 o2 l2 deadline
    = liftIO $ do True <- checkRange b1 o1 l1
                    | False => pure (negate einval)
                  True <- checkRange b2 o2 l2
                    | False => pure (negate einval)
                  send2Loop s.fd b1 o1 l1 b2 o2 l2 deadline

||| Send all of two ranges, one after the other, with one system call when
||| the socket takes them all.
export covering
sendAll2 : HasIO io => AsyncSocket ->
           Buffer -> (offset1, len1 : Int) ->
           Buffer -> (offset2, len2 : Int) ->
           (deadline : Maybe Int) -> io (Either NetError ())
sendAll2 s b1 o1 l1 b2 o2 l2 deadline
    = do r <- sendAll2Code s b1 o1 l1 b2 o2 l2 (deadlineCode deadline)
         pure $ fromCode r (const ())

-- ---------------------------------------------------------------------------
-- Connections

covering
acceptLoop : Int -> Int -> IO Int
acceptLoop fd deadline
    = do r <- primIO $ prim__accept fd
         if r /= negEAgain then pure r else do
           w <- waitCode fd 1 deadline
           if w == 1 then acceptLoop fd deadline else pure w

covering
acceptAddrLoop : Int -> Buffer -> Int -> IO Int
acceptAddrLoop fd b deadline
    = do r <- primIO $ prim__acceptAddr fd b
         if r /= negEAgain then pure r else do
           w <- waitCode fd 1 deadline
           if w == 1 then acceptAddrLoop fd b deadline else pure w

||| Accept a connection on a listening socket, waiting for one until the
||| deadline: the descriptor of a new non-blocking socket, or minus an errno
||| code, as for `recvCode`.
export covering
acceptCode : HasIO io => AsyncSocket -> (deadline : Int) -> io Int
acceptCode s deadline = liftIO $ acceptLoop s.fd deadline

||| Accept a connection on a listening socket, waiting for one until the
||| deadline.  The new socket is non-blocking.  (`acceptFrom` gives the
||| address of the peer too.)
export covering
accept : HasIO io => AsyncSocket -> (deadline : Maybe Int) ->
         io (Either NetError AsyncSocket)
accept s deadline
    = do r <- acceptCode s (deadlineCode deadline)
         pure $ fromCode r MkAsyncSocket

||| Accept a connection, and give the address of the peer.
export covering
acceptFrom : HasIO io => AsyncSocket -> (deadline : Maybe Int) ->
             io (Either NetError (AsyncSocket, SockAddr))
acceptFrom s deadline
    = do Right b <- newAddrBuffer
           | Left e => pure (Left e)
         r <- liftIO $ acceptAddrLoop s.fd b (deadlineCode deadline)
         if r < 0 then pure (Left (codeError r)) else do
           Right a <- decodeAddr b
             | Left _ => pure (Right (MkAsyncSocket r, UnixPath ""))
           pure (Right (MkAsyncSocket r, a))

covering
connectWait : Int -> Int -> IO Int
connectWait fd deadline
    = do w <- waitCode fd 2 deadline
         if w /= 1 then pure w else do
           r <- primIO $ prim__connectResult fd
           if r == negEInProgress then connectWait fd deadline else pure r

||| Connect a socket that the caller made (to set options first, or to bind
||| it) to a numeric address, waiting until the deadline: on `Timeout` the
||| connection is not made and the socket should be closed.
export covering
connectSocket : HasIO io => AsyncSocket -> SockAddr -> (deadline : Maybe Int) ->
                io (Either NetError ())
connectSocket s a deadline
    = do r <- primIO $ prim__connect s.fd (familyCode (addrFamily a)) (addrHost a) (addrPort a)
         r <- if r == negEInProgress
                then liftIO $ connectWait s.fd (deadlineCode deadline)
                else pure r
         pure $ fromCode r (const ())

||| A new stream socket connected to a numeric address, waiting until the
||| deadline.  The socket is closed when the connection fails.
export covering
connect : HasIO io => SockAddr -> (deadline : Maybe Int) ->
          io (Either NetError AsyncSocket)
connect a deadline
    = do Right s <- socket (addrFamily a) StreamSocket
           | Left e => pure (Left e)
         Right () <- connectSocket s a deadline
           | Left e => do ignore (close s); pure (Left e)
         pure (Right s)

||| Resolve a name (`Network.Socket.DNS.resolve`), then connect to its
||| addresses in turn until one takes the connection, all before the
||| deadline.  The error is the one of the last address tried.
export covering
connectHost : HasIO io => (host : String) -> (port : Int) ->
              (deadline : Maybe Int) -> io (Either NetError AsyncSocket)
connectHost host port deadline
    = do Right addrs <- resolve host port Nothing
           | Left msg => pure (Left (ResolveError msg))
         tryAll addrs (Left (ResolveError "no address"))
  where
    tryAll : List SockAddr -> Either NetError AsyncSocket ->
             io (Either NetError AsyncSocket)
    tryAll [] err = pure err
    tryAll (a :: as) _
        = do Right s <- connect a deadline
               | Left Timeout => pure (Left Timeout)
               | Left e => tryAll as (Left e)
             pure (Right s)

-- ---------------------------------------------------------------------------
-- Datagrams

covering
recvFromLoop : Int -> Buffer -> Int -> Int -> Buffer -> Int -> IO Int
recvFromLoop fd buf offset len ab deadline
    = do r <- primIO $ prim__recvFrom fd buf offset len ab
         if r /= negEAgain then pure r else do
           w <- waitCode fd 1 deadline
           if w == 1 then recvFromLoop fd buf offset len ab deadline else pure w

covering
sendToLoop : Int -> Buffer -> Int -> Int -> Int -> String -> Int -> Int -> IO Int
sendToLoop fd buf offset len fam host port deadline
    = do r <- primIO $ prim__sendTo fd buf offset len fam host port
         if r /= negEAgain then pure r else do
           w <- waitCode fd 2 deadline
           if w == 1 then sendToLoop fd buf offset len fam host port deadline else pure w

||| Receive a datagram into at most `len` bytes of the buffer from
||| `offset` (the rest of a longer datagram is lost), waiting until the
||| deadline: its length and the address of its sender.
export covering
recvFrom : HasIO io => AsyncSocket -> Buffer -> (offset, len : Int) ->
           (deadline : Maybe Int) -> io (Either NetError (Int, SockAddr))
recvFrom s buf offset len deadline
    = do Right ab <- newAddrBuffer
           | Left e => pure (Left e)
         r <- liftIO $ do True <- checkRange buf offset len
                            | False => pure (negate einval)
                          recvFromLoop s.fd buf offset len ab (deadlineCode deadline)
         if r < 0 then pure (Left (codeError r)) else do
           Right a <- decodeAddr ab
             | Left _ => pure (Right (r, UnixPath ""))
           pure (Right (r, a))

||| Send `len` bytes of the buffer from `offset` as one datagram to a
||| numeric address, waiting until the deadline for room: the number of
||| bytes sent.
export covering
sendTo : HasIO io => AsyncSocket -> Buffer -> (offset, len : Int) ->
         SockAddr -> (deadline : Maybe Int) -> io (Either NetError Int)
sendTo s buf offset len a deadline
    = do r <- liftIO $ do True <- checkRange buf offset len
                            | False => pure (negate einval)
                          sendToLoop s.fd buf offset len (familyCode (addrFamily a))
                                     (addrHost a) (addrPort a) (deadlineCode deadline)
         pure $ fromCode r id
