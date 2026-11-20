module Main

import Data.Bits

-- The Doubles computed by primitives are C doubles (see Compiler.RefC.Unbox)
-- and the functions whose Double parameters or results are C doubles have
-- workers that take and give them (see `Worker` in Compiler.RefC.RefC).
-- Every result here is what the values give (the expected output was made
-- with Doubles in values): NaN, the infinities, the signed zeros, the casts
-- to and from the integers out of their ranges, `show`.

values : List Double
values = [0.0, -0.0, 1.0, -1.5, 2.5, -2.5, 1.0e300, -1.0e300, 5.0e-324,
          1.0 / 0.0, -1.0 / 0.0, 0.0 / 0.0, 9.2233720368547758e18,
          -9.2233720368547758e18, 1.8446744073709552e19, 4.294967296e9,
          255.9, -128.5, 1114111.9, 1114112.0]

-- The comparisons, of every pair (NaN compares false, -0.0 == 0.0)
cmps : Double -> Double -> List Bool
cmps x y = [x < y, x <= y, x == y, x /= y, x >= y, x > y]

arith : Double -> Double -> List Double
arith x y = [x + y, x - y, x * y, x / y, negate x, x * 3.0 - y / 7.0]

fns : Double -> List Double
fns x = [exp x, log x, pow x 0.5, sin x, cos x, tan x, asin x, acos x,
         atan x, sqrt x, floor x, ceiling x]

-- The casts to the integer types, which wrap around (and give 0 for NaN and
-- the infinities, as the runtime does)
toInts : Double -> (Int, Int8, Int16, Int32, Int64, Bits8, Bits16, Bits32, Bits64)
toInts x = (cast x, cast x, cast x, cast x, cast x, cast x, cast x, cast x, cast x)

fromInts : Int -> Bits64 -> Int8 -> Bits8 -> Int32 -> List Double
fromInts i b i8 b8 i32 = [cast i, cast b, cast i8, cast b8, cast i32, cast i * 0.5]

-- (a big Integer is rounded to the nearest Double)
fromIntegers : List Double
fromIntegers = map (\i => fromInteger i + 0.0)
                   [0, -1, 9007199254740993, 2 `pow` 70 + 1, - (2 `pow` 64) - 1]
  where
    pow : Integer -> Nat -> Integer
    pow b Z = 1
    pow b (S k) = b * pow b k

toInteger : Double -> Integer
toInteger x = cast (x * 2.0)

-- A loop on doubles: a worker that takes and gives them
sumTo : Int -> Double -> Double
sumTo 0 acc = acc
sumTo n acc = sumTo (n - 1) (acc + cast n * 0.25)

-- A result of a call that is not in tail position
harmonic : Int -> Double
harmonic 0 = 0.0
harmonic n = 1.0 / cast n + harmonic (n - 1)

-- Mutual recursion in tail position, between functions that take doubles
-- and integers in different numbers (jumps, deep enough to overflow the
-- stack otherwise)
mutual
  ping : Double -> Double -> Int -> Double
  ping a b 0 = a + b
  ping a b n = pong (a * 0.5 + b) n

  pong : Double -> Int -> Double
  pong a 0 = a
  pong a n = ping a (a / 3.0) (n - 1)

-- Many doubles: more than the registers that the C calling conventions
-- pass them in
many : Double -> Double -> Double -> Double -> Double -> Double -> Double ->
       Double -> Double -> Double -> Int -> Double
many a b c d e f g h i j 0 = a + b + c + d + e + f + g + h + i + j
many a b c d e f g h i j n = many b c d e f g h i j (a * 1.0001) (n - 1)

-- A call in tail position of a function that takes more arguments in the
-- general registers than its caller, which takes doubles: it is not a jump
-- where the callee would need more of the stack for its arguments (the C
-- compiler would refuse it).  `strs` has no worker: it takes 8 values.
strs : String -> String -> String -> String -> String -> String -> String ->
       String -> String
strs a b c d e f g h = a ++ b ++ c ++ d ++ e ++ f ++ g ++ h

