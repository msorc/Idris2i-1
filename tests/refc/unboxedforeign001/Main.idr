import Data.Bits
import Data.Buffer

%default total

-- Foreign functions that take and give fixed width integers: their calls
-- pass and get C integers (see `foreignWorker` in Compiler.RefC.RefC).
%foreign "RefC:getBufferUInt8"
prim__peek8 : Buffer -> Int -> Bits8

%foreign "RefC:getBufferUInt64LE"
prim__peek64 : Buffer -> Int -> Bits64

%foreign "RefC:setBufferUInt8"
prim__poke8 : Buffer -> Int -> Bits8 -> PrimIO ()

%foreign "C:llabs,libc"
cabs : Int -> Int

%foreign "C:abs,libc"
cabs32 : Int32 -> Int32

-- The sum of the bytes, read with the pure foreign function.
sumBytes : Buffer -> (i : Int) -> (n : Int) -> Bits64 -> Bits64
sumBytes b i n acc =
  if i >= n then acc
  else sumBytes b (assert_smaller i (i + 1)) n (acc + cast (prim__peek8 b i))

-- The words, mixed.
mixWords : Buffer -> (i : Int) -> (n : Int) -> Bits64 -> Bits64
mixWords b i n acc =
  if i + 8 > n then acc
  else mixWords b (assert_smaller i (i + 8)) n ((acc * 31) `xor` prim__peek64 b i)

fill : Buffer -> Int -> Int -> IO ()
fill b i n = if i >= n then pure ()
             else do primIO (prim__poke8 b i (cast (i * 7 + 3)))
                     fill b (assert_smaller i (i + 1)) n

main : IO ()
main = do
  Just b <- newBuffer 1000 | Nothing => putStrLn "no buffer"
  fill b 0 1000
  printLn (sumBytes b 0 1000 0)
  printLn (mixWords b 0 1000 0)
  printLn (map cabs [-5, 0, 0x7FFFFFFFFFFF, -0x100000000], map cabs32 [-7, 7])
  -- a partial application calls the wrapper, which takes values
  printLn (map (prim__peek8 b) [0, 1, 999])
