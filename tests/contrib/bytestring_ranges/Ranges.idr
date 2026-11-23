-- The operations on ranges of bytes of Data.ByteString.Internal (compare,
-- search, hash) and the functions of Data.ByteString written with them, at
-- the boundaries: empty ranges, slices at an offset, the last byte.
import Data.Bits
import Data.Buffer
import Data.ByteString as BS
import Data.ByteString.Internal
import Data.Hashable
import Data.List
import Data.List1

%default total

-- The hash as it was computed before, one byte at a time.
refHash : Bits64 -> ByteString -> Bits64
refHash s bs = fnvFinish (fnvStep (go (BS.unpack bs) (fnvStart s))
                                  (prim__and_Int (lengthInt bs) 0x7fffffff))
  where
    go : List Bits8 -> Int -> Int
    go [] h = h
    go (w :: ws) h = go ws (fnvStep h (cast w))

-- The order as it was computed before, from the lists of bytes.
refCompare : ByteString -> ByteString -> Ordering
refCompare x y = compare (BS.unpack x) (BS.unpack y)

-- `isInfixOf` from the lists of bytes.
refInfix : ByteString -> ByteString -> Bool
refInfix p bs = isInfixOf (BS.unpack p) (BS.unpack bs)

main : IO ()
main = do
  -- the slice [2, 8) of a buffer of 10 bytes: the bytes around it must not
  -- be seen
  let whole = pack [9, 9, 1, 2, 3, 0xFF, 2, 7, 9, 9]
      s = BS.take 6 (BS.drop 2 whole)
      t = pack [1, 2, 3, 0xFF, 2, 7]
      u = pack [1, 2, 3, 0xFF, 2, 8]
      e1 = BS.take 0 (BS.drop 5 whole)
  putStrLn "-- compare"
  printLn (unsafeOffset s, lengthInt s)
  printLn (unsafeCompareRange (unsafeBuffer s) (unsafeOffset s) (unsafeBuffer t) 0 6)
  printLn (unsafeCompareRange (unsafeBuffer s) (unsafeOffset s) (unsafeBuffer u) 0 6)
  printLn (unsafeCompareRange (unsafeBuffer u) 0 (unsafeBuffer s) (unsafeOffset s) 6)
  printLn (unsafeCompareRange (unsafeBuffer u) 6 (unsafeBuffer s) 10 0)
  printLn [s == t, s == u, t == s, s == e1, e1 == BS.empty, BS.empty == BS.empty]
  let cases = [s, t, u, e1, BS.empty, pack [1], pack [0xFF], pack [1, 2, 3], BS.drop 1 s, BS.take 5 s]
  printLn [compare x y | x <- cases, y <- cases]
  printLn ([compare x y | x <- cases, y <- cases] == [refCompare x y | x <- cases, y <- cases])
  printLn ([x == y | x <- cases, y <- cases] == [BS.unpack x == BS.unpack y | x <- cases, y <- cases])
  putStrLn "-- search"
  printLn (findByteFrom 9 0 s, findByteFrom 1 0 s, findByteFrom 7 0 s, findByteFrom 2 0 s)
  printLn (findByteFrom 2 2 s, findByteFrom 2 5 s, findByteFrom 7 5 s, findByteFrom 7 6 s)
  printLn (findByteFrom 1 (-3) s, findByteFrom 1 100 s, findByteFrom 1 0 e1, findByteFrom 0 0 BS.empty)
  printLn [BS.elem 9 s, BS.elem 7 s, BS.notElem 0xFF s, BS.elem 0 e1]
  printLn [BS.elemIndex 0xFF s, BS.elemIndex 9 s, BS.elemIndex 7 s]
  printLn (map BS.unpack (forget (BS.split 2 s)))
  printLn (map BS.unpack (forget (BS.split 2 e1)))
  printLn (map BS.unpack (forget (BS.split 7 s)), map BS.unpack (forget (BS.split 1 s)))
  printLn (map BS.unpack (forget (BS.split 2 s)) == map BS.unpack (forget (BS.splitWith (== 2) s)))
  putStrLn "-- prefixes and infixes"
  printLn [BS.isPrefixOf (pack [1, 2]) s, BS.isPrefixOf (pack [9, 1]) s, BS.isPrefixOf e1 s, BS.isPrefixOf s s]
  printLn [BS.isSuffixOf (pack [2, 7]) s, BS.isSuffixOf (pack [7, 9]) s, BS.isSuffixOf e1 e1, BS.isSuffixOf t s]
  let hay = pack [1, 1, 1, 2, 1, 1, 2, 3]
      needles = [pack [1, 1, 2], pack [1, 2, 3], pack [2, 3], pack [3], pack [3, 4], pack [1, 1, 1, 1],
                 BS.empty, hay, pack [2, 1, 1], pack [9, 1], pack [7, 9]]
  printLn (map (\p => BS.isInfixOf p hay) needles)
  printLn (map (\p => BS.isInfixOf p hay) needles == map (\p => refInfix p hay) needles)
  printLn (map (\p => BS.isInfixOf p s) needles == map (\p => refInfix p s) needles)
  printLn [BS.isInfixOf (pack [9]) s, BS.isInfixOf (pack [7]) s, BS.isInfixOf e1 BS.empty]
  putStrLn "-- hash"
  let salts = [0, 1, 0x7fffffff, 0x80000000, 0xFFFFFFFFFFFFFFFF, 12345678901234567]
      hcases = cases ++ [BS.replicate 300 0, BS.replicate 3 0, whole, BS.drop 9 whole]
  printLn (map hash hcases)
  printLn (all id [hashWithSalt k x == refHash k x | k <- salts, x <- hcases])
  printLn (hash s == hash t, hash s == hash (BS.copy s))
  putStrLn "-- words and folds"
  printLn [unsafeIndexWord32LE s 0 == 0xFF030201, unsafeIndexWord32LE s 2 == 0x0702FF03]
  printLn [BS.indexBits32LE 2 s, BS.indexBits32LE 3 s, BS.indexBits32BE 2 s]
  printLn (BS.indexBits16LE 4 s, BS.indexBits16LE 5 s)
  printLn (BS.unpack s, BS.foldr (::) [] s)
  printLn [BS.foldl (\a, w => a * 3 + cast {to = Int} w) 0 s, BS.foldl (\a, w => a + cast {to = Int} w) 0 e1]
  printLn (BS.unpack e1, BS.foldr (::) [] e1)
  printLn [BS.isValidUtf8 s, BS.isValidUtf8 (BS.take 3 s), BS.isValidUtf8 e1]
  printLn (BS.toString (pack [0x61, 0xC3, 0xA9]))
  printLn (BS.findIndex (== 3) s, BS.findIndex (== 9) s)
  printLn (BS.unpack (BS.takeWhile (< 3) s), BS.unpack (BS.dropWhile (< 3) s))
