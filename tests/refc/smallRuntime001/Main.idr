-- A program that uses neither threads nor the reactor does not link the
-- scheduler, the reactor nor the code that shares values between workers:
-- the runtime calls them through hooks that the first fork, the first wait
-- and the reactor set (see threads.c).  Each mode starts using a feature
-- late, after other work, to check that it then works as before.
import Data.Buffer
import Data.IORef
import System
import System.Concurrency
import System.IO.Fd

-- A constant (evaluated once, by a `cold` function).
table : List Int
table = map (* 3) [1 .. 100]

work : Int -> Int -> Int
work 0 acc = acc
work n acc = work (n - 1) ((acc * 31 + n) `mod` 1000003)

-- Recurse `depth` times, then run `act` (the first fork is deep in the
-- stack of the main thread).
deep : Nat -> IO a -> IO a
deep Z act = act
deep (S k) act = do
  r <- deep k act
  pure r

readString : Int -> Int -> IO String
readString fd n = do
  Just buf <- newBuffer n
    | Nothing => die "newBuffer"
  r <- readFdWait fd buf 0 n
  if r < 0 then pure "error \{show (negate r)}" else getString buf 0 r

-- Spin until the flag is set (by the main thread, on another worker).
spin : IORef Bool -> Int -> IO Int
spin flag n = do
  done <- readIORef flag
  if done then pure n else spin flag (n + 1)

partial
main : IO ()
main = do
  [_, mode] <- getArgs
    | _ => die "usage: main MODE"
  putStrLn "work: \{show (work 1000000 0)}, table: \{show (sum table)}"
  case mode of
    "hello" => putStrLn "hello"
    "crash" => printLn (idris_crash {a = Int} "a crash")
    "sleep" => do
      -- the first wait starts the scheduler, without a fork
      usleep 10000
      putStrLn "slept"
    "fork" => do
      ch <- makeChannel
      t <- deep 1000 $ fork $ channelPut ch (work 1000 0)
      v <- channelGet ch
      threadWait t
      flag <- newIORef False
      s <- fork $ do
        n <- spin flag 0
        putStrLn "the spinner stopped: \{show (n >= 0)}"
      usleep 20000
      writeIORef flag True
      threadWait s
      putStrLn "forked late: \{show v}"
    "io" => do
      -- the first reactor use, without a fork
      0 <- setNonBlocking 0
        | e => die "setNonBlocking: \{show e}"
      line <- readString 0 100
      putStr "stdin: \{line}"
    _ => die "unknown mode"
