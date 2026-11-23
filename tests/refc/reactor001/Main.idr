-- Threads that wait for file descriptors: woken up by data, by a deadline,
-- by the descriptor being closed, several on one descriptor, and a writer
-- waiting for room in a pipe.  The first wait (on standard input, which
-- the test script feeds late) comes before the first fork.
import Data.Buffer
import Data.IORef
import Data.List
import System
import System.Concurrency
import System.IO.Fd

nonBlockingPipe : IO (Int, Int)
nonBlockingPipe = do
  Right (r, w) <- pipe
    | Left e => die "pipe: \{show e}"
  0 <- setNonBlocking r
    | e => die "setNonBlocking: \{show e}"
  0 <- setNonBlocking w
    | e => die "setNonBlocking: \{show e}"
  pure (r, w)

writeString : Int -> String -> IO ()
writeString fd s = do
  let n = stringByteLength s
  Just buf <- newBuffer n
    | Nothing => die "newBuffer"
  setString buf 0 s
  r <- writeFdWait fd buf 0 n
  when (r /= n) $ die "write: \{show r}"

-- Read up to `n` bytes, waiting for them.
readString : Int -> Int -> IO String
readString fd n = do
  Just buf <- newBuffer n
    | Nothing => die "newBuffer"
  r <- readFdWait fd buf 0 n
  if r < 0
     then pure "error \{show (negate r)}"
     else getString buf 0 r

-- Write until the pipe is full.
fill : Int -> Buffer -> Int -> IO Int
fill w big done = do
  k <- writeFd w big 0 4096
  if k > 0 then fill w big (done + k) else pure done

-- Read `left` bytes that are in the pipe.
drain : Int -> Buffer -> Int -> IO ()
drain r big left = when (left > 0) $ do
  k <- readFd r big 0 (min left 4096)
  if k > 0 then drain r big (left - k) else pure ()

main : IO ()
main = do
  args <- getArgs
  let closeWakes = not (elem "--close-does-not-wake" args)
  let useStdin = not (elem "--no-stdin" args)

  -- Before the first fork: only the main thread, which waits for the data
  -- that the test script writes late to standard input.
  when useStdin $ do
    0 <- setNonBlocking 0
      | e => die "setNonBlocking: \{show e}"
    line <- readString 0 100
    putStr "stdin: \{line}"

  (r, w) <- nonBlockingPipe
  Just buf <- newBuffer 16
    | Nothing => die "newBuffer"
  n <- readFd r buf 0 16
  putStrLn "an empty pipe would block: \{show (wouldBlock n)}"

  -- A deadline.
  start <- now
  res <- waitReadable r (Just (start + 30000000))
  end <- now
  putStrLn "wait with a deadline: \{show res}, after 30ms: \{show (end - start >= 30000000)}"
  res <- waitReadable r (Just 0)
  putStrLn "wait with a deadline in the past: \{show res}"

  -- Woken up by data, written by the main thread after a while.
  done <- makeChannel
  t <- fork $ do
    s <- readString r 100
    channelPut done s
  usleep 20000
  writeString w "hello from main\n"
  s <- channelGet done
  putStr "thread got: \{s}"
  threadWait t

  -- Several threads waiting for the same descriptor: each takes one byte.
  results <- makeChannel
  ts <- for [1 .. 10] $ \i => fork $ do
    s <- readString r 1
    channelPut results s
  usleep 20000
  writeString w "abcde"
  usleep 20000
  writeString w "fghij"
  got <- for [1 .. 10] $ \_ => channelGet results
  traverse_ (\t => threadWait t) ts
  putStrLn "ten waiters got: \{concat (sort got)}"

  -- A writer that waits for room in the pipe.
  Just big <- newBuffer 4096
    | Nothing => die "newBuffer"
  filled <- fill w big 0
  putStrLn "the pipe is full: \{show (filled > 0)}"
  wrote <- makeChannel
  t <- fork $ do
    k <- writeFdWait w big 0 100
    channelPut wrote k
  usleep 20000
  drain r big filled
  k <- channelGet wrote
  putStrLn "the writer wrote: \{show k}"
  threadWait t
  drain r big 100

  -- A descriptor closed while a thread waits for it.
  when closeWakes $ do
    t <- fork $ do
      -- (a wait may say that the descriptor is ready when it is not: the
      -- thread reads, and waits again)
      s <- readString r 1
      channelPut done (show (s == "error \{show ebadf}"))
    usleep 20000
    c <- closeFd r
    s <- channelGet done
    putStrLn "closed while waiting: \{show c} \{s}"
    threadWait t
  when (not closeWakes) $ ignore $ closeFd r
  ignore $ closeFd w

  -- A new pipe may get the numbers of the old one.
  (r2, w2) <- nonBlockingPipe
  t <- fork $ do
    s <- readString r2 100
    channelPut done s
  usleep 20000
  writeString w2 "after a reuse\n"
  s <- channelGet done
  putStr "thread got: \{s}"
  threadWait t
  ignore $ closeFd r2
  ignore $ closeFd w2
  putStrLn "done"
