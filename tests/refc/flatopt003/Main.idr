||| A case on an element read from a flat array (Compiler.RefC.FlatOpt) with
||| a branch for one of `Nothing` and `Just` and a default for the other:
||| the default is taken for the elements that are not the branch's, of
||| records and of primitives.
module Main

import Data.IOArray

record P where
  constructor MkP
  x : Double
  y : Double

-- (a branch for Nothing, a default)
present : IOArray P -> Int -> IO Int
present a i = do
  m <- readFlatArray a i
  case m of
    Nothing => pure 0
    _ => pure 1

-- (the same after an element read by its fields)
shifted : IOArray P -> Int -> IO Double
shifted a i = do
  Just p <- readFlatArray a 1 | Nothing => pure (-1.0)
  m <- readFlatArray a i
  case m of
    Nothing => pure p.x
    _ => pure (p.x + 100.0)

-- (a branch for Just, a default)
field : IOArray P -> Int -> IO Double
field a i = do
  m <- readFlatArray a i
  case m of
    Just p => pure p.y
    _ => pure (-1.0)

presentD : IOArray Double -> Int -> IO Int
presentD a i = do
  m <- readFlatArray a i
  case m of
    Nothing => pure 0
    _ => pure 1

fieldD : IOArray Double -> Int -> IO Double
fieldD a i = do
  m <- readFlatArray a i
  case m of
    Just d => pure d
    _ => pure (-1.0)

main : IO ()
main = do
  ps <- newFlatArray {elem = P} 3
  ignore (writeFlatArray ps 1 (MkP 1.0 2.0))
  printLn [!(present ps 0), !(present ps 1), !(present ps 2)]
  printLn [!(shifted ps 0), !(shifted ps 1), !(shifted ps 2)]
  printLn [!(field ps 0), !(field ps 1), !(field ps 2)]
  ds <- newFlatArray {elem = Double} 3
  ignore (writeFlatArray ds 2 4.5)
  printLn [!(presentD ds 0), !(presentD ds 1), !(presentD ds 2)]
  printLn [!(fieldD ds 0), !(fieldD ds 1), !(fieldD ds 2)]
