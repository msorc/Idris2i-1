module Main

import Data.List
import Data.Vect
import System.Concurrency
import System.Random

draws : Nat -> IO a -> IO (List a)
draws Z _ = pure []
draws (S k) act = do x <- act
                     xs <- draws k act
                     pure (x :: xs)

int32s : Nat -> (Int32, Int32) -> IO (List Int32)
int32s n range = draws n (randomRIO range)

doubles : Nat -> IO (List Double)
doubles n = draws n randomIO

-- Draw numbers in a thread, and say whether they were all in their range.
worker : Channel Bool -> IO ()
worker ch = do
  xs <- int32s 2000 (10, 19)
  ds <- doubles 2000
  channelPut ch (all (\x => x >= 10 && x <= 19) xs
                   && all (\d => d >= 0 && d < 1) ds)

main : IO ()
main = do
  -- Without a seed: the numbers differ from run to run, their ranges do not.
  xs <- int32s 1000 (-3, 3)
  putStrLn $ "in [-3, 3]: " ++ show (all (\x => x >= -3 && x <= 3) xs)
  putStrLn $ "every value drawn: " ++ show (sort (nub xs))
  ds <- doubles 1000
  putStrLn $ "in [0, 1): " ++ show (all (\d => d >= 0 && d < 1) ds)
  ds <- draws 1000 (randomRIO (the Double 2.5, 4.5))
  putStrLn $ "in [2.5, 4.5]: " ++ show (all (\d => d >= 2.5 && d <= 4.5) ds)
  one <- int32s 10 (7, 7)
  putStrLn $ "in [7, 7]: " ++ show one

  -- The same seed gives the same numbers.
  srand 42
  a <- int32s 20 (1, 100)
  da <- doubles 20
  srand 42
  b <- int32s 20 (1, 100)
  db <- doubles 20
  srand 43
  c <- int32s 20 (1, 100)
  putStrLn $ "seed 42: " ++ show (take 8 a)
  putStrLn $ "same seed, same Int32s: " ++ show (a == b)
  putStrLn $ "same seed, same Doubles: " ++ show (da == db)
  putStrLn $ "other seed, other Int32s: " ++ show (a /= c)

  -- A seed that does not fit in 32 bits, and the seed 0.
  srand 0xFFFFFFFFFFFFFFFF
  a <- int32s 5 (0, 999)
  srand 0xFFFFFFFF
  b <- int32s 5 (0, 999)
  srand 0
  c <- int32s 5 (0, 999)
  putStrLn $ "big seeds: " ++ show a ++ " " ++ show b ++ " " ++ show c

  -- The whole of Int32: the range does not fit in 32 bits.
  srand 1
  ws <- int32s 1000 (-2147483648, 2147483647)
  putStrLn $ "whole range, both signs: "
          ++ show (any (< 0) ws && any (> 0) ws)
  putStrLn $ "whole range, big values: "
          ++ show (any (\x => x > 0x40000000 || x < -0x40000000) ws)
  ws <- draws 1000 (the (IO Int32) randomIO)
  putStrLn $ "randomIO, both signs: " ++ show (any (< 0) ws && any (> 0) ws)
  ws <- int32s 1000 (2147483646, 2147483647)
  putStrLn $ "top of the range: " ++ show (sort (nub ws) == [2147483646, 2147483647])

  -- The functions built on them.
  srand 7
  fs <- draws 200 (rndFin 3)
  putStrLn $ "rndFin 3: " ++ show (sort (nub (map finToNat fs)))
  ss <- draws 200 (rndSelect ["a", "b", "c"])
  putStrLn $ "rndSelect: " ++ show (sort (nub ss))
  vs <- draws 200 (rndSelect' (the (Vect 2 Char) ['x', 'y']))
  putStrLn $ "rndSelect': " ++ show (sort (nub vs))

  -- The generator is shared by the threads of the program.
  ch <- makeChannel
  ts <- for [1 .. 8] $ \_ => fork (worker ch)
  oks <- for ts $ \_ => channelGet ch
  for_ ts (\t => threadWait t)
  putStrLn $ "in threads: " ++ show (and (map delay oks))
