module Main

import Data.Bits
import System

-- The murmur3 finaliser: its parameter and lets are C integers (uint64_t)
mix : Bits64 -> Bits64
mix x = let a = (x `xor` (x `shiftR` 33)) * 0xff51afd7ed558ccd
            b = (a `xor` (a `shiftR` 33)) * 0xc4ceb9fe1a85ec53 in
            b `xor` (b `shiftR` 33)

-- a loop on Bits64 and Int: nothing is boxed in it
hash : Bits64 -> Int -> Bits64
hash acc 0 = acc
hash acc n = let a = (acc `xor` cast n) * 0x100000001b3 in
                 hash (a `xor` (a `shiftR` 29)) (n - 1)

-- FNV-1a on bytes (Bits32 and Bits8)
fnv : Bits32 -> Int -> Bits32
fnv h 0 = h
fnv h n = let byte : Bits8 = cast n in
              fnv ((h `xor` cast byte) * 16777619) (n - 1)

-- a mask of 32 bits on Int: a C constant, not an Integer made at every step
mask : Int -> Int -> Int
mask acc 0 = acc
mask acc n = mask ((acc * 1103515245 + 12345) .&. 0xffffffff) (n - 1)

-- a `case` on Int16 literals
classify : Int16 -> Int16 -> Int
classify x d = case x * d of
  0 => 0
  (-32768) => 1
  32767 => 2
  _ => 3

main : IO ()
main = do
  printLn (mix 1, mix 0xffffffffffffffff)
  printLn (hash 1 100000)
  printLn (fnv 2166136261 100000)
  printLn (mask 1 100000)
  printLn (map (\x => classify x 1) [0, -32768, 32767, 5], classify 16384 2)
