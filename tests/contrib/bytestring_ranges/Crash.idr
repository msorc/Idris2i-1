-- The checked reads of RefC stop the program on a range that is not within
-- the buffer (the other backends raise their own errors).
import Data.ByteString as BS
import Data.Buffer
import Data.ByteString.Internal
import System

main : IO ()
main = do
  [_, what] <- getArgs | _ => pure ()
  let bs = pack [1, 2, 3, 4]
      b = unsafeBuffer bs
  case what of
    "byte" => printLn (unsafeBufferByte b 4)
    "neg" => printLn (unsafeBufferByte b (-1))
    "word" => printLn (unsafeBufferWord32LE b 1)
    "compare" => printLn (unsafeCompareRange b 1 b 0 4)
    "find" => printLn (unsafeFindByte 9 b 2 3)
    "hash" => printLn (unsafeHashRange 0 b 0 5)
    _ => printLn (unsafeBufferByte b 3, unsafeBufferWord32LE b 0)
