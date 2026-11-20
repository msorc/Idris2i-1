||| The accesses of flat arrays that the RefC back end keeps out of values
||| (Compiler.RefC.FlatOpt, with `--directive refc-flat-arrays`): reads as
||| the presence and the fields of the element, writes from the fields, in
||| loops on linear arrays (Data.Linear.Array.Flat) of records of raw fields
||| and of primitives; empty slots, indices out of bounds, code generic in
||| the elements, closures, and arrays whose layout is not the one expected
||| (read through values).  Every back end prints the same.
module Main

import Data.IOArray
import Data.Linear.Array.Flat
import Data.String

record P where
  constructor MkP
  x : Double
  v : Double
  n : Int

-- (as integers: the back ends show Doubles differently)
showP : P -> String
showP p = "P \{show (cast {to = Int} (p.x * 4.0))} \{show (cast {to = Int} (p.v * 4.0))} \{show p.n}"

step : P -> P -> P
step p q = let v' = (p.v + (q.x - p.x) * 0.25) * 0.5
               x' = p.x + v'
           in MkP (if x' > 100.0 then 100.0 else x') v' (p.n + 1)

-- a sweep reading two elements and writing one (an empty slot is left
-- alone, the index k is out of bounds for the last one)
sweep : Int -> Int -> (1 _ : FlatArray P) -> FlatArray P
sweep k i a =
  if i >= k then a else
    let (mp # a) = mread a i
        (mq # a) = mread a (i + 1)
    in case mp of
         Nothing => sweep k (i + 1) a
         Just p => case mq of
           Nothing => let (_ # a) = write a i ({ n $= (+ 100) } p) in sweep k (i + 1) a
           Just q => let (_ # a) = write a i (step p q) in sweep k (i + 1) a

-- of Doubles and of Ints
scale : Int -> Int -> (1 _ : FlatArray Double) -> FlatArray Double
scale k i a =
  if i >= k then a else
    let (md # a) = mread a i in
    case md of
      Nothing => scale k (i + 1) a
      Just d => let (_ # a) = write a i (d * 1.5 + 0.25) in scale k (i + 1) a

countUp : Int -> Int -> Int -> (1 _ : FlatArray Int) -> Res Int (const (FlatArray Int))
countUp k i acc a =
  if i >= k then acc # a else
    let (mi # a) = mread a i in
    case mi of
      Nothing => countUp k (i + 1) acc a
      Just m => let (_ # a) = write a i (m * 3) in countUp k (i + 1) (acc + m) a

-- generic in the elements, and through a closure
mapAll : Flat t => (t -> t) -> Int -> Int -> (1 _ : FlatArray t) -> FlatArray t
mapAll f k i a =
  if i >= k then a else
    let (mx # a) = mread a i in
    case mx of
      Nothing => mapAll f k (i + 1) a
      Just x => let (_ # a) = write a i (f x) in mapAll f k (i + 1) a

fillP : Int -> Int -> (1 _ : FlatArray P) -> FlatArray P
fillP k i a =
  if i >= k then a else
    -- (slot 3 stays empty)
    if i == 3 then fillP k (i + 1) a else
      let (_ # a) = write a i (MkP (cast (i * 7 `mod` 11)) (cast i / 4.0) i) in
          fillP k (i + 1) a

fillD : Int -> Int -> (1 _ : FlatArray Double) -> FlatArray Double
fillD k i a = if i >= k then a else
                let (_ # a) = write a i (cast i) in fillD k (i + 1) a

fillI : Int -> Int -> (1 _ : FlatArray Int) -> FlatArray Int
fillI k i a = if i >= k then a else
                if i == 2 then fillI k (i + 1) a else
                  let (_ # a) = write a i (i * i) in fillI k (i + 1) a

showAll : (t -> String) -> FlatIArray t -> Int -> List String
showAll sh a k = map (\i => maybe "-" sh (read a i)) [0 .. k]

runP : Int -> (1 _ : FlatArray P) -> List String
runP k a =
  let (r1 # a) = write (mapAll { x $= (+ 1.0) } k 0 (sweep k 0 (sweep k 0 (fillP k 0 a)))) k (MkP 0.0 0.0 0)
      -- (out of bounds)
      (r2 # a) = mread a (-1)
  in toIArray a (\r => show r1 :: maybe "-" showP r2 :: showAll showP r k)

runD : Int -> (1 _ : FlatArray Double) -> List String
runD k a = toIArray (mapAll (* 2.0) k 0 (scale k 0 (fillD k 0 a)))
                    (\r => showAll (\d => show (cast {to = Int} (d * 8.0))) r k)

runI : Int -> (1 _ : FlatArray Int) -> List String
runI k a =
  let (s # a) = countUp k 0 0 (fillI k 0 a)
      (s' # a) = countUp k 0 0 a
  in toIArray a (\r => show s :: show s' :: showAll show r k)

-- thawed into a smaller array
runC : Int -> (1 _ : FlatArray P) -> List String
runC k a =
  let (s # a) = msize (fillP k 0 a) in
      toIArray a (\r => thawFlat r 5 (\c =>
        let (s' # c) = msize c
            (_ # c) = write c 4 (MkP 9.0 9.0 9) in
            toIArray c (\r' => show s :: show s' :: showAll showP r' 5)))

main : IO ()
main = do
  let k = 10
  putStrLn (unwords (newFlatArray k (runP k)))
  putStrLn (unwords (newFlatArray k (runD k)))
  putStrLn (unwords (newFlatArray k (runI k)))
  putStrLn (unwords (newFlatArray k (runC k)))
  -- an array of the layout of values, read and written by the flat accesses
  b <- newArray {elem = P} 4
  ignore (writeArray b 1 (MkP 1.0 2.0 3))
  ignore (writeFlatArray b 2 (MkP 4.0 5.0 6))
  m1 <- readFlatArray b 1
  m2 <- readArray b 2
  m3 <- readFlatArray b 3
  putStrLn (unwords (map (maybe "-" showP) [m1, m2, m3]))
