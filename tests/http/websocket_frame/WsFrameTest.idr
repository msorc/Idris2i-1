import Data.ByteString as BS
import Data.ByteString.Builder as B
import Data.List
import Network.WebSocket.Frame
import Network.WebSocket.Handshake

%default total

hex : ByteString -> String
hex = toHex

-- Decode a frame (header and payload), unmasking the payload.
frame : DecodeOptions -> ByteString -> String
frame opts bs = case decodeHeader opts bs of
  Header h used =>
    let payload = BS.take (cast h.payloadLength) (BS.drop (cast used) bs)
        plain = case h.maskKey of Nothing => payload; Just k => mask k 0 payload
    in show h ++ " used " ++ show used ++ " payload " ++
       (if h.payloadLength <= 16 then show plain else "(" ++ show (BS.length plain) ++ " bytes)")
  r => show r

-- Every proper prefix of the header gives `NeedMore`, with a count that
-- is more than the prefix and no more than the header; the whole bytes
-- give the same as decoding at once.
prefixes : DecodeOptions -> ByteString -> Bool
prefixes opts bs = case decodeHeader opts bs of
  Header h used => all (ok used) [0 .. used - 1]
  _ => False
  where
    ok : Int -> Int -> Bool
    ok used k = case decodeHeader opts (BS.take (cast k) bs) of
                  NeedMore n => n > k && n <= used
                  _ => False

-- Encoding the decoded header and payload gives the same bytes again.
reencodes : DecodeOptions -> ByteString -> Bool
reencodes opts bs = case decodeHeader opts bs of
  Header h used =>
    let payload = BS.take (cast h.payloadLength) (BS.drop (cast used) bs)
        plain = case h.maskKey of Nothing => payload; Just k => mask k 0 payload
    in toByteString (encodeFrame h plain) == bs
  _ => False

example : String -> DecodeOptions -> List Bits8 -> IO ()
example name opts bytes = do
  let bs = BS.pack bytes
  putStrLn (name ++ ": " ++ frame opts bs)
  putStrLn ("  prefixes " ++ show (prefixes opts bs) ++ ", re-encodes " ++ show (reencodes opts bs))

-- The bytes 0, 1, 2, ... (mod 256).
counting : Nat -> ByteString
counting n = BS.pack (map cast (take n [the Int 0 ..]))

key : Bits32
key = 0x37fa213d

-- Mask in pieces cut at `cuts`, each at its offset in the payload.
piecewise : Bits32 -> Int -> List Nat -> ByteString -> ByteString
piecewise k off [] bs = mask k off bs
piecewise k off (c :: cs) bs =
  let (a, b) = BS.splitAt c bs in
  mask k off a <+> piecewise k (off + cast (BS.length a)) cs b

-- Byte `i` of the result is byte `i` XOR key byte `(off + i) mod 4`.
naive : Bits32 -> Int -> ByteString -> ByteString
naive k off bs = BS.pack (go off (BS.unpack bs))
  where
    kb : Int -> Bits8
    kb j = cast (prim__shr_Bits32 k (cast (24 - 8 * prim__and_Int j 3)))
    go : Int -> List Bits8 -> List Bits8
    go _ [] = []
    go i (w :: ws) = prim__xor_Bits8 w (kb i) :: go (i + 1) ws

maskChecks : Bool
maskChecks = all one [ (n, off) | n <- [0 .. 33], off <- [0 .. 3] ]
  where
    one : (Nat, Int) -> Bool
    one (n, off) =
      let -- an unaligned slice, so that the word loop reads at odd offsets
          bs = BS.drop 3 (counting (n + 3))
          m = mask key off bs
      in m == naive key off bs && mask key off m == bs &&
         all (\c => piecewise key off [c, 5] bs == m) [0 .. n]

invalid : String -> DecodeOptions -> List Bits8 -> IO ()
invalid name opts bytes = putStrLn (name ++ ": " ++ show (decodeHeader opts (BS.pack bytes)))

