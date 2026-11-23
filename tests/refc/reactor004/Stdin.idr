-- Every thread is blocked, the main one waiting for standard input, which
-- comes late: that is not a deadlock.
import Data.Buffer
import System
import System.Concurrency
import System.IO.Fd

main : IO ()
main = do
  ignore $ setNonBlocking 0
  c <- makeChannel {a = Int}
  t <- fork $ do
    ignore $ channelGet c
    putStrLn "the thread got its value"
  Just buf <- newBuffer 100
    | Nothing => die "newBuffer"
  k <- readFdWait 0 buf 0 100
  putStr "stdin: \{!(getString buf 0 k)}"
  channelPut c 1
  threadWait t
