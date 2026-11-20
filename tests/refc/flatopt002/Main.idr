||| An element of a flat array shared between two threads, read by its
||| fields (Compiler.RefC.FlatOpt) while the other thread writes it: the
||| fields read are those of one write (the element is taken whole, under
||| the lock of the array), never some of one write and some of another.
module Main

import Data.IOArray
import System.Concurrency

record Q where
  constructor MkQ
  a : Int
  b : Int
  c : Int
  d : Int

size : Int
size = 64

-- every element written with all its fields equal
writeAll : IOArray Q -> Int -> Int -> IO ()
writeAll arr k i =
  if i >= size then pure () else do
    ignore (writeFlatArray arr i (MkQ k k k k))
    writeAll arr k (i + 1)

writer : IOArray Q -> Int -> IO ()
writer arr k = if k >= 3000 then pure () else do
                 writeAll arr k 0
                 writer arr (k + 1)

-- the number of elements read whose fields are not all equal
torn : IOArray Q -> Int -> Int -> IO Int
torn arr i n =
  if i >= size then pure n else do
    Just q <- readFlatArray arr i | Nothing => torn arr (i + 1) n
    torn arr (i + 1) (if q.a == q.b && q.b == q.c && q.c == q.d then n else n + 1)

reader : IOArray Q -> Int -> Int -> IO Int
reader arr k n = if k >= 3000 then pure n else do
                   n' <- torn arr 0 n
                   reader arr (k + 1) n'

main : IO ()
main = do
  arr <- newFlatArray {elem = Q} size
  writeAll arr 0 0
  t <- fork (writer arr 1)
  n <- reader arr 0 0
  threadWait t
  putStrLn "torn elements: \{show n}"
