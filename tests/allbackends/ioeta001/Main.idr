module Main

import Data.IORef
import Data.List

-- A function in IO whose body gives its action without a bind first is given
-- the world as a parameter (see Compiler.Opts.EtaIO) only when what the body
-- computes before its action is cheap.  An action made once by a partial
-- application and run many times must not compute again what it computed when
-- it was made: `expensive` counts how many times it is computed.

%noinline
expensive : IORef Int -> Int -> Int
expensive r x = unsafePerformIO $ do
  modifyIORef r (+ 1)
  pure (x * 2)

-- `expensive` is inlined here (its effect is a primitive of IO)
expensiveInl : IORef Int -> Int -> Int
expensiveInl r x = unsafePerformIO $ do
  modifyIORef r (+ 1)
  pure (x * 2)

-- a let of an expensive value before the action
shareLet : IORef Int -> Int -> IO Int
shareLet r x = let y = expensive r x in pure (y + 1)

shareLetInl : IORef Int -> Int -> IO Int
shareLetInl r x = let y = expensiveInl r x in pure (y + 1)

-- an expensive scrutinee
shareCase : IORef Int -> Int -> IO Int
shareCase r x = case expensive r x of
  0 => pure 0
  n => pure (n + 1)

-- an expensive argument of a tail call that gives an action
countDown : Int -> Int -> IO Int
countDown acc 0 = pure acc
countDown acc n = countDown (acc + n) (n - 1)

shareArg : IORef Int -> Int -> IO Int
shareArg r x = countDown 0 (expensive r x)

-- the same, with a function whose body is a bind, which took the world before
-- the other functions were given it: the partial application is a lambda,
-- which computes its argument at every run (as it did before)
countDownB : Int -> Int -> IO Int
countDownB acc 0 = pure acc
countDownB acc n = do
  x <- pure n
  countDownB (acc + x) (n - 1)

shareArgB : IORef Int -> Int -> IO Int
shareArgB r x = countDownB 0 (expensive r x)

-- a callback, applied before the action
shareCallback : (Int -> IO Int) -> Int -> IO Int
shareCallback k x = if x > 0 then k x else pure 0

-- a lazy value, forced in the action
shareLazy : IORef Int -> Int -> IO Int
shareLazy r x = let y = delay (expensive r x) in if x > 0 then pure (force y) else pure 0

-- cheap: the body is given the world, and computes `acc + n` at every run
cheapLoop : Int -> Int -> IO Int
cheapLoop acc n = if n == 0 then pure acc else cheapLoop (acc + n) (n - 1)

-- where helper and a let of cheap values
cheapWhere : Int -> IO Int
cheapWhere n = let m = n * 2 in go 0 m
  where
    go : Int -> Int -> IO Int
    go acc 0 = pure acc
    go acc k = go (acc + k) (k - 1)

-- an action that has an effect, made once and run many times
tick : IORef Int -> Int -> IO ()
tick r k = if k > 0 then modifyIORef r (+ k) else pure ()

-- PrimIO, with the world after a case
primCount : Int -> Int -> PrimIO Int
primCount acc n = if n == 0 then \w => MkIORes acc w else primCount (acc + 1) (n - 1)

-- Run an action 3 times, and say how many times `expensive` was computed by
-- the runs (the action is made, by the caller, before the count is reset).
-- 0 is that the action shares what it computed when it was made.  (A case
-- whose alternatives are all lambdas, as in `shareCase`, and an argument of
-- `pure` that the inliner substitutes under its lambda, as in `shareCallback`,
-- are computed at every run: they were before functions were given the world.)
run3 : String -> IORef Int -> IO Int -> IO ()
run3 name r act = do
  writeIORef r 0
  a <- act
  b <- act
  c <- act
  n <- readIORef r
  putStrLn "\{name}: \{show [a, b, c]}, computed \{show n} times"

main : IO ()
main = do
  r <- newIORef 0
  run3 "shareLet" r (shareLet r 5)
  run3 "shareLetInl" r (shareLetInl r 5)
  run3 "shareCase" r (shareCase r 5)
  run3 "shareArg" r (shareArg r 5)
  run3 "shareArgB" r (shareArgB r 5)
  run3 "shareCallback" r (shareCallback (\x => pure (expensive r x)) 5)
  run3 "shareCallback'" r (shareCallback (let y = expensive r 5 in \x => pure (x + y)) 5)
  run3 "shareLazy" r (shareLazy r 5)
  run3 "cheapLoop" r (cheapLoop 0 (expensive r 4))
  run3 "cheapWhere" r (cheapWhere (expensive r 3))
  -- actions in a data structure, run many times
  writeIORef r 0
  let acts = [shareLet r 1, shareLet r 2, shareCase r 3, shareArg r 4]
  xs <- traverse id (acts ++ acts ++ acts)
  n <- readIORef r
  putStrLn "list: \{show xs}, computed \{show n} times"
  -- an action with an effect, made once
  t <- newIORef 0
  let tk = tick t 3
  tk; tk; tk
  printLn !(readIORef t)
  ys <- traverse (\k => do tick t k; readIORef t) [1, 2, 3]
  printLn ys
  -- PrimIO
  printLn !(primIO (primCount 0 1000))
  let pc = primCount 0 10
  printLn !(primIO pc)
  printLn !(primIO pc)
  -- unsafePerformIO of an action given the world
  printLn (unsafePerformIO (cheapLoop 0 100))
  printLn (unsafePerformIO (shareLet r 7))