fromDoubles : Double -> Double -> Double -> Double -> Double -> Double ->
              Double -> Int -> String
fromDoubles a b c d e f g n
    = strs (show (a + b)) (show (c * 2.0)) (show (d - 1.0)) (show (e / 4.0))
           (show (f + f)) (show (g * g)) (show n) "!"

-- A case on Double literals, of a C double
classify : Double -> String
classify x = case x * 2.0 of
                  0.0 => "zero"
                  2.0 => "one"
                  1.0 => "half"
                  _ => "other"

-- A Double needed as a value too: stored in a constructor and computed with
record Point where
  constructor MkPoint
  px, py : Double

norm : Point -> Double
norm p = sqrt (p.px * p.px + p.py * p.py)

scale : Double -> Point -> Point
scale k p = let x = p.px * k in MkPoint x (x + p.py * k)

-- A newtype over Double, and an IO function giving a Double
record Meters where
  constructor MkMeters
  meters : Double

addM : Meters -> Meters -> Meters
addM (MkMeters a) (MkMeters b) = MkMeters (a + b)

halfIO : Double -> IO Double
halfIO x = pure (x / 2.0)

-- Foreign functions of C that take and give doubles
%foreign "C:fmax,libm"
fmax : Double -> Double -> Double

%foreign "C:copysign,libm"
prim__copysign : Double -> Double -> PrimIO Double

copysign : Double -> Double -> IO Double
copysign x y = primIO (prim__copysign x y)

-- The casts of a Double to and from String
strings : Double -> (String, Double)
strings x = (show (x + 1.0), cast (show x) * 2.0)

-- (a closure calls the function, which passes values)
applyAll : List (Double -> Double) -> Double -> List Double
applyAll fs x = map (\f => f x) fs

main : IO ()
main = do
  printLn values
  printLn (map (\x => map (cmps x) values) values == map (\x => map (cmps x) values) values)
  printLn [cmps x y | x <- [0.0, -0.0, 0.0 / 0.0, 1.0 / 0.0, 1.0], y <- [0.0, -0.0, 0.0 / 0.0, -1.0 / 0.0, 1.0]]
  printLn (map (\x => arith x 2.0) values)
  printLn [arith x y | x <- [0.0, -0.0, 1.0 / 0.0], y <- [0.0, -0.0, 0.0 / 0.0]]
  printLn [1.0 / (x * (-1.0)) | x <- [0.0, -0.0]]
  printLn (map fns [0.0, -0.0, 0.5, 2.0, -1.0, 1.0 / 0.0, 0.0 / 0.0, -2.5])
  printLn (map toInts values)
  printLn (fromInts 9223372036854775807 18446744073709551615 (-128) 255 (-2147483648))
  printLn (fromInts (-9007199254740993) 9007199254740993 127 0 2147483647)
  printLn fromIntegers
  printLn (map toInteger [0.0, -0.0, 1.5, -2.75, 1.0e20, -1.0e20, 4.5e15])
  printLn (sumTo 1000000 0.0)
  printLn (harmonic 10000)
  printLn (ping 1.0 2.0 1000000)
  printLn (many 1.0 2.0 3.0 4.0 5.0 6.0 7.0 8.0 9.0 10.0 100000)
  printLn (fromDoubles 1.0 2.0 3.0 4.0 5.0 6.0 7.0 8)
  printLn (map classify [0.0, -0.0, 1.0, -0.5, 0.0 / 0.0, 3.0])
  printLn (norm (scale 2.0 (MkPoint 3.0 4.0)))
  printLn (meters (addM (MkMeters 1.5) (MkMeters (-0.0))))
  printLn !(halfIO (-0.0))
  printLn (fmax 1.0 (0.0 / 0.0), fmax (-0.0) 2.5)
  printLn !(copysign 3.0 (-0.0))
  printLn (map strings [65.7, -1.0, 1114112.0, 0.0 / 0.0, 1.0e-7, 1.0e21])
  printLn (applyAll [sumTo 10, harmonic . cast, \x => ping x x 3, fmax 0.5] 4.0)
