import Data.ByteString as BS
import Network.HTTP.Base64

%default total

-- `n` bytes `250 + 37 i` (mod 256): every bit pattern
-- turns up in some position.
bytes : Nat -> ByteString
bytes n = BS.pack (map (\i => cast (i * 37 + 250)) (take n [the Int 0 ..]))

roundTrip : Nat -> Bool
roundTrip n =
  let b = bytes n in
  decode (encode b) == Just b &&
  decodeUrl (encodeUrl b) == Just b &&
  decodeUrlUnpadded (encodeUrlUnpadded b) == Just b &&
  decodeWith Standard Unpadded (encodeWith Standard Unpadded b) == Just b

main : IO ()
main = do
  putStrLn "RFC 4648 section 10:"
  for_ ["", "f", "fo", "foo", "foob", "fooba", "foobar"] $ \s => do
    let e = encode (fromString s)
    putStrLn ("  " ++ show s ++ " -> " ++ show e ++ " -> " ++ show (decode e))
  putStrLn "Alphabets:"
  let b = BS.pack [0xfb, 0xff, 0xbf, 0xfe]
  putStrLn ("  standard " ++ show (encode b))
  putStrLn ("  url " ++ show (encodeUrl b))
  putStrLn ("  url unpadded " ++ show (encodeUrlUnpadded b))
  putStrLn ("  url decoded " ++ show (map BS.unpack (decodeUrl (fromString "-_-_-g=="))))
  putStrLn ("  standard rejects url " ++ show (decode (fromString "-_-_-g==")))
  putStrLn ("  url rejects standard " ++ show (decodeUrl (fromString "+/+/+g==")))
  putStrLn ("  round trips 0..40: " ++ show (all roundTrip [0 .. 40]))
  putStrLn "Strict decoding (standard, padded):"
  for_ [ "Z", "Zg", "Zg=", "Zm9", "Zh==", "Zm9=", "Zm8=", "Z===", "====", "=Zg="
       , "Zm9v\n", "Zm9v ", " Zm9v", "Zm 9", "Zm9vYg=a", "Zm=vYg==", "Zm9v===="
       , "Zm9vYg==Zg==", "Zm9-", "Zm9_", "Zm9\0" ] $ \s =>
    putStrLn ("  " ++ show s ++ " " ++ show (decode (fromString s)))
  putStrLn "Strict decoding (url, unpadded):"
  for_ ["Z", "Zg==", "Zh", "Zm9", "Zm8", "Zm9v+", "Zm9vY"] $ \s =>
    putStrLn ("  " ++ show s ++ " " ++ show (decodeUrlUnpadded (fromString s)))
