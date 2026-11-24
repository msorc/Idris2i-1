||| Raw file descriptors: non-blocking reads and writes into buffers, and
||| pipes.
|||
||| The functions that can fail return minus the errno code in their
||| result: errno itself belongs to the OS thread, and a green thread of the
||| RefC back end may move to another OS thread between two calls.
module System.IO.Fd

import Data.Bits
import Data.Buffer
import public System.IO.Wait

%default total

fdC : String -> String
fdC fn = "C:\{fn}, libidris2i_1_support, idris_fd.h"

%foreign fdC "idris2i_1_fdSetNonBlocking"
prim__setNonBlocking : Int -> PrimIO Int

%foreign fdC "idris2i_1_fdRead"
prim__read : Int -> Buffer -> Int -> Int -> PrimIO Int

%foreign fdC "idris2i_1_fdWrite"
prim__write : Int -> Buffer -> Int -> Int -> PrimIO Int

%foreign fdC "idris2i_1_fdPipe"
prim__pipe : PrimIO Int64

%foreign fdC "idris2i_1_fdEAGAIN"
prim__eagain : PrimIO Int

%foreign fdC "idris2i_1_fdEWOULDBLOCK"
prim__ewouldblock : PrimIO Int

%foreign fdC "idris2i_1_fdEINTR"
prim__eintr : PrimIO Int

%foreign fdC "idris2i_1_fdEBADF"
prim__ebadf : PrimIO Int

%foreign fdC "idris2i_1_fdEINVAL"
prim__einval : PrimIO Int

||| The errno code `EAGAIN`.
export
eagain : Int
eagain = unsafePerformIO $ primIO prim__eagain

||| The errno code `EWOULDBLOCK` (often `EAGAIN`).
export
ewouldblock : Int
ewouldblock = unsafePerformIO $ primIO prim__ewouldblock

||| The errno code `EINTR`.
export
eintr : Int
eintr = unsafePerformIO $ primIO prim__eintr

||| The errno code `EBADF`.
export
ebadf : Int
ebadf = unsafePerformIO $ primIO prim__ebadf

||| The errno code `EINVAL`.
export
einval : Int
einval = unsafePerformIO $ primIO prim__einval

||| Is this result of `readFd` or `writeFd` "try again later"?
export
wouldBlock : Int -> Bool
wouldBlock r = r == negate eagain || r == negate ewouldblock

||| Make a descriptor non-blocking.  Returns 0, or minus the errno code.
export
setNonBlocking : HasIO io => (fd : Int) -> io Int
setNonBlocking fd = primIO $ prim__setNonBlocking fd

||| Read at most `max` bytes into the buffer, from `offset`.  Returns the
||| number of bytes read (0 at the end of the file), or minus the errno code
||| (`-EINVAL` when the bytes do not fit in the buffer).
export
readFd : HasIO io => (fd : Int) -> Buffer -> (offset : Int) -> (max : Int) ->
         io Int
readFd fd buf offset max
    = do size <- rawSize buf
         if offset < 0 || max < 0 || offset + max > size
            then pure (negate einval)
            else primIO $ prim__read fd buf offset max

||| Write at most `len` bytes of the buffer, from `offset`.  Returns the
||| number of bytes written, or minus the errno code (`-EINVAL` when the
||| bytes are not in the buffer, `-EPIPE` when the reader of a pipe or a
||| socket is gone: SIGPIPE is blocked for the call, so it does not kill
||| the program).
export
writeFd : HasIO io => (fd : Int) -> Buffer -> (offset : Int) -> (len : Int) ->
          io Int
writeFd fd buf offset len
    = do size <- rawSize buf
         if offset < 0 || len < 0 || offset + len > size
            then pure (negate einval)
            else primIO $ prim__write fd buf offset len

||| Like `readFd`, on a non-blocking descriptor: when there is nothing to
||| read yet, wait until there is (see `System.IO.Wait`).
export covering
readFdWait : HasIO io => (fd : Int) -> Buffer -> (offset : Int) -> (max : Int) ->
             io Int
readFdWait fd buf offset max
    = do r <- readFd fd buf offset max
         if wouldBlock r
            then case !(waitReadable fd Nothing) of
                   WaitError e => pure (negate e)
                   _ => readFdWait fd buf offset max
            else pure r

||| Like `writeFd`, on a non-blocking descriptor: when nothing can be
||| written yet, wait until something can (see `System.IO.Wait`).  Like
||| write(2), this may write fewer bytes than asked.
export covering
writeFdWait : HasIO io => (fd : Int) -> Buffer -> (offset : Int) -> (len : Int) ->
              io Int
writeFdWait fd buf offset len
    = do r <- writeFd fd buf offset len
         if wouldBlock r
            then case !(waitWritable fd Nothing) of
                   WaitError e => pure (negate e)
                   _ => writeFdWait fd buf offset len
            else pure r

||| Make a pipe: `Right (readEnd, writeEnd)`, or `Left` the errno code.  Both
||| ends are closed when the program runs another one (close-on-exec), and
||| they are blocking: see `setNonBlocking`.  Close them with `closeFd`.
export
pipe : HasIO io => io (Either Int (Int, Int))
pipe = do r <- cast {to = Int} <$> primIO prim__pipe
          pure $ if r < 0
                    then Left (negate r)
                    else Right (r .&. 0xffffffff, shiftR r 32)