main : IO ()
main = do
  putStrLn "Handshake (RFC 6455 section 1.3):"
  putStrLn ("  " ++ show (acceptKey (fromString "dGhlIHNhbXBsZSBub25jZQ==")))
  putStrLn ("  valid keys: " ++ show (map validClientKey
             [ "dGhlIHNhbXBsZSBub25jZQ==", "dGhlIHNhbXBsZSBub25jZQ", "dGhlIHNhbXBsZSBub25jZQ=="
             , "dGhlIHNhbXBsZSBub25j", "AAAAAAAAAAAAAAAAAAAAAA==", "AAAAAAAAAAAAAAAAAAAAAB==" ]))
  putStrLn ("  client key " ++ show (clientKey (counting 16)) ++ " " ++ show (clientKey (counting 15)))

  putStrLn "RFC 6455 section 5.7:"
  example "unmasked Hello" clientOptions [0x81, 0x05, 0x48, 0x65, 0x6c, 0x6c, 0x6f]
  example "masked Hello" serverOptions [0x81, 0x85, 0x37, 0xfa, 0x21, 0x3d, 0x7f, 0x9f, 0x4d, 0x51, 0x58]
  example "fragment Hel" clientOptions [0x01, 0x03, 0x48, 0x65, 0x6c]
  example "fragment lo" clientOptions [0x80, 0x02, 0x6c, 0x6f]
  example "unmasked Ping" clientOptions [0x89, 0x05, 0x48, 0x65, 0x6c, 0x6c, 0x6f]
  example "masked Pong" serverOptions [0x8a, 0x85, 0x37, 0xfa, 0x21, 0x3d, 0x7f, 0x9f, 0x4d, 0x51, 0x58]
  example "256 bytes" clientOptions ([0x82, 0x7E, 0x01, 0x00] ++ BS.unpack (counting 256))
  example "64 KiB" clientOptions ([0x82, 0x7F, 0, 0, 0, 0, 0, 1, 0, 0] ++ BS.unpack (counting 65536))
  putStrLn ("  64 KiB header " ++ hex (encodeHeader (simpleHeader Binary 65536)))
  putStrLn ("  masked 300 header " ++ hex (encodeHeader ({ maskKey := Just key } (simpleHeader Text 300))))
  putStrLn ("  masked Hello " ++ hex (toByteString (encodeFrame ({ maskKey := Just key } (simpleHeader Text 0)) (fromString "Hello"))))

  putStrLn "Need more:"
  invalid "  empty" serverOptions []
  invalid "  one byte" serverOptions [0x81]
  invalid "  16-bit length, masked, 3 bytes" serverOptions [0x82, 0xFE, 0x01]
  invalid "  64-bit length, unmasked, 9 bytes" clientOptions [0x82, 0x7F, 0, 0, 0, 0, 0, 1, 0]
  invalid "  key missing" serverOptions [0x81, 0x85, 0x37, 0xfa]

  putStrLn "Invalid:"
  invalid "  RSV1 without extension" clientOptions [0xC1, 0x00]
  invalid "  RSV2" clientOptions [0xA1, 0x00]
  invalid "  RSV3" clientOptions [0x91, 0x00]
  putStrLn ("  RSV1 with extension: " ++ show (decodeHeader ({ allowedRsv := 0x40 } clientOptions) (BS.pack [0xC1, 0x00])))
  invalid "  RSV2 with RSV1 extension" ({ allowedRsv := 0x40 } clientOptions) [0xA1, 0x00]
  for_ [3, 4, 5, 6, 7, 11, 12, 13, 14, 15] $ \op =>
    invalid ("  opcode " ++ show op) clientOptions [0x80 + op, 0x00]
  invalid "  fragmented ping" clientOptions [0x09, 0x00]
  invalid "  fragmented close" clientOptions [0x08, 0x00]
  invalid "  ping of 126 bytes" clientOptions [0x89, 0x7E, 0x00, 0x7E]
  invalid "  ping of 125 bytes (valid)" clientOptions [0x89, 0x7D]
  invalid "  unmasked frame to a server" serverOptions [0x81, 0x05]
  invalid "  masked frame to a client" clientOptions [0x81, 0x85, 1, 2, 3, 4]
  invalid "  16-bit length 125" clientOptions [0x82, 0x7E, 0x00, 0x7D]
  invalid "  16-bit length 126 (valid)" clientOptions [0x82, 0x7E, 0x00, 0x7E]
  invalid "  64-bit length 65535" clientOptions [0x82, 0x7F, 0, 0, 0, 0, 0, 0, 0xFF, 0xFF]
  invalid "  64-bit length with top bit" clientOptions [0x82, 0x7F, 0x80, 0, 0, 0, 0, 0, 0, 0]
  invalid "  above maxPayload" ({ maxPayload := 1000 } clientOptions) [0x82, 0x7E, 0x03, 0xE9]
  invalid "  at maxPayload (valid)" ({ maxPayload := 1000 } clientOptions) [0x82, 0x7E, 0x03, 0xE8]
  putStrLn ("  close codes for errors: " ++ show (map closeCodeFor [ReservedBitSet, ControlTooLong, PayloadTooLarge]))

  putStrLn "Masking:"
  putStrLn ("  lengths 0..33 at offsets 0..3, piecewise: " ++ show maskChecks)
  putStrLn ("  " ++ hex (mask key 0 (fromString "Hello")) ++ " " ++ hex (mask key 1 (fromString "ello")))

  putStrLn "Close frames:"
  for_ [0, 999, 1000, 1001, 1002, 1003, 1004, 1005, 1006, 1007, 1011, 1012, 1014, 1015, 1016, 2999, 3000, 4999, 5000, 65535] $ \c =>
    putStrLn ("  " ++ show c ++ " " ++ show (validCloseCode c))
  let cp = closePayload 1000 (fromString "bye")
  putStrLn ("  payload " ++ hex cp ++ " " ++ show (parseClose cp))
  putStrLn ("  empty " ++ show (parseClose BS.empty))
  putStrLn ("  one byte " ++ show (parseClose (BS.pack [0x03])))
  putStrLn ("  code 1005 " ++ show (parseClose (BS.pack [0x03, 0xED])))
  putStrLn ("  bad reason " ++ show (parseClose (BS.pack [0x03, 0xE8, 0xC3, 0x28])))
  putStrLn ("  utf-8 reason " ++ show (map (map (map BS.unpack)) (parseClose (BS.pack [0x0F, 0xA0, 0xCE, 0xBA]))))
  putStrLn ("  error codes " ++ show (map closeErrorCode [CloseTruncated, InvalidCloseCode 5, InvalidReason]))
