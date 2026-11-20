||| Arrays whose elements are laid out inline by the RefC back end (see
||| Data.IOArray.Flat, `newFlatArray`): of primitives, of records of raw
||| fields, with empty slots, written and read inline (`readFlatArray`,
||| `writeFlatArray`) and by the other functions (`readArray`, `toList`, code
||| that is generic in the elements), copied between arrays of either layout,
||| and the linear arrays as before.  The other back ends ignore the layouts:
||| every back end prints the same.
module Main

import Data.IOArray
import Data.Linear.Array
import Data.String

record P where
  constructor MkP
  x : Double
  y : Double
  n : Int

Show P where
  -- (as integers: the back ends show Doubles differently)
  show p = "P \{show (cast {to = Int} (p.x * 4.0))} \{show (cast {to = Int} (p.y * 4.0))} \{show p.n}"

-- generic in the elements: the arrays it makes have the layout of values,
-- and it reads and writes any array with that layout
genericFill : Int -> (Int -> e) -> IO (IOArray e)
genericFill k f = do
  a <- newArray k
  for_ [0 .. k - 1] $ \i => ignore (writeArray a i (f i))
  pure a

genericRead : IOArray e -> IO (List (Maybe e))
genericRead = toList

genericSwap : IOArray e -> Int -> Int -> IO ()
genericSwap a i j = do
  Just x <- readArray a i | Nothing => pure ()
  Just y <- readArray a j | Nothing => pure ()
  ignore (writeArray a i y)
  ignore (writeArray a j x)

sumP : List (Maybe P) -> Double
sumP = foldl (\s, m => maybe s (\p => s + p.x + p.y + cast p.n) m) 0.0

-- through the linear arrays
sweep : Int -> Int -> (1 _ : LinArray P) -> LinArray P
sweep k i a =
  if i >= k then a else
    let (mp # a) = mread a i in
    case mp of
      Nothing => sweep k (i + 1) a
      Just p => let (_ # a) = write a i ({ x $= (* 2.0), n $= (+ 1) } p) in sweep k (i + 1) a

fillLin : Int -> Int -> (1 _ : LinArray P) -> LinArray P
fillLin k i a =
  if i >= k then a else
    let (_ # a) = write a i (MkP (cast i) (cast i / 2.0) i) in fillLin k (i + 2) a

checksum : Int -> IArray P -> Double
checksum k a = go 0 0.0
  where
    go : Int -> Double -> Double
    go i s = if i >= k then s else go (i + 1) (maybe s (\p => s + p.x + p.y + cast p.n) (read a i))

main : IO ()
main = do
  -- primitives, with an empty slot
  ds <- newFlatArray {elem = Double} 4
  ignore (writeFlatArray ds 0 1.5)
  ignore (writeFlatArray ds 2 (-0.25))
  printLn !(toList ds)
  is <- newFlatArray {elem = Int} 3
  ignore (writeFlatArray is 0 900000000)
  ignore (writeFlatArray is 2 (-3))
  printLn !(toList is)
  bs <- newFlatArray {elem = Bits8} 6
  for_ [0 .. 5] $ \i => ignore (writeFlatArray bs i (cast i))
  printLn !(toList bs)
  cs <- newFlatArray {elem = Char} 4
  for_ [0 .. 3] $ \i => ignore (writeFlatArray cs i (assert_total (strIndex "flat" i)))
  printLn [!(readFlatArray cs 0), !(readArray cs 1), !(readFlatArray cs 3)]
  -- records, written by code that knows the type, read by generic code
  ps <- newFlatArray {elem = P} 5
  for_ [0 .. 4] $ \i => when (i /= 3) $ ignore (writeFlatArray ps i (MkP (cast i) (cast i * 0.5) (i * 10)))
  printLn !(genericRead ps)
  genericSwap ps 0 4
  printLn !(toList ps)
  -- made by generic code (the layout of values), read by code that knows
  -- the type
  gs <- genericFill 3 (\i => MkP (cast i) 1.0 i)
  printLn (cast {to = Int} (sumP !(toList gs)))
  printLn !(readFlatArray gs 1)
  ignore (writeFlatArray gs 2 (MkP 0.5 0.5 5))
  printLn !(toList gs)
  -- copies between arrays of either layout
  cp <- newArrayCopy 6 ps
  printLn !(toList cp)
  ok <- copyArrayRange gs 0 ps 1 3
  printLn (ok, !(toList ps))
  ok <- copyArrayRange ps 0 ps 1 3   -- overlapping
  printLn (ok, !(toList ps))
  -- out of bounds
  printLn (!(writeFlatArray ps 9 (MkP 0 0 0)), !(readFlatArray ps (-1)))
  -- linear arrays: thaw, copyInto
  let r = Array.newArray 10 (\a => toIArray (sweep 10 0 (fillLin 10 0 a)) (\ia =>
            (checksum 10 ia, thaw ia 12 (\b => toIArray (sweep 12 0 b) (checksum 12)))))
  printLn (bimap (cast {to = Int}) (cast {to = Int}) r)
