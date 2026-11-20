||| Raw fields (stage A of docs/source/backends/refc-flat-layout.rst): the
||| Double, Int, Int64 and Bits64 fields of constructors are stored in their
||| cells as C numbers.  Every representation, records of pointer and raw
||| fields mixed, reuse of their cells (unique and shared), polymorphic code
||| that passes them around, closures that build them, constants, and tail
||| recursion modulo cons through a cell with raw fields.
module Main

import Data.List
import System.Concurrency

-- every raw representation, between pointer fields
record Mixed where
  constructor MkMixed
  name : String
  d : Double
  tag : Bits8
  i : Int
  big : Int64
  u : Bits64
  rest : List Int

-- a list of Int: its cells are a raw field and a pointer
data IL = INil | ICons Int IL

-- an option of a Double
data MD = NoD | SomeD Double

record P2 where
  constructor MkP2
  x : Double
  y : Double

-- a polymorphic field next to a raw one
record Tagged a where
  constructor MkTagged
  weight : Double
  item : a

Show Mixed where
  show m = "\{m.name} \{show m.d} \{show m.tag} \{show m.i} \{show m.big} \{show m.u} \{show m.rest}"

-- built from parameters, literals and results of operations
mkMixed : String -> Double -> Int -> Mixed
mkMixed s x n = MkMixed s (x * 2.0) 7 (n + 1) 9000000000000000000 18000000000000000000 [n, n + 1]

-- the record updated: its cell is reused when it is unique
bump : Mixed -> Mixed
bump m = { d $= (+ 0.5), i $= (* 3), u $= (+ 1) } m

-- the fields read in a borrowed position (the record is used after)
sumFields : Mixed -> Double
sumFields m = m.d + cast m.i + cast m.big + cast m.u

-- tail recursion modulo cons through cells with a raw field
mapIL : (Int -> Int) -> IL -> IL
mapIL f INil = INil
mapIL f (ICons x r) = ICons (f x) (mapIL f r)

fromList : List Int -> IL
fromList [] = INil
fromList (x :: xs) = ICons x (fromList xs)

sumIL : IL -> Int
sumIL = go 0
  where
    go : Int -> IL -> Int
    go acc INil = acc
    go acc (ICons x r) = go (acc + x) r

-- a conversion that must not be compiled away (see NoIntrinsic)
toMD : Maybe Double -> MD
toMD Nothing = NoD
toMD (Just d) = SomeD d

fromMD : MD -> Double
fromMD NoD = -1.0
fromMD (SomeD d) = d

-- many small records, rebuilt: the cells of the shared case are copies
step : P2 -> P2
step (MkP2 x y) = MkP2 (y + 1.0) (x * 0.5)

loop : Int -> P2 -> P2
loop 0 p = p
loop k p = loop (k - 1) (step p)

-- constants with raw fields: static values
origin : P2
origin = MkP2 0.25 (-3.5)

constMixed : Mixed
constMixed = MkMixed "const" 0.5 1 2 3 4 [5]

main : IO ()
main = do
  let m = mkMixed "m" 1.5 41
  printLn m
  printLn (bump m)          -- m is shared: the cell of bump is a copy
  printLn m
  printLn (bump (mkMixed "fresh" 2.0 1))   -- a unique cell, reused
  printLn (sumFields m)
  -- polymorphic code moves the cells around
  let ps = map (\k => MkP2 (cast k) (cast k * 2.0)) [1 .. 5]
  printLn (map (.x) (sortBy (\a, b => compare b.y a.y) ps))
  printLn (map (\p => p.x + p.y) (reverse ps))
  -- a closure that builds one (a partial application of a constructor)
  let mk = MkTagged {a = String} 0.5
  let ts = map mk ["a", "b"]
  printLn (map (\t => (t.weight, t.item)) ts)
  printLn (sumIL (mapIL (* 2) (fromList [1 .. 1000])))
  printLn (map fromMD [toMD Nothing, toMD (Just 2.5)])
  let p = loop 1000 (MkP2 1.0 2.0)
  printLn (p.x, p.y)
  printLn (origin.x, origin.y)
  printLn constMixed
  -- a record that two threads read
  t <- fork (printLn (sumFields m))
  threadWait t
  printLn (m.name, m.rest)
