module Signals

import Data.Fuel
import Data.List
import System
import System.Signal

-- System.Signal on Node: signals that the program raises itself are handled
-- at once, as with `raise` in C; signals from other processes reach `main`
-- when it runs in its worker thread (the main thread receives them).

check : String -> IO (Either SignalError ()) -> IO ()
check what act = do
  Right () <- act
    | Left (Error e) => putStrLn "\{what} failed: \{show e}"
  pure ()

-- Waits for a collected signal, up to about 5 seconds.
wait : Nat -> IO (Maybe Signal)
wait 0 = pure Nothing
wait (S k) = do
  Nothing <- handleNextCollectedSignal
    | Just s => pure (Just s)
  usleep 10000
  wait k

self : IO ()
self = do
  check "ignore" (ignoreSignal SigABRT)
  check "raise ignored" (raiseSignal SigABRT)
  putStrLn "survived an ignored SIGABRT"
  check "collect" (collectSignal SigABRT)
  check "collect" (collectSignal SigILL)
  printLn (signalCode SigABRT > 0, toSignal (signalCode SigILL) == Just SigILL)
  printLn (!handleNextCollectedSignal == Nothing)
  ignore $ sequence (replicate 3 (raiseSignal SigABRT))
  ignore $ sequence (replicate 3 (raiseSignal SigILL))
  pid <- getPID
  check "send" (sendSignal SigABRT pid)
  sigs <- handleManyCollectedSignals (limit 4)
  printLn (sigs == [SigILL, SigABRT])
  printLn (!handleNextCollectedSignal == Nothing)
  check "default" (defaultSignal SigABRT)
  check "default" (defaultSignal SigILL)

others : IO ()
others = do
  check "collect" (collectSignal (SigPosix SigUser1))
  check "ignore" (ignoreSignal SigINT)
  pid <- getPID
  0 <- system "kill -INT \{show pid}; kill -USR1 \{show pid}"
    | _ => putStrLn "kill failed"
  s <- wait 500
  putStrLn $ if s == Just (SigPosix SigUser1) then "got SIGUSR1" else "no signal"
  -- a signal cuts a sleep short
  0 <- system "(sleep 0.2; kill -USR1 \{show pid}) &"
    | _ => putStrLn "kill failed"
  t <- time
  sleep 10
  t' <- time
  putStrLn $ if t' - t < 5 then "woken up" else "slept on"
  s <- wait 500
  putStrLn $ if s == Just (SigPosix SigUser1) then "got SIGUSR1" else "no signal"

main : IO ()
main = do
  [_, what] <- getArgs
    | _ => putStrLn "usage: signals self|others"
  if what == "self" then self else others
  putStrLn "done"
