||| Nightly digest of meter readings: tallies, the set of distinct readings,
||| how many fall outside the calibrated band, and a scan of the station list.
module Main

import Data.IORef
import Data.List
import Data.String
import System

-- Readings ---------------------------------------------------------------------

||| The next state of the generator that stands in for the meter feed.
next : Int -> Int
next x = (x * 1103515245 + 12345) `mod` 2147483648

reading : Int -> Int
reading x = (x `div` 8) `mod` 100000

-- Tallies ----------------------------------------------------------------------

record Tally where
  constructor MkTally
  count : IORef Int
  whole : IORef Int
  peak  : IORef Int
  odd   : IORef Int

tallies : Int -> IO (Int, Int, Int, Int)
tallies n = do
  t <- [| MkTally (newIORef 0) (newIORef 0) (newIORef 0) (newIORef 0) |]
  loop t 1 42
  loop t 1 43
  loop t 1 44
  [| (\a, b, c, d => (a, b, c, d)) (readIORef t.count) (readIORef t.whole)
       (readIORef t.peak) (readIORef t.odd) |]
  where
    loop : Tally -> Int -> Int -> IO ()
    loop t i x = if i > n then pure () else do
      let x' = next x
      let v = reading x'
      modifyIORef t.count (+ 1)
      modifyIORef t.whole (+ v)
      modifyIORef t.peak (max v)
      when (v `mod` 2 == 1) $ modifyIORef t.odd (+ 1)
      loop t (i + 1) x'

-- Distinct readings --------------------------------------------------------------

data Tree = Leaf | Node Tree Int Tree

insert : Int -> Tree -> Tree
insert x Leaf = Node Leaf x Leaf
insert x t@(Node l y r) =
  if x < y then Node (insert x l) y r
  else if x > y then Node l y (insert x r)
  else t

size : Tree -> Int
size Leaf = 0
size (Node l _ r) = size l + 1 + size r

distinct : Int -> Int
distinct n = size (loop Leaf 1 7)
  where
    loop : Tree -> Int -> Int -> Tree
    loop t i x = if i > n then t else
      let x' = next x in loop (insert (reading x') t) (i + 1) x'

-- The calibrated band ------------------------------------------------------------

||| The band of normal readings. It comes from a table of reference samples and
||| is worked out when it is first needed.
record Band where
  constructor MkBand
  low  : Lazy Int
  high : Lazy Int

samples : Int -> List Int
samples seed = go 5 seed []
  where
    go : Nat -> Int -> List Int -> List Int
    go Z _ acc = acc
    go (S k) x acc = let x' = next x in go k x' (reading x' :: acc)

percentile : Int -> List Int -> Int
percentile p xs =
  case drop (cast (cast (length xs) * p `div` 100)) (sort xs) of
    (v :: _) => v
    [] => 0

calibrate : Int -> Band
calibrate seed =
  let table = samples seed in
  MkBand (percentile 10 table) (percentile 90 table)

outside : Band -> Int -> Int
outside band n = loop 0 1 99
  where
    loop : Int -> Int -> Int -> Int
    loop acc i x = if i > n then acc else
      let x' = next x
          v = reading x'
      in if v < band.low || v > band.high
           then loop (acc + 1) (i + 1) x'
           else loop acc (i + 1) x'

-- Station list -------------------------------------------------------------------

stationNames : List String
stationNames = ["Aarau", "Basel", "Chur", "Davos", "Genf", "Zürich", "Luzern", "Thun"]

||| The station list as it arrives: names separated by semicolons.
stationList : Int -> String
stationList n = joinBy ";" (map name [1 .. n `div` 125])
  where
    name : Int -> String
    name i = case drop (cast (i `mod` 8)) stationNames of
      (s :: _) => s ++ show (i `mod` 97)
      [] => "?"

||| Number of fields and a checksum of the characters, read one at a time.
partial
scan : String -> (Int, Int)
scan s = loop 0 1 0
  where
    len : Int
    len = strLength s

    partial
    loop : Int -> Int -> Int -> (Int, Int)
    loop i fields acc =
      if i >= len then (fields, acc) else
        let c = strIndex s i in
        if c == ';' then loop (i + 1) (fields + 1) acc
        else loop (i + 1) fields ((acc * 31 + ord c) `mod` 1000003)

-- Main ---------------------------------------------------------------------------

partial
main : IO ()
main = do
  [_, arg] <- getArgs
    | _ => die "usage: meter READINGS"
  let Just n = parsePositive {a = Int} arg
    | Nothing => die "usage: meter READINGS"
  (count, whole, peak, odd) <- tallies n
  putStrLn "readings \{show count} total \{show whole} peak \{show peak} odd \{show odd}"
  putStrLn "distinct \{show (distinct n)}"
  let band = calibrate 5
  putStrLn "band \{show band.low}..\{show band.high} outside \{show (outside band n)}"
  let (fields, check) = scan (stationList n)
  putStrLn "stations \{show fields} checksum \{show check}"
