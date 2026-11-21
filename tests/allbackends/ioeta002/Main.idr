module Main

import Data.IORef

-- A function in IO whose body is a cheap let before the lambda of the world
-- (`f x = let y = x + 1 in do ...`) took no world before it was given it
-- (see Compiler.Opts.EtaIO): an application of it that lacks the world, `f
-- (expensive r x)`, was a full one, and an action made by it computed its
-- arguments once, however often it is run.  `expensive` counts how many
-- times it is computed.

%noinline
expensive : IORef Int -> Int -> Int
expensive r x = unsafePerformIO $ do
  modifyIORef r (+ 1)
  pure (x * 2)

%noinline
letLam : Int -> IO Int
letLam x = let y = x + 1 in do
  z <- pure y
  pure (y + z)

letLamInl : Int -> IO Int
letLamInl x = let y = x + 1 in do
  z <- pure y
  pure (y + z)

-- the let in an alternative of a case
%noinline
caseLet : Int -> IO Int
caseLet x = case x of
  0 => pure 0
  n => let y = n + 1 in do
         z <- pure y
         pure (y + z)

-- Run an action 3 times, and say how many times `expensive` was computed by
-- the runs (the action is made, by the caller, before the count is reset).
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
  run3 "letLam" r (letLam (expensive r 5))
  run3 "letLamInl" r (letLamInl (expensive r 5))
  run3 "caseLet" r (caseLet (expensive r 5))
  writeIORef r 0
  let acts = [letLam (expensive r 1), caseLet (expensive r 2)]
  xs <- traverse id (acts ++ acts ++ acts)
  n <- readIORef r
  putStrLn "list: \{show xs}, computed \{show n} times"
