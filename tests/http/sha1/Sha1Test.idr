import Data.ByteString as BS
import Data.List
import Network.HTTP.SHA1

%default total

t : String -> ByteString -> IO ()
t name msg = putStrLn (name ++ ": " ++ toHex (sha1 msg))

-- `n` copies of a string.
copies : Nat -> String -> ByteString
copies n s = BS.concat (List.replicate n (fromString s))

main : IO ()
main = do
  -- RFC 3174 section 7.3 and FIPS 180 examples
  t "abc" (fromString "abc")
  t "empty" BS.empty
  t "448 bits" (fromString "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq")
  t "896 bits" (fromString "abcdefghbcdefghicdefghijdefghijkefghijklfghijklmghijklmnhijklmnoijklmnopjklmnopqklmnopqrlmnopqrsmnopqrstnopqrstu")
  t "million a" (BS.replicate 1000000 97)
  t "01234567 x 80" (copies 80 "01234567")
  -- Around the padding boundaries: a block holds at most 55 bytes of
  -- message with the padding, and 64 in all.
  for_ [0, 1, 54, 55, 56, 57, 63, 64, 65, 119, 120, 127, 128, 129] $ \n =>
    t ("a x " ++ show n) (BS.replicate n 97)
  -- All the byte values, and a slice (offset in its buffer)
  t "0..255" (BS.pack (map cast [the Int 0 .. 255]))
  t "slice" (BS.drop 3 (BS.take 10 (fromString "xxxabcyyyy")))
