module Main

import Data.List
import System.Concurrency

-- Borrows its list.
sumL : List Int -> Int
sumL [] = 0
sumL (x :: xs) = x + sumL xs

-- Calls in tail position that pass a borrowed list on: they must stay tail
-- calls (the loops run in a thread with a stack of 8MB).
mutual
  ping : List Int -> Int -> Int -> Int
  ping xs 0 acc = acc
  ping xs n acc = pong xs (n - 1) (acc + sumL xs)

  pong : List Int -> Int -> Int -> Int
  pong xs n acc = ping xs n acc

-- A loop of its own, which passes the fields of a borrowed list on.
walk : List Int -> List Int -> Int -> Int
walk orig [] acc = if acc > 5000000 then acc else walk orig orig acc
walk orig (x :: xs) acc = walk orig xs (acc + x)

-- An IO loop.
countdown : List Int -> Int -> IO ()
countdown xs 0 = putStrLn "done"
countdown xs n = do
  if n `mod` 1000000 == 0 then printLn (sumL xs) else pure ()
  countdown xs (n - 1)

-- A loop with a value that is built at each step: it is owned, and passed
-- to a parameter that cannot be borrowed then.
build : List Int -> Int -> List Int
build acc 0 = acc
build acc n = build (n :: List.take 3 acc) (n - 1)

main : IO ()
main = do
  let xs = [1 .. 10]
  t <- fork $ do
    pure ()
    printLn (ping xs 2000000 0)
    printLn (walk xs xs 0)
    countdown xs 3000000
    printLn (build [] 3000000)
  threadWait t
