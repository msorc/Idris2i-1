module Main

import Data.Bits
import Data.IORef
import Data.IOArray
import Data.List
import Data.Maybe
import Data.String
import System
import System.Concurrency

-- The functions in IO take the world as a last parameter: their workers (see
-- `Worker` in Compiler.RefC.RefC) take the fixed width integers as C
-- integers, and give the result of the action as one.  So do the functions
-- whose types name the integer types through an alias or a newtype.  Every
-- function is called by name, through a closure, and from a forked thread,
-- with the boundary values of the types.

-- An IO step, and loops that call it
stepIO : Bits64 -> Bits64 -> IO Bits64
stepIO h b = pure ((h `xor` b) * 0x100000001b3)

fnvIO : Bits64 -> Bits64 -> IO Bits64
fnvIO h 0 = pure h
fnvIO h n = do
  h' <- stepIO h (n .&. 0xff)
  fnvIO h' (n - 1)

-- Int64 state, with a mod by a constant (the missing case of the mod is a
-- crash, which any integer type takes)
lcgI64 : Int64 -> Int -> IO Int64
lcgI64 x 0 = pure x
lcgI64 x n = do
  let x' = (x * 6364136223846793005 + 1442695040888963407) `mod` 0x7fffffffffffffff
  lcgI64 x' (n - 1)

bigInt : Int -> Int -> IO Int
bigInt acc 0 = pure acc
bigInt acc n = do
  let a = (acc * 1103515245 + 12345) `mod` 0x7fffffffffff
  bigInt (a + 0x100000000) (n - 1)

-- The narrow types, signed and unsigned, wrapping
addB8IO : Bits8 -> Bits8 -> IO Bits8
addB8IO x y = pure (x + y)

negI16IO : Int16 -> IO Int16
negI16IO x = pure (0 - x)

mulI32IO : Int32 -> Int32 -> IO Int32
mulI32IO x y = pure (x * y)

addB32IO : Bits32 -> Bits32 -> IO Bits32
addB32IO x y = pure (x + y)

subI8IO : Int8 -> Int8 -> IO Int8
subI8IO x y = pure (x - y)

addB16IO : Bits16 -> Bits16 -> IO Bits16
addB16IO x y = pure (x + y)

divI64IO : Int64 -> Int64 -> IO Int64
divI64IO x y = pure (x `div` y + x `mod` y)

-- An action of PrimIO
primStep : Bits64 -> PrimIO Bits64
primStep x w = MkIORes (x * 3 + 1) w

-- An IORef of a Bits64, read and written in a loop
refLoop : IORef Bits64 -> Int -> IO ()
refLoop r 0 = pure ()
refLoop r n = do
  v <- readIORef r
  writeIORef r (v * 5 + 1)
  refLoop r (n - 1)

-- An array of Bits64, summed
sumArr : IOArray Bits64 -> Int -> Int -> Bits64 -> IO Bits64
sumArr arr i n acc =
  if i >= n then pure acc
  else do
    v <- readArray arr i
    sumArr arr (i + 1) n (acc + fromMaybe 0 v)

-- Aliases and newtypes of the integer types
Hash : Type
Hash = Bits64

mixHash : Hash -> Hash -> Hash
mixHash h x = (h `xor` x) * 0x9e3779b97f4a7c15

mixHashIO : Hash -> Hash -> IO Hash
mixHashIO h x = pure (mixHash h x)

record Seed where
  constructor MkSeed
  seedVal : Bits64

nextSeed : Seed -> Seed
nextSeed (MkSeed s) = MkSeed (s * 6364136223846793005 + 1)

seedLoop : Seed -> Int -> Seed
seedLoop s 0 = s
seedLoop s n = seedLoop (nextSeed s) (n - 1)

-- A function whose result is a function, by a name
Endo : Type
Endo = Int64 -> Int64

addTo : Int64 -> Endo
addTo x y = x + y

-- The results, called every way
callAll : String -> (Bits64 -> Bits64 -> IO Bits64) -> List (Bits64, Bits64) -> IO ()
callAll what f xs = do
  rs <- traverse (\(a, b) => f a b) xs
  putStrLn "\{what}: \{show rs}"

edges64 : List (Bits64, Bits64)
edges64 = [(0, 0), (1, 0xffffffffffffffff), (0xffffffffffffffff, 0xffffffffffffffff),
           (0x7fffffff, 0x80000000), (0x8000000000000000, 1)]

main : IO ()
main = do
  -- by name
  r1 <- stepIO 0xffffffffffffffff 0x8000000000000000
  r2 <- fnvIO 0xcbf29ce484222325 100000
  r3 <- lcgI64 0x7fffffffffffffff 100000
  r4 <- bigInt 3 100000
  putStrLn (unwords [show r1, show r2, show r3, show r4])
  b8 <- addB8IO 255 1
  i16 <- negI16IO (-32768)
  i32 <- mulI32IO 2147483647 2
  b32 <- addB32IO 4294967295 2
  i8 <- subI8IO (-128) 1
  b16 <- addB16IO 65535 65535
  d64 <- divI64IO (-9223372036854775807 - 1) (-3)
  putStrLn (unwords [show b8, show i16, show i32, show b32, show i8, show b16, show d64])
  p <- primIO (primStep 0xffffffffffffffff)
  printLn p
  r <- newIORef (the Bits64 0xffffffffffffffff)
  refLoop r 1000
  readIORef r >>= printLn
  arr <- newArray 100
  for_ [0 .. 99] $ \i => writeArray arr i (cast i * 0x9e3779b97f4a7c15)
  sumArr arr 0 100 0 >>= printLn
  h <- mixHashIO 0xffffffffffffffff 1
  printLn (h, mixHash 0 0xffffffffffffffff, seedVal (seedLoop (MkSeed 0xffffffffffffffff) 1000))
  printLn (addTo 0x7fffffffffffffff 1, map (addTo 5) [0x7fffffffffffffff, -9223372036854775807 - 1])
  -- through closures and partial applications
  callAll "stepIO" stepIO edges64
  callAll "fnvIO" fnvIO [(0xcbf29ce484222325, 10), (0, 0), (0xffffffffffffffff, 3)]
  callAll "mixHashIO" mixHashIO edges64
  rs <- traverse (lcgI64 0x7fffffffffffffff) [0, 1, 2]
  printLn rs
  rs <- traverse (bigInt 0x7fffffffffffffff) [0, 1, 2]
  printLn rs
  rs <- traverse (addB8IO 200) [55, 56, 255]
  printLn rs
  rs <- traverse (\x => primIO (primStep x)) [0, 0x5555555555555555, 0xffffffffffffffff]
  printLn rs
  -- from forked threads
  results <- newIORef (the (List String) [])
  lock <- makeMutex
  ts <- for [1 .. 4] $ \k => fork $ do
    a <- fnvIO (cast k) 10000
    b <- lcgI64 (cast k) 10000
    c <- mixHashIO (cast k) 0xffffffffffffffff
    r' <- newIORef (the Bits64 (cast k))
    refLoop r' 100
    d <- readIORef r'
    mutexAcquire lock
    modifyIORef results (unwords [show k, show a, show b, show c, show d] ::)
    mutexRelease lock
  traverse_ (\t => threadWait t) ts
  readIORef results >>= traverse_ putStrLn . sort
