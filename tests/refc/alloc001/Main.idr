-- Values of many sizes made and freed in turns, in one thread and in
-- several at once (on four workers: the generated code finds the worker of
-- its OS thread, see idris2i_1_worker), with the leak check, which must
-- find every value freed, and the census of the pages at exit.
import Data.List
import System
import System.Concurrency

data Cell = C1 Int | C3 Int Int Int | C7 Int Int Int Int Int Int Int
          | C20 Int Int Int Int Int Int Int Int Int Int
                Int Int Int Int Int Int Int Int Int Int
          | C40 Int Int Int Int Int Int Int Int Int Int
                Int Int Int Int Int Int Int Int Int Int
                Int Int Int Int Int Int Int Int Int Int
                Int Int Int Int Int Int Int Int Int Int

mkCell : Int -> Cell
mkCell n = case n `mod` 5 of
  0 => C1 n
  1 => C3 n n n
  2 => C7 n n n n n n n
  3 => C20 n n n n n n n n n n n n n n n n n n n n
  _ => C40 n n n n n n n n n n n n n n n n n n n n
           n n n n n n n n n n n n n n n n n n n n

weight : Cell -> Int
weight (C1 a) = a
weight (C3 a _ c) = a + c
weight (C7 a _ _ _ _ _ g) = a + g
weight (C20 a _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ t) = a + t
weight (C40 a _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _
            _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ z) = a + z

-- A closure and a Double per element too.
step : Int -> List (Cell, Int -> Int, Double)
step k = map (\i => (mkCell i, \x => x + i, cast i / 2)) [k .. k + 999]

score : List (Cell, Int -> Int, Double) -> Double
score = foldl (\acc, (c, f, d) => acc + cast (weight c + f 1) + d) 0

-- Keep every other batch alive until the end, free the others at once.
rounds : Int -> List (List (Cell, Int -> Int, Double)) -> Double -> Double
rounds 0 kept acc = acc + sum (map score kept)
rounds n kept acc =
  let b = step n in
  if n `mod` 2 == 0 then rounds (n - 1) (b :: kept) acc
                    else rounds (n - 1) kept (acc + score b)

main : IO ()
main = do
  args <- getArgs
  let n = 200 + cast (length args)
  printLn (rounds n [] 0)
  -- made here, used and dropped in other threads at the same time
  let shared = step n
  t1 <- fork $ printLn (score shared)
  t2 <- fork $ printLn (score (reverse shared))
  threadWait t1
  threadWait t2
  printLn (score shared)
