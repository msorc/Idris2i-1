import Data.ByteString as BS
import Data.List
import Network.WebSocket.UTF8

%default total

-- "aé€𐍈κόσμε": code points of one to four bytes.
sample : ByteString
sample = BS.pack [ 0x61, 0xc3, 0xa9, 0xe2, 0x82, 0xac, 0xf0, 0x90, 0x8d, 0x88
                 , 0xce, 0xba, 0xe1, 0xbd, 0xb9, 0xcf, 0x83, 0xce, 0xbc, 0xce, 0xb5 ]

-- The state after feeding the pieces one after the other.
feedAll : List ByteString -> Utf8State
feedAll = foldl feedUtf8 utf8Start

describe : Utf8State -> String
describe s = if utf8Invalid s then "invalid"
             else if utf8Complete s then "complete" else "incomplete"

-- Split at every pair of cut points; every split must give `expect`.
splits : ByteString -> String -> Bool
splits bs expect =
  let n = BS.length bs in
  all (\(i, j) => describe (feedAll [BS.take i bs, BS.take (minus j i) (BS.drop i bs), BS.drop j bs]) == expect)
      [ (i, j) | i <- [0 .. n], j <- [i .. n] ]

-- The index of the byte at which the state becomes invalid, fed one byte
-- at a time.
failsAt : ByteString -> Maybe Nat
failsAt bs = go 0 utf8Start (BS.unpack bs)
  where
    go : Nat -> Utf8State -> List Bits8 -> Maybe Nat
    go _ _ [] = Nothing
    go i s (w :: ws) = let s' = feedUtf8 s (BS.singleton w) in
                       if utf8Invalid s' then Just i else go (S i) s' ws

check : String -> List Bits8 -> IO ()
check name bytes = do
  let bs = BS.pack bytes
  putStrLn (name ++ ": " ++ describe (feedUtf8 utf8Start bs) ++
            ", fails at " ++ show (failsAt bs) ++ ", splits agree " ++
            show (splits bs (describe (feedUtf8 utf8Start bs))))

ascii : Nat -> List Bits8
ascii n = replicate n 0x41

main : IO ()
main = do
  putStrLn ("sample: " ++ describe (feedUtf8 utf8Start sample) ++
            ", every split into three: " ++ show (splits sample "complete"))
  putStrLn ("sample without its last byte: " ++ show (splits (BS.take 20 sample) "incomplete"))
  putStrLn "Boundaries:"
  check "  U+007F" [0x7f]
  check "  U+0080" [0xc2, 0x80]
  check "  U+07FF" [0xdf, 0xbf]
  check "  U+0800" [0xe0, 0xa0, 0x80]
  check "  U+D7FF" [0xed, 0x9f, 0xbf]
  check "  U+E000" [0xee, 0x80, 0x80]
  check "  U+FFFF" [0xef, 0xbf, 0xbf]
  check "  U+10000" [0xf0, 0x90, 0x80, 0x80]
  check "  U+10FFFF" [0xf4, 0x8f, 0xbf, 0xbf]
  putStrLn "Invalid:"
  check "  overlong NUL (2)" [0xc0, 0x80]
  check "  overlong / (2)" [0xc1, 0xaf]
  check "  overlong (3)" [0xe0, 0x80, 0xaf]
  check "  overlong (4)" [0xf0, 0x80, 0x80, 0xaf]
  check "  surrogate U+D800" [0xed, 0xa0, 0x80]
  check "  surrogate U+DFFF" [0xed, 0xbf, 0xbf]
  check "  U+110000" [0xf4, 0x90, 0x80, 0x80]
  check "  0xF5" [0xf5, 0x80, 0x80, 0x80]
  check "  0xFE" [0xfe]
  check "  0xFF" [0xff]
  check "  stray continuation" [0x41, 0x80, 0x41]
  check "  missing continuation" [0xc2, 0x41]
  check "  truncated then ASCII" [0xe2, 0x82, 0x41]
  -- Autobahn 6.4.2: fails at the surrogate, before the rest arrives
  check "  fail fast" ([0xce, 0xba, 0xe1, 0xbd, 0xb9, 0xcf, 0x83, 0xce, 0xbc, 0xce, 0xb5, 0xf4, 0x90, 0x80, 0x80] ++ ascii 5)
  putStrLn "ASCII runs (word at a time) followed by:"
  putStrLn ("  a two-byte character: " ++
            show (all (\n => describe (feedUtf8 utf8Start (BS.pack (ascii n ++ [0xc3, 0xa9] ++ ascii n))) == "complete") [0 .. 24]))
  putStrLn ("  a stray continuation byte, found at its index: " ++
            show (all (\n => failsAt (BS.pack (ascii n ++ [0x80] ++ ascii 9)) == Just n) [0 .. 24]))
  putStrLn ("  a stray byte, whole: " ++
            show (all (\n => utf8Invalid (feedUtf8 utf8Start (BS.pack (ascii n ++ [0x80] ++ ascii 9)))) [0 .. 24]))
  putStrLn ("  a slice that starts inside a buffer: " ++
            show (validUtf8 (BS.drop 3 (BS.pack (ascii 20)))))
  putStrLn ("  invalid is for good: " ++ describe (feedAll [BS.pack [0xff], BS.pack (ascii 4)]))
