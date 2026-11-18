module Main

import Data.IOArray
import Data.List
import Data.Maybe
import Data.String
import System
import System.Concurrency

-- Copies to and from arrays that other threads can see (in RefC they are
-- shared, and their elements are taken and put under their locks), and
-- copies within one array whose ranges overlap, of more elements than fit
-- in the buffer on the stack.

strs : Int -> Int -> IO (IOArray String)
strs from n = fromList [Just ("s" ++ show (from + i)) | i <- [0 .. n - 1]]

showArr : IOArray String -> IO String
showArr arr = do xs <- toList arr
                 pure (unwords (map (fromMaybe "_") xs))

copyLoop : IOArray String -> IOArray String -> Int -> IO ()
copyLoop src dst 0 = pure ()
copyLoop src dst k = do
  _ <- copyArrayRange src 0 dst 0 (max src)
  _ <- copyArrayRange dst 1 dst 0 (max dst - 1)
  copyLoop src dst (k - 1)

main : IO ()
main = do
  a <- strs 0 40
  b <- strs 100 40
  -- two threads copy between the same arrays, in both directions
  t <- fork (copyLoop a b 200)
  copyLoop b a 200
  threadWait t
  -- the arrays hold only strings that were in them
  xs <- toList a
  ys <- toList b
  let ok = all (\x => maybe False (isPrefixOf "s") x) (xs ++ ys)
  printLn ok
  -- overlapping copies of 30 elements, in both directions
  c <- strs 0 40
  _ <- copyArrayRange c 0 c 5 30
  putStrLn !(showArr c)
  d <- strs 0 40
  _ <- copyArrayRange d 5 d 0 30
  putStrLn !(showArr d)
