module BufInt

-- setInt and getInt take eight bytes, as with Chez and RefC: the bytes of
-- the value sign-extended to 64 bits (JavaScript's Int has 32 bits).

import Data.Buffer
import Data.String

%default covering

dump : Buffer -> IO String
dump b = do
  bs <- traverse (\i => getBits8 b i) [0 .. 9]
  pure (unwords (map show bs))

main : IO ()
main = do
  Just b <- newBuffer 10 | Nothing => putStrLn "no buffer"
  for_ [0, 1, -1, 2147483647, -2147483648, 256] $ \v => do
    -- over bytes that are all 255: every one of the eight is written
    for_ [0 .. 9] $ \i => setBits8 b i 255
    setInt b 1 v
    putStrLn (show v ++ ": " ++ !(dump b) ++ " -> " ++ show !(getInt b 1)
              ++ " " ++ show !(getInt64 b 1))
  -- getInt of eight bytes that another backend wrote for a 64 bit Int: the
  -- low 32 bits, as a cast of the Int64 gives
  for_ [4294967297, -4294967297, 1099511627775] $ \v => do
    setInt64 b 0 v
    putStrLn (show v ++ " -> " ++ show !(getInt b 0) ++ " " ++ show (the Int (cast v)))
