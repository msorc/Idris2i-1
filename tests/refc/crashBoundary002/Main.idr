-- Crash boundaries and threads: a crash in one of 100 threads ends only the
-- action of its boundary, and the others finish their work; a Mutex that
-- the crashed code held stays held by its thread; a constant whose
-- evaluation crashed is evaluated by the next thread that needs it; a
-- boundary only catches the crashes of its own thread.
module Main

import Data.IORef
import Data.List
import System
import System.Concurrency
import System.Crash

%default partial

-- The work of a thread: the sum of 1 .. 1000 * (i + 1), the long way, with
-- a crash in the middle for one of them.
work : Int -> Int -> Int -> Int
work bad i k = go 0 1
  where
    go : Int -> Int -> Int
    go acc j =
      if j > 1000 * (i + 1) then acc
      else if i == bad && j == 500 then assert_total (idris_crash ("thread " ++ show i ++ " gave up"))
      else go (acc + j) (j + 1)

threads : Int -> IO ()
threads bad = do
  ch <- makeChannel
  for_ [0 .. 99] $ \i => fork $ do
    r <- catchCrash (pure (work bad i 0))
    channelPut ch (i, r)
  results <- for [0 .. 99] (\_ => channelGet ch)
  let sorted = sortBy (\(a, _), (b, _) => compare a b) results
  let ok = all (\(i, r) => case r of
                             Right s => i /= bad && s == (1000 * (i + 1)) * (1000 * (i + 1) + 1) `div` 2
                             Left c => i == bad && c.message == "thread " ++ show i ++ " gave up")
               sorted
  putStrLn ("100 threads, results right: " ++ show ok)
  putStrLn ("crashed: " ++ show (map fst (filter (isLeft . snd) sorted)))
  where
    isLeft : Either a b -> Bool
    isLeft (Left _) = True
    isLeft _ = False

mutexHeld : IO ()
mutexHeld = do
  m <- makeMutex
  got <- newIORef False
  r <- catchCrash {a = ()} (do mutexAcquire m; assert_total (idris_crash "with the lock"))
  putStrLn ("crashed: " ++ either (.message) (const "no") r)
  t <- fork (do mutexAcquire m; writeIORef got True; mutexRelease m)
  usleep 100000
  putStrLn ("the other thread got the mutex: " ++ show !(readIORef got))
  -- the thread that ran the boundary holds it, and may release it
  mutexRelease m
  threadWait t
  putStrLn ("after the release: " ++ show !(readIORef got))

flag : IORef Bool
flag = unsafePerformIO (newIORef True)

-- A constant whose first evaluation crashes.
%noinline
answer : Int
answer = unsafePerformIO $ do
  b <- readIORef flag
  if b then assert_total (idris_crash "not yet") else pure 42

constants : IO ()
constants = do
  r <- catchCrash (pure answer)
  putStrLn ("first: " ++ either (.message) show r)
  writeIORef flag False
  ch <- makeChannel
  _ <- fork (channelPut ch answer)
  putStrLn ("in another thread: " ++ show !(channelGet ch))

main : IO ()
main = do
  args <- getArgs
  case drop 1 args of
    [] => do
      threads 37
      mutexHeld
      constants
      putStrLn ("crashes caught: " ++ show !crashesCaught)
    ["other thread"] => do
      -- the crash of the forked thread is not in the boundary
      _ <- catchCrash $ do
        t <- fork (putStrLn (show (work 0 0 0)))
        threadWait t
      putStrLn "not reached"
    _ => putStrLn "?"
