import Data.ByteString as BS
import Data.ByteString.Builder as B
import Data.List

%default total
%ambiguity_depth 10

t : Show a => String -> a -> IO ()
t name v = putStrLn (name ++ ": " ++ show v)

-- The bytes of the builder, as numbers.
bytesOf : Builder -> List Bits8
bytesOf = BS.unpack . toByteString

counting : Nat -> List Bits8
counting n = go n []
  where
    go : Nat -> List Bits8 -> List Bits8
    go Z acc = acc
    go (S k) acc = go k (cast k :: acc)

-- A left-nested chain of `n` pieces: ((((x <+> x) <+> x) <+> x) ...
leftNested : Nat -> Builder -> Builder
leftNested n x = go n neutral
  where
    go : Nat -> Builder -> Builder
    go Z acc = acc
    go (S k) acc = go k (acc <+> x)

-- A right-nested chain.
rightNested : Nat -> Builder -> Builder
rightNested n x = go n neutral
  where
    go : Nat -> Builder -> Builder
    go Z acc = acc
    go (S k) acc = go k (x <+> acc)

covering
main : IO ()
main = do
  putStrLn "-- empty"
  t "empty" (toByteString B.empty)
  t "neutral" (toByteString (neutral <+> neutral), B.length (neutral <+> neutral))
  t "empty pieces" (toByteString (B.byteString BS.empty <+> B.bytes [] <+> B.utf8String "" <+> B.replicate 0 7))
  putStrLn "-- bytes and integers"
  t "word8" (bytesOf (word8 0 <+> word8 127 <+> word8 128 <+> word8 255))
  t "int8" (bytesOf (int8 0 <+> int8 127 <+> int8 (-128) <+> int8 (-1)))
  t "word16" (bytesOf (word16LE 0x0102), bytesOf (word16BE 0x0102))
  t "word16 high" (bytesOf (word16LE 0xFFFE), bytesOf (word16BE 0xFFFE))
  t "word32" (bytesOf (word32LE 0x01020304), bytesOf (word32BE 0x01020304))
  t "word32 high" (bytesOf (word32LE 0xFFFFFFFE), bytesOf (word32BE 0x80000001))
  t "word64" (bytesOf (word64LE 0x0102030405060708), bytesOf (word64BE 0x0102030405060708))
  t "word64 high" (bytesOf (word64LE 0xFFFFFFFFFFFFFFFE), bytesOf (word64BE 0x8000000000000001))
  t "int16" (bytesOf (int16LE (-2)), bytesOf (int16BE (-2)), bytesOf (int16LE 0x0102), bytesOf (int16BE 0x0102))
  t "int32" (bytesOf (int32LE (-2)), bytesOf (int32BE (-2)), bytesOf (int32LE (-0x80000000)), bytesOf (int32BE 0x7FFFFFFF))
  t "int64" (bytesOf (int64LE (-2)), bytesOf (int64BE (-2)), bytesOf (int64LE 1), bytesOf (int64BE 1))
  t "int64 min" (bytesOf (int64LE (-0x8000000000000000)), bytesOf (int64BE 0x7FFFFFFFFFFFFFFF))
  t "read back" (let bs = toByteString (word16BE 0xCAFE <+> word32LE 0xDEADBEEF <+> word64BE 0x0123456789ABCDEF)
                 in (BS.indexBits16BE 0 bs, BS.indexBits32LE 2 bs, BS.indexBits64BE 6 bs))
  putStrLn "-- byte strings and strings"
  let hello = BS.pack [104, 101, 108, 108, 111]
  t "byteString" (toByteString (byteString hello <+> byteString (BS.drop 3 hello) <+> byteString (BS.take 2 hello)))
  t "bytes" (toByteString (bytes [0, 255, 128]))
  t "replicate" (toByteString (B.replicate 5 0xAA <+> word8 1 <+> B.replicate 2 0xBB))
  t "utf8String" (bytesOf (utf8String "aé€😀"))
  t "utf8Char" (bytesOf (utf8Char 'a' <+> utf8Char 'é' <+> utf8Char '€' <+> utf8Char '😀'))
  t "literal" (toByteString ("héllo" <+> word8 33))
  t "length" (B.length (word8 1 <+> word32BE 7 <+> utf8String "é" <+> byteString hello <+> bytes [1, 2]))
  t "length is size" (let b = word8 1 <+> word32BE 7 <+> utf8String "é€" <+> byteString hello
                      in (B.length b, BS.length (toByteString b)))
  putStrLn "-- structure"
  let a = word8 1; b = word8 2; c = word8 3; d = word8 4
  t "assoc" (bytesOf ((a <+> b) <+> (c <+> d)), bytesOf (a <+> (b <+> (c <+> d))), bytesOf (((a <+> b) <+> c) <+> d))
  t "reuse" (let r = word8 9 <+> word16LE 1 in bytesOf (r <+> r <+> r))
  t "slices" (toByteString (byteString (BS.drop 1 (BS.take 4 hello)) <+> byteString (BS.drop 4 hello)))
  putStrLn "-- big"
  let n = 200000
  t "left nested" (let bs = toByteString (leftNested n (word8 7)) in (BS.length bs, BS.all (== 7) bs))
  t "right nested" (let bs = toByteString (rightNested n (word8 9)) in (BS.length bs, BS.all (== 9) bs))
  t "left words" (let bs = toByteString (leftNested n (word32BE 0x01020304))
                  in (BS.length bs, BS.indexBits32BE 0 bs, BS.indexBits32BE (4 * (n `minus` 1)) bs, BS.indexBits32LE 4 bs))
  t "mixed" (let bs = toByteString (leftNested 50000 (word16LE 1 <+> utf8String "é" <+> byteString hello <+> word8 0))
             in (BS.length bs, BS.take 14 bs))
  t "big chunk" (let bs = toByteString (byteString (BS.pack (counting 100000)) <+> word8 1 <+> byteString (BS.pack (counting 100000)))
                 in (BS.length bs, BS.index 99999 bs, BS.index 100000 bs, BS.index 100001 bs, BS.index 200000 bs))
