module CopyData

import Data.Buffer

-- copyData within one buffer, where the two ranges overlap
fill : Buffer -> IO ()
fill buf = traverse_ (\i => setBits8 buf i (cast i)) [0 .. 31]

main : IO ()
main = do
  Just buf <- newBuffer 32
    | Nothing => putStrLn "no buffer"
  fill buf
  copyData buf 0 20 buf 5
  bufferData buf >>= printLn
  fill buf
  copyData buf 5 20 buf 0
  bufferData buf >>= printLn
  fill buf
  copyData buf 1 31 buf 0
  bufferData buf >>= printLn
