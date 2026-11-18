module Main

import Data.IOArray
import Data.Linear.Array as L
import Data.List
import Data.String
import Rose

-- The slots of an array, with `_` for an empty one.
showArr : IOArray Int -> IO String
showArr arr = do xs <- toList arr
                 pure (unwords (map (maybe "_" show) xs))

range : Int -> Int -> IO (IOArray Int)
range from n = fromList (map (Just . (from +)) [0 .. n - 1])

copyTest : String -> Int -> Int -> Int -> IO ()
copyTest msg sp dp len = do
  src <- range 0 6
  dst <- range 10 6
  ok <- copyArrayRange src sp dst dp len
  s <- showArr dst
  putStrLn "\{msg}: \{show ok} \{s}"

-- Copies within one array: the ranges overlap
selfTest : String -> Int -> Int -> Int -> IO ()
selfTest msg sp dp len = do
  arr <- range 0 8
  ok <- copyArrayRange arr sp arr dp len
  s <- showArr arr
  putStrLn "\{msg}: \{show ok} \{s}"

ioTests : IO ()
ioTests = do
  arr <- newArray {elem = Int} 4
  w1 <- writeArray arr 1 11
  w2 <- writeArray arr 4 44
  w3 <- writeArray arr (-1) 0
  r1 <- readArray arr 1
  r2 <- readArray arr 0
  r3 <- readArray arr 4
  printLn [w1, w2, w3]
  printLn [r1, r2, r3]
  printLn (max arr)
  putStrLn =<< showArr arr
  copyTest "middle" 1 2 3
  copyTest "all" 0 0 6
  copyTest "none" 3 3 0
  copyTest "at end" 6 6 0
  copyTest "src too far" 4 0 3
  copyTest "dst too far" 0 4 3
  copyTest "negative len" 0 0 (-1)
  copyTest "negative src" (-1) 0 2
  copyTest "negative dst" 0 (-1) 2
  copyTest "huge len" 1 1 9223372036854775807
  selfTest "self right" 0 2 5
  selfTest "self left" 2 0 5
  selfTest "self same" 1 1 4
  -- empty slots are copied as empty
  holes <- fromList [Just 1, Nothing, Just 3]
  dst <- range 10 4
  ok <- copyArrayRange holes 0 dst 1 3
  putStrLn "holes: \{show ok} \{!(showArr dst)}"
  -- newArrayCopy: larger, smaller (keeps the old size), empty
  big <- newArrayCopy 6 holes
  small <- newArrayCopy 1 holes
  e <- newArray {elem = Int} 0
  ee <- newArrayCopy 0 e
  putStrLn "copies: \{!(showArr big)} | \{!(showArr small)} | \{show (max ee)}"
  -- the copy is independent of the original
  _ <- writeArray big 0 100
  putStrLn "independent: \{!(showArr holes)} | \{!(showArr big)}"
  -- elements that are not Ints, shared between arrays
  strs <- fromList (map Just ["a", "b", "c"])
  strs2 <- newArrayCopy 3 strs
  _ <- writeArray strs 0 "z"
  _ <- copyArrayRange strs 0 strs2 1 2
  xs <- toList strs2
  printLn xs

-- A MArray that keeps the default `mcopy`, which copies element by element
data Slow : Type -> Type where
  MkSlow : (1 _ : LinArray t) -> Slow t

Array Slow where
  read (MkSlow a) i = read a i
  size (MkSlow a) = size a

MArray Slow where
  newArray n k = newArray n (\a => k (MkSlow a))
  write (MkSlow a) i x = let ok # a = write a i x in ok # MkSlow a
  mread (MkSlow a) i = let v # a = mread a i in v # MkSlow a
  msize (MkSlow a) = let n # a = msize a in n # MkSlow a

freezeSlow : (1 _ : Slow t) -> IArray t
freezeSlow (MkSlow a) = toIArray a id

