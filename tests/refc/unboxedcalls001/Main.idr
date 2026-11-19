module Main

import Data.Bits
import Data.List

-- The functions whose fixed width integer parameters and results are C
-- integers have workers that take and give them (see `Worker` in
-- Compiler.RefC.RefC); their calls by name call the workers, the closures
-- and partial applications call the functions.  Every function here is
-- called both ways, with the boundary values of the types.

-- A step and a loop that calls it (Bits64, beyond the tagged values)
step : Bits64 -> Bits64 -> Bits64
step h b = (h `xor` b) * 0x100000001b3

fnv : Bits64 -> Bits64 -> Bits64
fnv h 0 = h
fnv h n = fnv (step h (n .&. 0xff)) (n - 1)

-- A result that crosses a call that is not in tail position
sumSq : Bits64 -> Bits64
sumSq 0 = 0
sumSq n = n * n + sumSq (n - 1)

-- Mutual recursion in tail position, deep enough to overflow the stack if
-- the calls were not jumps (or went through the trampoline)
mutual
  ping : Bits64 -> Int -> Bits64
  ping acc 0 = acc
  ping acc n = pong (acc * 6364136223846793005 + 1442695040888963407) (n - 1)

  pong : Bits64 -> Int -> Bits64
  pong acc 0 = acc
  pong acc n = ping (acc `xor` (acc `shiftR` 29)) (n - 1)

-- Signed types, Euclidean division, wrapping
mixI : Int -> Int -> Int
mixI h x = (h * 1000003) `xor` x

divI64 : Int64 -> Int64 -> Int64
divI64 x y = x `div` y + x `mod` y

addI32 : Int32 -> Int32 -> Int32
addI32 x y = x + y

addB8 : Bits8 -> Bits8 -> Bits8
addB8 x y = x + y

negI16 : Int16 -> Int16
negI16 x = 0 - x

-- A fold over a list (a case on constructors gives the integer)
sumList : Bits64 -> List Bits64 -> Bits64
sumList acc [] = acc
sumList acc (x :: xs) = sumList (acc + x * 3) xs

-- A field of a value is returned: it stays a value
record Entry where
  constructor MkEntry
  key : Bits64
  name : String

keyOf : Entry -> Bits64
keyOf e = key e

-- A function with an erased argument
lenMix : (0 n : Nat) -> Bits64 -> Bits64
lenMix _ x = x `xor` 0xffffffff00000000

-- Calls one of the functions above in tail position, and one whose
-- result is a value
pick : Bool -> Bits64 -> Bits64
pick True x = step x 7
pick False x = keyOf (MkEntry x "x")

-- Casts between the types, through calls
toB64 : Int -> Bits64
toB64 x = cast x

toI : Bits64 -> Int
toI x = cast x

-- An integer compared by a caller
isBig : Bits64 -> Bool
isBig x = x > 0xffffffff

-- A loop through a closure of a function that has a worker: the closure
-- calls the function, which jumps to its worker, which jumps to the worker
-- of `goC`, which applies the closure in tail position.  The stack must not
-- grow.
goC : (Bits64 -> Int -> Bits64) -> Bits64 -> Int -> Bits64
goC f acc 0 = acc
goC f acc n = f (acc * 3 + 0x100000000) (n - 1)

bounce : Bits64 -> Int -> Bits64
bounce acc n = goC bounce acc n

applyTwice : (a -> a -> a) -> a -> a -> a
applyTwice f x y = f (f x y) y

edges64 : List Bits64
edges64 = [0, 1, 0x7fffffff, 0x80000000, 0xffffffff, 0x100000000,
           0x7fffffffffffffff, 0x8000000000000000, 0xffffffffffffffff]

edgesI : List Int
edgesI = [0, 1, -1, 2147483647, 2147483648, -2147483648, -2147483649,
          9223372036854775807, -9223372036854775808]

main : IO ()
main = do
  printLn (fnv 0xcbf29ce484222325 100000)
  printLn (map (step 0xcbf29ce484222325) edges64)
  printLn (map (\x => applyTwice step x x) edges64)
  printLn (sumSq 1000, map sumSq [0, 1, 2, 3])
  printLn (ping 1 1000000, pong 0xffffffffffffffff 3)
  let f = ping 12345
  printLn (f 100, map (pong 7) [0, 1, 2])
  printLn (map (mixI 0x123456789) edgesI)
  printLn (map (\x => applyTwice mixI x 3) edgesI)
  printLn (map (\x => (divI64 x 7, divI64 x (-7))) [0, 1, -1, 9223372036854775807, -9223372036854775808])
  printLn (map (addI32 2147483647) [0, 1, -1, -2147483648], map (addB8 255) [0, 1, 255])
  printLn (map negI16 [0, 1, -32768, 32767])
  printLn (sumList 0 edges64, foldl (\a, x => sumList a [x]) 5 edges64)
  printLn (map (\k => keyOf (MkEntry k "e")) edges64)
  printLn (map (lenMix 3) edges64)
  printLn (map (pick True) edges64, map (pick False) edges64)
  printLn (map toB64 edgesI, map (toI . toB64) edgesI)
  printLn (map isBig edges64, filter isBig edges64)
  printLn (bounce 1 1000000)
