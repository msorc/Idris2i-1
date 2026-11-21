||| A projection in a branch, next to an element read from a flat array by
||| its fields (Compiler.RefC.FlatOpt): it is made in its branch only.  That
||| the case on `v` in `getS` has a single alternative tells that `v` is a
||| `VT` where `b` is True only: made before the test of `b`, the projection
||| would take the field of a `VG` (an integer stored raw) for a string.
module Main

import Data.IOArray
import System

record P where
  constructor MkP
  x : Double
  y : Double

data V : Bool -> Type where
  VT : String -> V True
  VF : V False
  VG : Int -> Int -> V False

%inline
getS : V True -> String
getS (VT s) = s

%inline
mkP : (b : Bool) -> V b -> P
mkP True v = MkP (if getS v == "abc" then 10.0 else 20.0) 1.0
mkP False _ = MkP 2.0 3.0

%noinline
mk : (b : Bool) -> V b -> IOArray P -> IO Double
mk b v a = do
  Just p <- readFlatArray a 1 | Nothing => pure (-1.0)
  let q = mkP b v
  pure (q.x + q.y + p.x)

-- (the value is not known when `mk` is compiled)
pickV : Nat -> Nat -> (b : Bool ** V b)
pickV k n = case k of
              0 => (True ** VT "abc")
              1 => (False ** VG (cast n * 8) (cast n * 8))
              _ => (False ** VF)

main : IO ()
main = do
  ps <- newFlatArray {elem = P} 3
  ignore (writeFlatArray ps 1 (MkP 1.0 2.0))
  n <- map length getArgs
  for_ [0, 1, 2] $ \k => do
    let (b ** v) = pickV k n
    printLn !(mk b v ps)
