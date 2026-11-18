-- What went wrong when the generated C was compiled for a 32 bit platform
-- (see `run`: with `cc -m32` where there is one, natively otherwise; the
-- output is the same).

import Data.Buffer
import Data.List

-- Not constants for the compiler: the casts are made when the program runs.
big : List Integer
big = [0, 1, -1, 2147483647, 2147483648, -2147483648, -2147483649,
       4294967295, 4294967296, 4294967297, -4294967296, 1000000000000,
       -1000000000000, 9223372036854775807, 9223372036854775808,
       -9223372036854775808, -9223372036854775809, 18446744073709551615,
       18446744073709551616, 18446744073709551617,
       1234567890123456789012345678901234567890,
       -1234567890123456789012345678901234567890]

classify : Int -> String
classify 0 = "zero"
classify 4294967296 = "2^32"
classify 4294967297 = "2^32 + 1"
classify 1 = "one"
classify (-4294967296) = "-2^32"
classify 9223372036854775807 = "max"
classify _ = "other"

classifyInteger : Integer -> String
classifyInteger 1 = "one"
classifyInteger 4294967297 = "2^32 + 1"
classifyInteger 18446744073709551617 = "2^64 + 1"
classifyInteger (-1) = "minus one"
classifyInteger _ = "other"

classifyChar : Char -> String
classifyChar 'a' = "a"
classifyChar '\x1F600' = "U+1F600"
classifyChar '\xF600' = "U+F600"
classifyChar '\x10FFFF' = "U+10FFFF"
classifyChar _ = "other"

-- Calls in tail position between functions with different numbers of
-- arguments, and through closures: they must not use the C stack.
mutual
  even' : Int -> Bool
  even' 0 = True
  even' n = odd' (n - 1) 0 0 0 0 0 0 0

  odd' : Int -> Int -> Int -> Int -> Int -> Int -> Int -> Int -> Bool
  odd' 0 _ _ _ _ _ _ _ = False
  odd' n a b c d e f g = even' (n - 1 + a + b + c + d + e + f + g)

applyN : Int -> (Int -> Int -> Int -> Int) -> Int -> Int
applyN 0 f acc = acc
applyN n f acc = applyN (n - 1) f (f acc n 1)

main : IO ()
main = do
  printLn (map (cast {to = Int}) big)
  printLn (map (cast {to = Int64}) big)
  printLn (map (cast {to = Bits64}) big)
  printLn (map (cast {to = Int32}) big)
  printLn (map (cast {to = Bits32}) big)
  printLn (map (cast {to = Bits16}) big)
  printLn (map (cast {to = Int8}) big)
  printLn (map (cast {to = Double}) big)
  -- and back
  printLn (map (cast {to = Integer} . cast {to = Int}) big == map (cast {to = Integer} . cast {to = Int64}) big)
  printLn (map (\i => cast {to = Integer} (cast {to = Bits64} i) + 1) big)
  printLn (map (\i => cast {to = Integer} (cast {to = Int} i * 3)) big)
  -- a `case` on constants that do not fit in 32 bits
  printLn (map (classify . cast) big)
  printLn (map classifyInteger big)
  -- characters above U+FFFF
  let chars = map (cast {to = Char}) (the (List Int) [97, 0xF600, 0x1F600, 0x10FFFF, 0x10000])
  printLn (map ord chars)
  printLn (map classifyChar chars)
  printLn (map (\c => ord (chr (ord c + 1))) chars)
  putStrLn (pack chars)
  printLn (map ord (unpack (pack chars)), length (pack chars))
  printLn (map (cast {to = Int} . cast {to = Bits16}) chars, map (cast {to = Integer}) chars)
  -- strings to numbers
  printLn (map (cast {to = Int}) ["4294967297", "-9223372036854775808", "18446744073709551617"])
  printLn (map (cast {to = Bits64}) ["4294967297", "-1", "18446744073709551617"])
  -- shifts of Integers
  printLn (map (\i => (i `prim__shl_Integer` 33, i `prim__shr_Integer` 33)) (take 12 big))
  -- 64 bit values in a buffer
  Just buf <- newBuffer 32
    | Nothing => putStrLn "no buffer"
  setBits64 buf 0 (cast (the Integer 0x1122334455667788))
  setInt64 buf 8 (cast (the Integer (-0x1122334455667788)))
  setInt buf 16 (cast (the Integer 0x7766554433221100))
  setDouble buf 24 1.5
  printLn (!(getBits64 buf 0), !(getInt64 buf 8), !(getInt buf 16), !(getDouble buf 24))
  printLn !(traverse (getBits8 buf) [0 .. 23])
  -- tail calls
  printLn (even' 1000000, even' 1000001)
  printLn (applyN 1000000 (\a, n, k => (a + n * k) `mod` 1000003) 0)
