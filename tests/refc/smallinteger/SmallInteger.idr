-- Integer arithmetic around the limits of the unboxed (32 bit) Integers.

import Data.Bits

edges : List Integer
edges = [ 0, 1, -1, 2, -2, 7, -7, 65536, 2147483646, 2147483647, 2147483648
        , -2147483647, -2147483648, -2147483649, 4294967296, 9223372036854775807
        , -9223372036854775808, 18446744073709551616 ]

divisors : List Integer
divisors = [1, -1, 3, -3, 2147483647, -2147483648, 4294967296]

main : IO ()
main = do
  printLn [x + y | x <- edges, y <- edges]
  printLn [x - y | x <- edges, y <- edges]
  printLn [x * y | x <- edges, y <- edges]
  printLn [map (negate) edges]
  printLn [(x `div` d, x `mod` d) | x <- edges, d <- divisors]
  printLn [compare x y | x <- edges, y <- edges]
  printLn [x == y | x <- edges, y <- edges]
  printLn [shiftL x 3 | x <- edges]
  printLn [shiftR x 3 | x <- edges]
  printLn [x .&. y | x <- edges, y <- edges]
  printLn [x .|. y | x <- edges, y <- edges]
  printLn [xor x y | x <- edges, y <- edges]
  printLn (map (\x => the Int (cast x)) edges)
  printLn (map (\x => the Bits8 (cast x)) edges)
  printLn (map (\x => the Bits32 (cast x)) edges)
  printLn (map (\x => the Bits64 (cast x)) edges)
  printLn (map (\x => the Int8 (cast x)) edges)
  printLn (map (\x => the Int32 (cast x)) edges)
  printLn (map (\x => the Double (cast x)) edges)
  printLn (map (\x => the Integer (cast (the Int x))) [0, 2147483647, 2147483648, -2147483649, 9223372036854775807])
  printLn (map (\x => the Integer (cast (the Bits64 x))) [0, 2147483647, 2147483648, 4294967295, 18446744073709551615])
  printLn (the (List Integer) (map cast ["0", "-2147483648", "2147483648", "123456789012345678901234567890"]))
  printLn (map show edges)
  printLn (product [1..25], sum [1..100000])