elems : IArray Int -> String
elems a = unwords [maybe "_" show (read a i) | i <- [0 .. size a - 1]]

fromL : List Int -> IArray Int
fromL xs = L.newArray (cast (length xs)) (go 0 xs)
  where
    go : Int -> List Int -> (1 _ : LinArray Int) -> IArray Int
    go i [] a = toIArray a id
    go i (x :: xs) a = let (_ # a) = write a i x in go (i + 1) xs a

-- Two arrays of the same constant size made in two places must not be one
-- array
mk1 : Int -> IArray Int
mk1 v = L.newArray 3 (\a => let (_ # a) = write a 0 v in toIArray a id)

mk2 : Int -> IArray Int
mk2 v = L.newArray 3 (\a => let (_ # a) = write a 0 v in toIArray a id)

-- insert in the middle, with two copies
insertTest : IArray Int -> (Bool, Bool, String)
insertTest src
    = L.newArray 6 $ \a =>
        let (ok1 # a) = copyInto src 0 a 0 2
            (_ # a) = write a 2 99
            (ok2 # a) = copyInto src 2 a 3 3 in
            toIArray a (\r => (ok1, ok2, elems r))

badCopy : IArray Int -> (Bool, String)
badCopy src
    = L.newArray 3 $ \a =>
        let (ok # a) = copyInto src 3 a 0 3 in toIArray a (\r => (ok, elems r))

fz : (1 _ : LinArray Int) -> Res String (const ())
fz a = toIArray a (\r => elems r # ())

both : (1 _ : LPair (LinArray Int) (LinArray Int)) -> (String, String)
both (a # b) = let (x # ()) = fz a
                   (y # ()) = fz b in
                   (x, y)

-- copyArray, which uses mcopy
copyTest1 : (String, String)
copyTest1
    = L.newArray 4 $ \a =>
        let (_ # a) = write a 0 7
            (_ # a) = write a 3 8
            (a # b) = copyArray 6 a
            (_ # b) = write b 5 9 in
            both (a # b)

copyTest2 : (String, String)
copyTest2
    = L.newArray 4 $ \a =>
        let (_ # a) = write a 1 5 in
            both (copyArray 2 a)

slowBoth : (1 _ : LPair (Slow Int) (Slow Int)) -> Res (String, String) (const ())
slowBoth (MkSlow a # MkSlow b) = let (x # ()) = fz a
                                     (y # ()) = fz b in
                                     (x, y) # ()

-- the default mcopy
slowTest : (Bool, Bool, (String, String))
slowTest
    = L.newArray {arr = Slow} 4 $ \a =>
        let (_ # a) = write a 0 1
            (_ # a) = write a 1 2
            (a # b) = copyArray 3 a
            (ok # ab) = mcopy a 0 b 1 2
            (a # b) = ab
            (bad # ab) = mcopy a 3 b 0 2
            (r # ()) = slowBoth ab in
            (ok, bad, r)

linearTests : IO ()
linearTests = do
  let src = fromL [1, 2, 3, 4, 5]
  -- an updated copy: thaw, write, freeze
  let upd = thaw src 5 (\a => let (_ # a) = write a 2 30 in toIArray a id)
  putStrLn "thaw: \{elems src} | \{elems upd}"
  putStrLn "thaw larger: \{elems (thaw src 7 (\a => toIArray a id))}"
  putStrLn "thaw smaller: \{elems (thaw src 2 (\a => toIArray a id))}"
  putStrLn "thaw negative: \{show (size (thaw src (-1) (\a => toIArray a id)))}"
  printLn (insertTest src)
  printLn (badCopy src)
  printLn copyTest1
  printLn copyTest2
  printLn slowTest
  let x = mk1 1
      y = mk2 2
      z = mk1 3
  printLn (read x 0, read y 0, read z 0)
  printLn (sumRose (node 1 [leaf 2, node 3 [leaf 4, leaf 5], leaf 6]))

main : IO ()
main = do
  ioTests
  linearTests
