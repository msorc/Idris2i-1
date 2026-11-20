-- W2: a binary heap of records, with insert/delete churn.
--
-- A discrete event simulation: a priority queue (a binary min-heap on the
-- time) of n events, kept in a linear array (Data.Linear.Array).  Each step
-- takes the earliest event out and puts in its next occurrence, a new
-- record, at a later time.  Every step allocates a record, drops one, and
-- moves about log2 n records along a path of the heap.
--
-- This copy uses the flat linear arrays (Data.Linear.Array.Flat): the
-- import, the types FlatArray and FlatIArray, and newFlatArray are all that
-- changes.
--
-- Input: the number of steps.
module Main

import Data.Linear.Array.Flat
import Data.String

record Event where
  constructor MkEvent
  time : Int
  ident : Int
  gen : Int

put : (1 _ : FlatArray Event) -> Int -> Event -> FlatArray Event
put a i e = let (_ # a) = write a i e in a

-- Put e at position i of a heap of n events, or further down.
siftDown : Int -> Int -> Event -> (1 _ : FlatArray Event) -> FlatArray Event
siftDown n i e a =
  let l = 2 * i + 1 in
  if l >= n then put a i e else
    let (ml # a) = mread a l
        (mr # a) = mread a (l + 1)
    in case ml of
         Nothing => put a i e
         Just cl => case mr of
           Just cr => if l + 1 < n && cr.time < cl.time
                         then descend (l + 1) cr a
                         else descend l cl a
           Nothing => descend l cl a
  where
    -- Move the smaller child c (ce) up to i if it is earlier than e.
    descend : Int -> Event -> (1 _ : FlatArray Event) -> FlatArray Event
    descend c ce a = if ce.time < e.time
                        then siftDown n c e (put a i ce)
                        else put a i e

-- Put e at position i of a heap, or further up.
siftUp : Int -> Event -> (1 _ : FlatArray Event) -> FlatArray Event
siftUp i e a =
  if i <= 0 then put a 0 e else
    let p = (i - 1) `div` 2
        (mp # a) = mread a p
    in case mp of
         Nothing => put a i e
         Just pe => if e.time < pe.time
                       then siftUp p e (put a i pe)
                       else put a i e

-- Take the earliest event out of a heap of n events.
pop : Int -> (1 _ : FlatArray Event) -> Res (Maybe Event) (const (FlatArray Event))
pop n a =
  let (mt # a) = mread a 0
      (ml # a) = mread a (n - 1)
  in case mt of
       Nothing => Nothing # a
       Just top => case ml of
         Nothing => Nothing # a
         Just lst => Just top # siftDown (n - 1) 0 lst a

-- The time until the next occurrence of an event.
delay : Int -> Int -> Int
delay ident gen = (ident * 7919 + gen * 104729) `mod` 1000 + 1

-- k steps on a heap of n events; the result is the sum of the times of the
-- events taken out.
simulate : Int -> Int -> Int -> (1 _ : FlatArray Event) -> Res Int (const (FlatArray Event))
simulate n k acc a =
  if k <= 0 then acc # a else
    let (mt # a) = pop n a in
    case mt of
      Nothing => acc # a
      Just e =>
        let a = siftUp (n - 1) (MkEvent (e.time + delay e.ident e.gen) e.ident (e.gen + 1)) a
        in simulate n (k - 1) (acc + e.time) a

-- Insert the events 0 to n - 1 one after the other.
build : Int -> Int -> (1 _ : FlatArray Event) -> FlatArray Event
build n i a =
  if i >= n then a else
    build n (i + 1) (siftUp i (MkEvent ((i * 7919) `mod` 100000) i 0) a)

-- The sum of the generations, and the earliest time.
summary : Int -> FlatIArray Event -> (Int, Int)
summary n a = go 0 0
  where
    go : Int -> Int -> (Int, Int)
    go i g =
      if i >= n then (g, maybe (-1) time (read a 0)) else
        case read a i of
          Nothing => go (i + 1) g
          Just e => go (i + 1) (g + e.gen)

main : IO ()
main = do
  line <- getLine
  let k = cast {to = Int} (trim line)
  let n = 131072
  let (s, g, t) = newFlatArray n (\a =>
                    let (s # a) = simulate n k 0 (build n 0 a) in
                    toIArray a (\r => let (g, t) = summary n r in (s, g, t)))
  putStrLn "\{show s} \{show g} \{show t}"
