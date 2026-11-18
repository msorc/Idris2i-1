import Data.ByteString as BS
import Data.Hashable
import Data.HashMap as HashMap
import Data.HashSet as HashSet
import Data.List
import Data.Maybe

%default total

-- A check that prints only "ok" or "FAILED", so that a pass is a line "ok".
ck : String -> Bool -> IO ()
ck name b = putStrLn (name ++ ": " ++ (if b then "ok" else "FAILED"))

-- [0, 1, .. 255, 0, 1 ..] of the given length, without using stack.
counting : Nat -> List Bits8
counting n = go n []
  where
    go : Nat -> List Bits8 -> List Bits8
    go Z acc = acc
    go (S k) acc = go k (cast k :: acc)

abc : ByteString
abc = BS.pack [97, 98, 99]

-- The same three bytes as slices of other buffers, at other offsets.
abcSlices : List ByteString
abcSlices =
  [ abc
  , BS.copy abc
  , BS.drop 3 (BS.pack [1, 2, 3, 97, 98, 99])
  , BS.take 3 (BS.pack [97, 98, 99, 4, 5, 6, 7])
  , BS.take 3 (BS.drop 2 (BS.pack [0, 0, 97, 98, 99, 0, 0]))
  , BS.fromString "abc"
  , BS.pack [97] <+> BS.pack [98, 99]
  , BS.concat [BS.singleton 97, BS.singleton 98, BS.singleton 99]
  ]

covering
main : IO ()
main = do
  putStrLn "-- hashes (the same on every back end)"
  putStrLn (show (hash BS.empty))
  putStrLn (show (hash (BS.singleton 0)))
  putStrLn (show (hash abc))
  putStrLn (show (hashWithSalt 12345 abc))
  putStrLn (show (hash (BS.pack [0, 1, 127, 128, 200, 255])))
  putStrLn (show (hash (BS.pack (counting 1000))))

  putStrLn "-- equal byte strings"
  ck "slices are ==" (all (== abc) abcSlices)
  ck "slices hash alike" (all (\s => hash s == hash abc) abcSlices)
  ck "slices hash alike with a salt"
     (all (\s => hashWithSalt 987654321 s == hashWithSalt 987654321 abc) abcSlices)
  ck "empty slices" (all (\s => hash s == hash BS.empty)
                         [BS.take 0 abc, BS.drop 3 abc, BS.copy (BS.drop 2 (BS.take 2 abc)), BS.pack []])
  let big = BS.pack (counting 100000)
  ck "big slices" (hash (BS.drop 5 big) == hash (BS.copy (BS.drop 5 big)))
  ck "big take" (hash (BS.take 70000 big) == hash (BS.pack (counting 70000)))

  putStrLn "-- different byte strings"
  let others = [BS.empty, BS.singleton 0, BS.singleton 97, BS.pack [97, 98], BS.pack [98, 97],
                BS.pack [97, 98, 99, 0], BS.pack [0, 97, 98, 99], BS.pack [255], BS.pack [0, 0], BS.pack [0, 0, 0], BS.replicate 100 0, BS.replicate 101 0]
  ck "different hashes" (length (nub (map hash others)) == length others)
  ck "different salts" (hashWithSalt 1 abc /= hashWithSalt 2 abc)
  ck "31 bits" (all (\s => hash s < 2147483648) (abc :: others))

  putStrLn "-- hash maps"
  let keys = [ (BS.pack (counting k), k) | k <- [0 .. 300] ]
      m = HashMap.fromList keys
  putStrLn (show (HashMap.size m))
  ck "lookup" (all (\(k, v) => HashMap.lookup k m == Just v) keys)
  ck "lookup by slice"
     (all (\(k, v) => HashMap.lookup (BS.drop 1 (BS.cons 255 k)) m == Just v) keys)
  ck "lookup missing" (HashMap.lookup (BS.pack [1, 2, 3]) m == Nothing)
  let m2 = HashMap.insert (BS.copy abc) "copy" (HashMap.insert (BS.drop 3 (BS.pack [1, 2, 3, 97, 98, 99])) "slice" HashMap.empty)
  putStrLn (show (HashMap.toList m2))
  ck "one entry for equal keys" (HashMap.size m2 == 1 && HashMap.lookup abc m2 == Just "copy")
  let m3 = foldl (\acc, s => HashMap.delete s acc) m (map fst (take 100 keys))
  putStrLn (show (HashMap.size m3))
  ck "deleted" (all (\(k, _) => not (HashMap.member k m3)) (take 100 keys))
  let wordsOf = map BS.fromString ["the", "quick", "brown", "fox", "jumps", "over", "the", "lazy", "dog", "the", "end"]
      counts = HashMap.fromListWith (+) (map (\w => (w, the Nat 1)) wordsOf)
  putStrLn (show (sortBy (\a, b => compare (fst a) (fst b)) (HashMap.toList counts)))
  let s = HashSet.fromList wordsOf
  putStrLn (show (HashSet.size s, HashSet.contains (BS.fromString "fox") s, HashSet.contains (BS.fromString "cat") s))
