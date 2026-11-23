-- Many threads, each waiting for a pipe of its own: a token goes around the
-- ring of pipes, from each thread to the next one.
import Data.Buffer
import System
import System.Concurrency
import Data.List
import Data.Zippable
import System.IO.Fd

nonBlockingPipe : IO (Int, Int)
nonBlockingPipe = do
  Right (r, w) <- pipe
    | Left e => die "pipe: \{show e}"
  ignore $ setNonBlocking r
  ignore $ setNonBlocking w
  pure (r, w)

-- Pass `rounds` tokens from `from` to `to`.
relay : Int -> Int -> Nat -> IO ()
relay from to Z = pure ()
relay from to (S k) = do
  Just buf <- newBuffer 1
    | Nothing => die "newBuffer"
  1 <- readFdWait from buf 0 1
    | r => die "read: \{show r}"
  1 <- writeFdWait to buf 0 1
    | r => die "write: \{show r}"
  relay from to k

threads : Nat
threads = 200

rounds : Nat
rounds = 50

main : IO ()
main = do
  pipes <- for [1 .. threads + 1] $ \_ => nonBlockingPipe
  let links = zip pipes (drop 1 pipes)
  ts <- for links $ \((r, _), (_, w)) => fork (relay r w rounds)
  let Just (_, first) = head' pipes
    | Nothing => die "no pipes"
  let Just (last, _) = last' pipes
    | Nothing => die "no pipes"
  Just buf <- newBuffer 1
    | Nothing => die "newBuffer"
  let go : Nat -> IO ()
      go Z = pure ()
      go (S k) = do
        setByte buf 0 (cast k)
        1 <- writeFdWait first buf 0 1
          | r => die "write: \{show r}"
        1 <- readFdWait last buf 0 1
          | r => die "read: \{show r}"
        go k
  go rounds
  traverse_ (\t => threadWait t) ts
  traverse_ (\(r, w) => do ignore (closeFd r); ignore (closeFd w)) pipes
  putStrLn "the token went \{show rounds} times around \{show threads} threads"
