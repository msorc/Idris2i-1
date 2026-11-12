module Main

import Data.Bits

-- Loops on Ints, whose variables RefC keeps in C integers (see
-- Compiler.RefC.Unbox).  The values cross 32 bits (where values are boxed)
-- and wrap around 64 bits, so that both representations meet the integers.

collatz : Int -> Int
collatz n = go n 0
  where
    go : Int -> Int -> Int
    go 1 acc = acc
    go x acc = go (if x `mod` 2 == 0 then x `div` 2 else 3 * x + 1) (acc + 1)

-- a parameter passed to another function, and returned
chunk : Int -> Int -> Int
chunk lo hi = go lo 0
  where
    go : Int -> Int -> Int
    go i acc = if i >= hi then acc else go (i + 1) (acc + collatz i)

-- the arithmetic wraps around, and goes through the boxed values
mix : Int -> Int -> Int -> Int
mix 0 h k = h
mix n h k = mix (n - 1) ((h `xor` k) * 1099511628211 + (h `shiftR` 7)) (k + n * 3)

-- Euclidean division and remainder by values of either sign
divs : Int -> Int -> Int -> Int
divs i lim acc
  = if i > lim then acc
    else let d = (i `mod` 7) - 3 in
         let d' = if d == 0 then 5 else d in
         divs (i + 1) lim (acc + (i * 1000003) `div` d' + (i * 999983) `mod` d'
                           - (((negate i `shiftL` 3) .&. 255) .|. 1))

-- Int64, with comparisons on both sides of 32 bits
countBig : Int64 -> Int64 -> Int64 -> Int64
countBig x step n = if n <= 0 then 0
                    else (if x > 2147483647 || x < -2147483648 then 1 else 0)
                         + countBig (x + step) step (n - 1)

loop64 : Int64 -> Int64 -> Int64
loop64 0 acc = acc
loop64 n acc = loop64 (n - 1) (acc * 6364136223846793005 + 1442695040888963407)

-- the smallest Int by -1, from a loop
minDiv : Int -> Int -> List (Int, Int)
minDiv 0 x = []
minDiv k x = (x `div` (-1), x `mod` (-1)) :: minDiv (k - 1) (x + 1)

-- An argument whose type depends on another one: an Int in one branch only,
-- so it must stay a value.
IntOrString : Bool -> Type
IntOrString True = Int
IntOrString False = String

describe : (b : Bool) -> IntOrString b -> Int -> String
describe True x 0 = show x
describe True x n = describe True (x * 2 + 1) (n - 1)
describe False s n = s ++ show n

main : IO ()
main = do
  printLn (collatz 27, collatz 837799)
  printLn (chunk 1 100000)
  printLn (mix 1000 14695981039346656037 0)
  printLn (divs (-500) 500 0)
  printLn (countBig 2147483000 97 100, countBig (-2147483000) (-97) 100)
  printLn (loop64 100000 1)
  printLn (minDiv 2 (-9223372036854775808))
  putStrLn (describe True 3 40)
  putStrLn (describe False "n = " 40)
