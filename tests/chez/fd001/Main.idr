-- A write to a pipe whose read end is closed fails with EPIPE, and the
-- program carries on: SIGPIPE does not kill it.
import Data.Buffer
import System
import System.Errno
import System.IO.Fd

main : IO ()
main = do
  Right (r, w) <- pipe
    | Left e => die "pipe: \{show e}"
  ignore $ closeFd r
  Just buf <- newBuffer 16
    | Nothing => die "newBuffer"
  n <- writeFd w buf 0 16
  putStrLn "the write failed: \{strerror (negate n)}"
  n <- writeFd w buf 0 16
  putStrLn "and again: \{strerror (negate n)}"
  ignore $ closeFd w
  putStrLn "the program is still running"
