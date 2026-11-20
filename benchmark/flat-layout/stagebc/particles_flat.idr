-- W1: records in a mutable array.
--
-- An array of particles (four Double fields and an Int), updated in place
-- over many passes.  Each update reads the particle and its right
-- neighbour, so a pass sees the left neighbour already updated (a
-- Gauss-Seidel sweep).  The array is a linear array (Data.Linear.Array).
--
-- This copy uses the flat linear arrays (Data.Linear.Array.Flat): the
-- import, the types FlatArray and FlatIArray, and newFlatArray are all that
-- changes.
--
-- Input: the number of passes.
module Main

import Data.Linear.Array.Flat
import Data.String

record Particle where
  constructor MkParticle
  px : Double
  py : Double
  vx : Double
  vy : Double
  hits : Int

-- Keep a particle in the box [0, 1000] x [0, 1000], bouncing off the walls.
bounce : Particle -> Particle
bounce p =
  let p = if p.px < 0.0 then { px := - p.px, vx := - p.vx, hits $= (+1) } p
          else if p.px > 1000.0 then { px := 2000.0 - p.px, vx := - p.vx, hits $= (+1) } p
          else p
  in if p.py < 0.0 then { py := - p.py, vy := - p.vy, hits $= (+1) } p
     else if p.py > 1000.0 then { py := 2000.0 - p.py, vy := - p.vy, hits $= (+1) } p
     else p

-- One particle, pulled towards its neighbour and down.
move : Particle -> Particle -> Particle
move p q =
  let vx' = (p.vx + (q.px - p.px) * 0.01) * 0.999
      vy' = (p.vy + (q.py - p.py) * 0.01 - 0.05) * 0.999
  in bounce (MkParticle (p.px + vx') (p.py + vy') vx' vy' p.hits)

-- The index after i, in an array of n elements, going round.
next : Int -> Int -> Int
next n i = if i + 1 >= n then 0 else i + 1

sweep : Int -> Int -> (1 _ : FlatArray Particle) -> FlatArray Particle
sweep n i a =
  if i >= n then a else
    let (mp # a) = mread a i
        (mq # a) = mread a (next n i)
    in case mp of
         Nothing => sweep n (i + 1) a
         Just p => case mq of
           Nothing => sweep n (i + 1) a
           Just q => let (_ # a) = write a i (move p q) in sweep n (i + 1) a

passes : Int -> Int -> (1 _ : FlatArray Particle) -> FlatArray Particle
passes n k a = if k <= 0 then a else passes n (k - 1) (sweep n 0 a)

fill : Int -> Int -> (1 _ : FlatArray Particle) -> FlatArray Particle
fill n i a =
  if i >= n then a else
    let x = cast ((i * 7919) `mod` 1000)
        y = cast ((i * 104729) `mod` 1000)
        (_ # a) = write a i (MkParticle x y 0.0 0.0 0)
    in fill n (i + 1) a

-- The sum of the coordinates (times 1000) and the number of bounces.
checksum : Int -> FlatIArray Particle -> (Int, Int)
checksum n a = go 0 0.0 0
  where
    go : Int -> Double -> Int -> (Int, Int)
    go i s h =
      if i >= n then (cast (s * 1000.0), h) else
        case read a i of
          Nothing => go (i + 1) s h
          Just p => go (i + 1) (s + p.px + p.py) (h + p.hits)

main : IO ()
main = do
  line <- getLine
  let k = cast {to = Int} (trim line)
  let n = 100000
  let (s, h) = newFlatArray n (\a => toIArray (passes n k (fill n 0 a)) (checksum n))
  putStrLn "\{show s} \{show h}"
