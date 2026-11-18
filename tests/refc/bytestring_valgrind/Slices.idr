import Data.ByteString as BS
import Data.ByteString.Builder as B
import Data.List
import Data.List1

%default total

counting : Nat -> List Bits8
counting n = go n []
  where
    go : Nat -> List Bits8 -> List Bits8
    go Z acc = acc
    go (S k) acc = go k (cast k :: acc)

-- The parent buffer is dropped while slices of it live on.
slices : (ByteString, ByteString, ByteString)
slices = let parent = BS.pack (counting 1000)
         in (BS.take 10 parent, BS.drop 990 parent, BS.take 5 (BS.drop 500 parent))

-- Drop the large parent, keep a copy of a small slice.
small : ByteString
small = BS.copy (BS.take 4 (BS.drop 100 (BS.pack (counting 100000))))

main : IO ()
main = do
  let (a, b, c) = slices
  printLn (BS.unpack a, BS.unpack b, BS.unpack c)
  printLn small
  -- many short-lived slices of one buffer
  let big = BS.pack (counting 50000)
  let sums = map (\i => BS.foldl (\acc, w => acc + cast w) (the Integer 0) (BS.take 16 (BS.drop (cast (i * 16)) big)))
                 (counting 3000)
  printLn (sum sums)
  -- slices of slices, appended, concatenated and built
  let parts = forget (BS.split 0 big)
  printLn (length parts, BS.length (BS.concat parts))
  printLn (BS.length (BS.intercalate (BS.singleton 44) parts))
  printLn (BS.length (toByteString (foldl (\acc, p => acc <+> byteString p) neutral parts)))
  printLn (BS.take 8 (BS.reverse (BS.drop 1 (BS.map (+ 1) big))))
  printLn (BS.toHex (BS.take 4 (BS.drop 10 big)))
