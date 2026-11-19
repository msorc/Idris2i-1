module Main

import Data.IORef

-- Functions in IO whose bodies give an action without a bind first (a case
-- of `pure` and a tail call, a let before the action, a where helper, IO (),
-- PrimIO) are given the world as a parameter (see Compiler.Opts.EtaIO): their
-- workers (see `Worker` in Compiler.RefC.RefC) give the result of the action
-- as a C integer, and the loops that call them make no value.

loopIf : Int64 -> Int64 -> IO Int64
loopIf acc n = if n == 0 then pure acc else loopIf (acc + n) (n - 1)

loopCase : Int64 -> Int64 -> IO Int64
loopCase acc n = case n of
  0 => pure acc
  _ => loopCase (acc + n) (n - 1)

loopLet : Int64 -> Int64 -> IO Int64
loopLet acc n = let acc' = acc + n in if n == 0 then pure acc else loopLet acc' (n - 1)

sumWhere : Int64 -> IO Int64
sumWhere n = go 0 n
  where
    go : Int64 -> Int64 -> IO Int64
    go acc 0 = pure acc
    go acc k = go (acc + k) (k - 1)

countUnit : Bits32 -> IO ()
countUnit 0 = pure ()
countUnit n = countUnit (n - 1)

loopPrim : Bits64 -> Bits64 -> PrimIO Bits64
loopPrim acc n = if n == 0 then \w => MkIORes acc w else loopPrim (acc * 3 + n) (n - 1)

-- a step that is not a loop, called by a loop at every step
step : Int64 -> Int64 -> IO Int64
step acc n = if n `mod` 3 == 0 then pure (acc + 1) else pure (acc + n)

stepTail : Int64 -> Int64 -> IO Int64
stepTail acc n = if n > 100 then step acc n else step (acc * 2) n

drive : Int64 -> Int64 -> IO Int64
drive acc 0 = pure acc
drive acc n = do
  acc' <- stepTail acc n
  drive (acc' `mod` 1000000007) (n - 1)

main : IO ()
main = do
  printLn !(loopIf 0 1000000)
  printLn !(loopCase 0 1000000)
  printLn !(loopLet 0 1000000)
  printLn !(sumWhere 1000000)
  countUnit 1000000
  printLn !(primIO (loopPrim 1 1000))
  printLn !(drive 0 1000000)
  -- as actions, made once and run twice
  let act = loopIf 0 10
  printLn !act
  printLn !act
  r <- newIORef (the Int64 0)
  let acts = [loopCase 1 2, loopLet 3 4, stepTail 5 6]
  traverse_ (\a => do v <- a; modifyIORef r (+ v)) (acts ++ acts)
  printLn !(readIORef r)
