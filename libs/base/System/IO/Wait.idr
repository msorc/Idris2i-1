||| Waiting for a file descriptor to become readable or writable.
|||
||| On the RefC back end, a thread that waits parks in the scheduler: the
||| other threads of its worker keep running (see "Waiting for file
||| descriptors" in the documentation of the back end).  The readiness is
||| edge triggered there: wait only after a read or a write on a
||| non-blocking descriptor failed with `EAGAIN` (see `System.IO.Fd`), and
||| be ready for a wait that says `Ready` when the descriptor is not (another
||| thread took the data first): try again, and wait again on `EAGAIN`.
|||
||| On the Chez and Racket back ends, whose threads are OS threads, a wait
||| blocks the thread that waits in poll(2).  The JavaScript back ends do not
||| support it.
|||
||| Deadlines are absolute times in nanoseconds on the clock of `now`.
module System.IO.Wait

%default total

||| What to wait for.
public export
data IOEvent = Readable | Writable

export
Show IOEvent where
  show Readable = "Readable"
  show Writable = "Writable"

export
Eq IOEvent where
  Readable == Readable = True
  Writable == Writable = True
  _ == _ = False

||| The result of a wait.
public export
data WaitResult
  = ||| The descriptor may be ready.
    Ready
  | ||| The deadline came first.
    TimedOut
  | ||| An error, with its errno code (`EBADF` when the descriptor was
    ||| closed with `closeFd` while waiting).
    WaitError Int

export
Show WaitResult where
  show Ready = "Ready"
  show TimedOut = "TimedOut"
  show (WaitError e) = "WaitError " ++ show e

export
Eq WaitResult where
  Ready == Ready = True
  TimedOut == TimedOut = True
  WaitError a == WaitError b = a == b
  _ == _ = False

%foreign "RefC:idris2i_1_monotonicNanoseconds"
         "C:idris2i_1_fdMonotonicNanoseconds, libidris2i_1_support, idris_fd.h"
         "javascript:lambda:() => { throw new Error('System.IO.Wait is not supported by the JavaScript back ends') }"
prim__now : PrimIO Int64

%foreign "RefC:idris2i_1_ioWait"
         "C__collect_safe:idris2i_1_fdWaitBlocking, libidris2i_1_support, idris_fd.h"
         "C:idris2i_1_fdWaitBlocking, libidris2i_1_support, idris_fd.h"
         "javascript:lambda:() => { throw new Error('System.IO.Wait is not supported by the JavaScript back ends') }"
prim__ioWait : (fd : Int) -> (event : Int) -> (deadline : Int64) -> PrimIO Int

%foreign "RefC:idris2i_1_ioClose"
         "C:idris2i_1_fdClose, libidris2i_1_support, idris_fd.h"
         "javascript:lambda:() => { throw new Error('System.IO.Wait is not supported by the JavaScript back ends') }"
prim__ioClose : (fd : Int) -> PrimIO Int

%foreign "RefC:idris2i_1_ioForget"
         "C:idris2i_1_fdForget, libidris2i_1_support, idris_fd.h"
         "javascript:lambda:() => { throw new Error('System.IO.Wait is not supported by the JavaScript back ends') }"
prim__ioForget : (fd : Int) -> PrimIO ()

||| The current time, in nanoseconds, on the monotonic clock of the
||| deadlines.
export
now : HasIO io => io Int
now = cast <$> primIO prim__now

||| The deadline `nanoseconds` from now.
export
deadlineIn : HasIO io => (nanoseconds : Int) -> io Int
deadlineIn ns = pure $ !now + ns

||| Wait until `fd` is ready for `event`, or until the deadline, if any.
export
waitFd : HasIO io => (fd : Int) -> IOEvent -> (deadline : Maybe Int) ->
         io WaitResult
waitFd fd ev deadline
    = do r <- primIO $ prim__ioWait fd (case ev of
                                          Readable => 1
                                          Writable => 2)
                                       (case deadline of
                                          Nothing => -1
                                          Just d => if d < 0 then 0 else cast d)
         pure $ if r == 1 then Ready
                else if r == 0 then TimedOut
                else WaitError (negate r)

||| Wait until `fd` is readable, or until the deadline, if any.
export
waitReadable : HasIO io => (fd : Int) -> (deadline : Maybe Int) -> io WaitResult
waitReadable fd = waitFd fd Readable

||| Wait until `fd` is writable, or until the deadline, if any.
export
waitWritable : HasIO io => (fd : Int) -> (deadline : Maybe Int) -> io WaitResult
waitWritable fd = waitFd fd Writable

||| Close a descriptor that threads may wait for: they are woken up, and
||| their wait returns `WaitError EBADF`.  Returns 0, or minus the errno code
||| of close(2).  Close a descriptor this way once a thread waited for it
||| (or `forgetFd` it first): the RefC back end keeps it registered with the
||| operating system otherwise.
export
closeFd : HasIO io => (fd : Int) -> io Int
closeFd fd = primIO $ prim__ioClose fd

||| Make the RefC back end forget a descriptor without closing it, before
||| handing it over to code that closes it (`fdopen`, C code).  Threads that
||| wait for it are woken up as by `closeFd`.
export
forgetFd : HasIO io => (fd : Int) -> io ()
forgetFd fd = primIO $ prim__ioForget fd
