module Buf

import Data.Buffer
import Data.List
import Data.String
import Data.Nat

%default covering

say : String -> IO ()
say = putStrLn

hex8 : Bits8 -> String
hex8 b = show b

dump : Buffer -> Int -> IO String
dump b n = do
  bs <- traverse (\i => getBits8 b i) [0 .. n - 1]
  pure (unwords (map (\x => show x) bs))

-- every accessor at several values: write at offset 1 into a zeroed buffer,
-- show the bytes, read it back
test : Show a => (name : String) -> (shown : Int)
    -> (set : Buffer -> Int -> a -> IO ()) -> (get : Buffer -> Int -> IO a)
    -> List a -> IO ()
test name shown set get vals = for_ vals $ \v => do
  Just b <- newBuffer 16 | Nothing => say "no buffer"
  set b 1 v
  d <- dump b shown
  r <- get b 1
  say (name ++ " " ++ show v ++ ": " ++ d ++ " -> " ++ show r)


main : IO ()
main = do
  Just b <- newBuffer 8 | Nothing => say "no"
  say ("size " ++ show !(rawSize b))
  test "Bits8" 3 setBits8 getBits8 [0, 1, 127, 128, 255]
  test "Int8" 3 setInt8 getInt8 [0, 1, 127, -1, -128, 128, 255, -129]
  test "Bits16" 4 setBits16 getBits16 [0, 1, 255, 256, 32767, 32768, 65535]
  test "Int16" 4 setInt16 getInt16 [0, 1, 255, 256, 32767, -1, -32768, 32768, 65535]
  test "Bits32" 6 setBits32 getBits32 [0, 1, 65536, 2147483647, 2147483648, 4294967295]
  test "Int32" 6 setInt32 getInt32 [0, 1, 65536, 2147483647, -1, -2147483648, 2147483648]
  test "Bits64" 10 setBits64 getBits64
    [0, 1, 4294967296, 9007199254740991, 9007199254740992, 9007199254740993, 9223372036854775807, 9223372036854775808, 18446744073709551615, 12345678901234567890]
  test "Int64" 10 setInt64 getInt64
    [0, 1, -1, 4294967296, 9007199254740991, 9007199254740993, -9007199254740993, 9223372036854775807, -9223372036854775808, 1234567890123456789]
  test "Int" 5 setInt getInt [0, 1, 2147483647, -1, -2147483648]
  test "Double" 10 setDouble getDouble [1.5, -2.25, 1.0e-10, 123456.789]
  test "Byte" 3 setByte getByte [0, 1, 255, 127, 256, -1, 300]
  -- string and copy
  Just s <- newBuffer 16 | Nothing => say "no"
  setString s 2 "h\xe9llo"
  say (show !(dump s 12))
  say (show !(getString s 2 6))
  say (show (stringByteLength "h\xe9llo \x1f600"))
  Just t <- newBuffer 16 | Nothing => say "no"
  copyData s 2 6 t 5
  say !(dump t 12)
  Just u <- resizeBuffer t 20 | Nothing => say "no"
  say (show !(rawSize u))
  Just w <- concatBuffers [s, t, u] | Nothing => say "no"
  say (show !(rawSize w))
  -- Integer and Nat (limbs)
  Just n <- newBuffer 64 | Nothing => say "no"
  e <- setInteger n 0 (-123456789012345678901234567890)
  say (show e)
  say (show !(getInteger n 0))
  e2 <- setNat n 0 (1180591620717411303429)
  say (show e2)
  say (show !(getNat n 0))
  setBool n 0 True
  say (show !(getBool n 0))
  say (show !(bufferData' n >>= pure . take 4))
