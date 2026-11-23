-- The direct reads of Data.ByteString.Internal, and fromString/toString.
import Data.ByteString
import Data.ByteString.Internal
import Data.Buffer

main : IO ()
main = do
  let bs = drop 2 (pack [0, 1, 0x41, 0x42, 0x43, 0x44, 0xC3, 0xA9, 0xFF])
  let buf = unsafeBuffer bs
  let o = unsafeOffset bs
  printLn (o, map (\i => unsafeBufferByte buf (o + i)) [0 .. 6])
  printLn (unsafeBufferWord32LE buf o == 0x44434241)
  printLn (unsafeBufferString buf o 6)
  printLn (map (unsafeIndex bs) [0, 4, 6])
  -- fromString is the UTF-8 encoding; toString checks it
  let s : String = "a\0b caf\233 \8364 \128512"
  printLn (Data.ByteString.unpack (Data.ByteString.fromString s))
  printLn (toString (fromString s) == Just s)
  printLn (Data.ByteString.length (Data.ByteString.fromString ""), toString empty)
  printLn (map toString [pack [0xC3], pack [0xED, 0xA0, 0x80], pack [0xF4, 0x90, 0x80, 0x80], pack [0xE0, 0x80, 0xAF], pack [0x80]])
  printLn (isValidUtf8 (fromString s), isValidUtf8 (pack [0x61, 0xFF]))
