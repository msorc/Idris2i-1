module Chains

-- Chains of closures as long as a list, which the browser backend ran on a
-- JavaScript stack as deep as the list: traverse and friends in State, and
-- chains of *> in IO and in State.  They are transformed to loops.

import Control.Monad.State
import Data.IORef
import Data.List

%default covering

n : Int
n = 100000

count : Int -> State Int Int
count x = do modify (+1); pure (x * 2)

tick : Int -> State Int ()
tick x = modify (+ x)

main : IO ()
main = do
  let xs = [1 .. n]
  -- traverse, for and sequence in State, the type written as `State` and as
  -- `StateT`, the result taken apart by a `let` and by `runState`
  let (k, ys) = runState 0 (traverse count xs)
  putStrLn ("traverse: " ++ show k ++ " " ++ show (sum ys) ++ " " ++ show (take 3 ys))
  let (k, ys) = runState 0 (for xs count)
  putStrLn ("for: " ++ show k ++ " " ++ show (sum ys))
  let r = runState 10 (sequence (map count xs))
  putStrLn ("sequence: " ++ show (fst r) ++ " " ++ show (sum (snd r)))
  let t : StateT Int Identity (List Int) = traverse count xs
  printLn (fst (runState 0 t))
  -- traverse_, for_, sequence_ and a chain of *> in State
  putStrLn ("traverse_: " ++ show (execState 0 (traverse_ tick xs)))
  putStrLn ("for_: " ++ show (execState 0 (for_ xs tick)))
  putStrLn ("sequence_: " ++ show (execState 0 (sequence_ (map tick xs))))
  putStrLn ("*> State: " ++ show (execState 0 (foldr (*>) (pure ()) (map tick xs))))
  -- the order of the effects
  putStrLn ("order: " ++ show (execState (the (List Int) []) (traverse_ (\x => modify (x ::)) [1, 2, 3])))
  putStrLn ("order: " ++ show (runState "" (traverse (\c => do modify (++ c); gets String.length) ["a", "bb", "c"])))
  -- a chain of *> in IO
  ref <- newIORef (the Int 0)
  foldr (*>) (pure ()) (map (\i => modifyIORef ref (+ i)) xs)
  putStrLn ("*> IO: " ++ show !(readIORef ref))
  ignore (foldr (*>) (pure 7) [putStr "a ", putStr "b "] >>= \v => putStrLn (show v))
