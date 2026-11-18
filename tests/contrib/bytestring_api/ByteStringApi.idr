import Data.ByteString as BS
import Data.List
import Data.List1
import Data.Maybe
import Data.Fin

%default total
%ambiguity_depth 10

-- Print a name and a result, to compare with the expected output.
t : Show a => String -> a -> IO ()
t name v = putStrLn (name ++ ": " ++ show v)

-- A check that prints only on failure, so that a pass is a line "ok".
ck : String -> Bool -> IO ()
ck name b = putStrLn (name ++ ": " ++ (if b then "ok" else "FAILED"))

hi : ByteString
hi = BS.pack [104, 101, 108, 108, 111]  -- hello

high : ByteString
high = BS.pack [0, 1, 127, 128, 200, 255]

-- [0, 1, .. 255, 0, 1 ..] of the given length, without using stack.
counting : Nat -> List Bits8
counting n = go n []
  where
    go : Nat -> List Bits8 -> List Bits8
    go Z acc = acc
    go (S k) acc = go k (cast k :: acc)

covering
main : IO ()
main = do
  putStrLn "-- construction"
  t "empty" BS.empty
  t "singleton" (BS.singleton 65)
  t "pack" hi
  t "unpack" (BS.unpack hi)
  t "unpack high" (BS.unpack high)
  t "show high" high
  t "show escapes" (BS.pack [34, 92, 10, 9, 13, 7, 0, 127, 200, 50, 0x53, 0x4f, 0x48])
  t "literal" (the ByteString "héllo")
  t "length" (BS.length hi, BS.length BS.empty, BS.length high)
  t "null" (BS.null BS.empty, BS.null hi)
  t "replicate" (BS.replicate 4 0xAB, BS.replicate 0 1)

  putStrLn "-- indexing"
  t "index" (map (\i => BS.index i hi) [0, 1, 4, 5, 100])
  t "index high" (BS.index 3 high, BS.index 5 high)
  t "index'" (map (BS.index' hi) (natToFin 2 (BS.length hi)), map (BS.index' hi) (natToFin 5 (BS.length hi)))
  t "head/last" (BS.head hi, BS.last hi, BS.head BS.empty, BS.last BS.empty)
  t "tail/init" (BS.tail hi, BS.init hi, BS.tail BS.empty, BS.init BS.empty)
  t "tail single" (BS.tail (BS.singleton 1), BS.init (BS.singleton 1))
  t "uncons" (BS.uncons hi, BS.uncons BS.empty)
  t "unsnoc" (BS.unsnoc hi, BS.unsnoc BS.empty)

  putStrLn "-- slicing"
  t "take" (map (\n => BS.take n hi) [0, 2, 5, 6, 1000])
  t "drop" (map (\n => BS.drop n hi) [0, 2, 5, 6, 1000])
  t "takeEnd" (map (\n => BS.takeEnd n hi) [0, 2, 5, 6, 1000])
  t "dropEnd" (map (\n => BS.dropEnd n hi) [0, 2, 5, 6, 1000])
  t "huge" (BS.take 0xFFFFFFFFFFFFFFFFFFFF hi, BS.drop 0xFFFFFFFFFFFFFFFFFFFF hi)
  t "splitAt" (map (\n => BS.splitAt n hi) [0, 3, 5, 9])
  let s1 = BS.drop 1 (BS.take 4 hi)   -- "ell"
  let s2 = BS.drop 1 (BS.take 2 s1)   -- "l"
  t "slice of slice" (s1, s2, BS.take 5 s1, BS.drop 1 s2)
  t "slices of slices ops" (BS.unpack s1, BS.reverse s1, BS.length s1, BS.index 2 s1, BS.index 3 s1)
  t "copy" (BS.copy s1, BS.copy s1 == s1, BS.copy BS.empty)
  t "tail of slice" (BS.tail s1, BS.init s1, BS.uncons s1, BS.unsnoc s1)

  putStrLn "-- takeWhile and friends"
  let digits = BS.pack (map (\c => cast (ord c)) (unpack "123abc456"))
  let isDigit : Bits8 -> Bool
      isDigit w = w >= 48 && w <= 57
  t "takeWhile" (BS.takeWhile isDigit digits, BS.takeWhile isDigit BS.empty)
  t "dropWhile" (BS.dropWhile isDigit digits, BS.dropWhile (const True) digits)
  t "span" (BS.span isDigit digits, BS.span (const False) digits)
  t "break" (BS.break (not . isDigit) digits, BS.break (const False) digits)

  putStrLn "-- combining"
  t "append" (hi <+> BS.singleton 33, BS.append BS.empty hi, BS.append hi BS.empty)
  t "<+> slices" (BS.take 2 hi <+> BS.drop 3 hi)
  t "concat" (BS.concat [hi, BS.empty, BS.singleton 32, high, BS.empty])
  t "concat empty" (BS.concat [], BS.concat [BS.empty, BS.empty])
  t "intercalate" (BS.intercalate (BS.singleton 44) [BS.take 1 hi, BS.drop 4 hi, BS.empty])
  t "monoid concat" (Prelude.concat [hi, hi], hi <+> neutral, the ByteString neutral)
  t "cons/snoc" (BS.cons 255 hi, BS.snoc hi 0, BS.cons 1 BS.empty, BS.snoc BS.empty 2)
  t "reverse" (BS.reverse hi, BS.reverse BS.empty, BS.reverse high)
  t "map" (BS.map (+ 1) high, BS.map id BS.empty)

  putStrLn "-- folds and searches"
  t "foldl" (BS.foldl (\a, w => a * 31 + cast w) (the Integer 7) hi)
  t "foldr" (BS.foldr (\w, a => cast w :: a) (the (List Integer) []) high)
  t "foldl order" (BS.foldl (\a, w => w :: a) [] (BS.pack [1, 2, 3]))
  t "foldr order" (BS.foldr (\w, a => w :: a) [] (BS.pack [1, 2, 3]))
  t "any/all" (BS.any (> 200) high, BS.any (> 255) high, BS.all (const True) high,
               BS.all (< 255) high, BS.any (const True) BS.empty, BS.all (const False) BS.empty)
  t "elem" (BS.elem 200 high, BS.elem 201 high, BS.notElem 201 high, BS.elem 0 BS.empty)
  t "findIndex" (BS.findIndex (> 127) high, BS.findIndex (> 255) high)
  t "elemIndex" (BS.elemIndex 108 hi, BS.elemIndex 1 hi)
  t "isPrefixOf" (BS.isPrefixOf (BS.take 2 hi) hi, BS.isPrefixOf hi hi, BS.isPrefixOf BS.empty hi,
                  BS.isPrefixOf hi (BS.take 2 hi), BS.isPrefixOf (BS.singleton 1) hi)
  t "isSuffixOf" (BS.isSuffixOf (BS.drop 3 hi) hi, BS.isSuffixOf hi hi, BS.isSuffixOf BS.empty hi,
                  BS.isSuffixOf hi (BS.drop 3 hi), BS.isSuffixOf (BS.singleton 1) hi)
  t "isInfixOf" (BS.isInfixOf (BS.take 3 (BS.drop 1 hi)) hi, BS.isInfixOf BS.empty hi,
                 BS.isInfixOf BS.empty BS.empty, BS.isInfixOf hi hi, BS.isInfixOf (hi <+> hi) hi,
                 BS.isInfixOf (BS.pack [108, 111]) hi, BS.isInfixOf (BS.pack [108, 108, 108]) hi)
  t "isInfixOf bytes>=0x80" (BS.isInfixOf (BS.pack [200, 255]) high, BS.isInfixOf (BS.pack [255, 200]) high)

  putStrLn "-- split"
  let sp : Bits8 -> ByteString -> List ByteString
      sp w b = forget (BS.split w b)
  t "split" (sp 44 (BS.pack [97, 44, 98, 44, 44, 99]))
  t "split none" (sp 44 hi)
  t "split empty" (sp 44 BS.empty)
  t "split only" (sp 44 (BS.pack [44]), sp 44 (BS.pack [44, 44]))
  t "split ends" (sp 44 (BS.pack [44, 97, 44]))
  t "split high" (sp 200 high)
  t "splitWith" (forget (BS.splitWith (> 100) high))
  t "split concat" (BS.intercalate (BS.singleton 44) (sp 44 (BS.pack [97, 44, 98, 44, 44, 99])))

  putStrLn "-- integers"
  let ints = BS.pack [1, 2, 3, 4, 5, 6, 7, 8, 0xFF, 0xFE]
  t "u16" (BS.indexBits16LE 0 ints, BS.indexBits16BE 0 ints)
  t "u32" (BS.indexBits32LE 1 ints, BS.indexBits32BE 1 ints)
  t "u64" (BS.indexBits64LE 0 ints, BS.indexBits64BE 0 ints)
  t "u64 high" (BS.indexBits64LE 2 ints, BS.indexBits64BE 2 ints)
  t "u16 high" (BS.indexBits16LE 8 ints, BS.indexBits16BE 8 ints)
  t "u32 all ff" (BS.indexBits32LE 0 (BS.replicate 4 255), BS.indexBits32BE 0 (BS.replicate 4 255))
  t "u64 all ff" (BS.indexBits64LE 0 (BS.replicate 8 255), BS.indexBits64BE 0 (BS.replicate 8 255))
  t "out of range" (BS.indexBits16LE 9 ints, BS.indexBits16BE 10 ints, BS.indexBits32LE 7 ints,
                    BS.indexBits64BE 3 ints, BS.indexBits16LE 100000 ints)
  t "ints of slice" (BS.indexBits16LE 0 (BS.drop 3 ints), BS.indexBits32BE 0 (BS.drop 3 ints))
  t "ints of empty" (BS.indexBits16LE 0 BS.empty, BS.indexBits64LE 0 BS.empty)

  putStrLn "-- Eq, Ord"
  ck "eq" (hi == BS.pack [104, 101, 108, 108, 111])
  ck "eq slice" (BS.take 2 (BS.drop 1 hi) == BS.pack [101, 108])
  ck "neq length" (hi /= BS.take 4 hi)
  ck "neq byte" (BS.pack [1, 2] /= BS.pack [1, 3])
  ck "eq empty" (BS.empty == BS.drop 5 hi)
  ck "lt prefix" (BS.take 2 hi < hi)
  ck "lt empty" (BS.empty < hi)
  ck "lt unsigned" (BS.pack [127] < BS.pack [128])
  ck "gt unsigned" (BS.pack [255, 0] > BS.pack [1, 255, 255])
  ck "compare eq" (compare hi hi == EQ)
  ck "compare empty" (compare BS.empty BS.empty == EQ)
  ck "sort" (sort [BS.pack [2], BS.pack [1, 9], BS.empty, BS.pack [1], BS.pack [200], BS.pack [1, 9, 0]]
             == [BS.empty, BS.pack [1], BS.pack [1, 9], BS.pack [1, 9, 0], BS.pack [2], BS.pack [200]])
  t "show sort" (sort [BS.pack [2], BS.pack [1, 9], BS.empty, BS.pack [200]])

  putStrLn "-- UTF-8"
  t "fromString ascii" (BS.fromString "abc")
  t "fromString empty" (BS.fromString "")
  t "fromString 2-4 bytes" (BS.unpack (BS.fromString "é€😀"))
  t "toString" (BS.toString (BS.fromString "é€😀 plain"))
  t "toString empty" (BS.toString BS.empty)
  let edges : String
      edges = pack (map chr [0x7f, 0x80, 0x7ff, 0x800, 0xffff, 0x10000, 0x10ffff])
  t "edge code points" (BS.unpack (BS.fromString edges))
  t "roundtrip" (map (\s => BS.toString (BS.fromString s) == Just s) ["", "a", "héllo wörld", "日本語", "😀😀", edges])
  t "length utf8" (BS.length (BS.fromString "é€😀"))
  t "valid" (map (BS.isValidUtf8 . BS.pack) [[], [0x41], [0xC3, 0xA9], [0xE2, 0x82, 0xAC], [0xF0, 0x9F, 0x98, 0x80],
                                              [0xF4, 0x8F, 0xBF, 0xBF], [0xED, 0x9F, 0xBF], [0xEE, 0x80, 0x80], [0x00]])
  let bad : List (List Bits8)
      bad = [ [0x80]                      -- stray continuation
            , [0xBF]
            , [0xC0, 0x80]                -- overlong NUL
            , [0xC1, 0xBF]                -- overlong
            , [0xC3]                      -- truncated 2
            , [0xC3, 0x28]                -- bad continuation
            , [0xE2, 0x82]                -- truncated 3
            , [0xE2, 0x28, 0xA1]
            , [0xE0, 0x80, 0x80]          -- overlong 3
            , [0xE0, 0x9F, 0xBF]
            , [0xED, 0xA0, 0x80]          -- surrogate D800
            , [0xED, 0xBF, 0xBF]          -- surrogate DFFF
            , [0xF0, 0x80, 0x80, 0x80]    -- overlong 4
            , [0xF0, 0x8F, 0xBF, 0xBF]
            , [0xF4, 0x90, 0x80, 0x80]    -- above 10FFFF
            , [0xF5, 0x80, 0x80, 0x80]
            , [0xF8, 0x88, 0x80, 0x80, 0x80]
            , [0xFF]
            , [0xFE]
            , [0x41, 0xFF, 0x42]
            , [0xF0, 0x9F, 0x98]          -- truncated 4
            ]
  t "invalid" (map (BS.toString . BS.pack) bad)
  t "invalid valid?" (map (BS.isValidUtf8 . BS.pack) bad)
  t "lossy" (map (map ord . unpack . BS.toStringLossy . BS.pack)
                 [[0x41, 0xFF, 0x42], [0xE2, 0x82], [0xC3, 0xA9, 0x80], [0xF0, 0x9F, 0x98, 0x80], [0xED, 0xA0, 0x80]])
  t "invalid in slice" (BS.toString (BS.take 2 (BS.fromString "é€")), BS.toString (BS.take 4 (BS.fromString "é€")), BS.toString (BS.drop 1 (BS.fromString "é€")))

  putStrLn "-- hex"
  t "toHex" (BS.toHex high, BS.toHex BS.empty, BS.toHex (BS.drop 3 high))
  t "fromHex" (BS.fromHex "00017f80c8ff", BS.fromHex "00017F80C8FF", BS.fromHex "")
  let badHex : List String
      badHex = ["0", "abc", "zz", "0g", "0x", " 0"]
  t "fromHex bad" (map BS.fromHex badHex)
  ck "hex roundtrip" (BS.fromHex (BS.toHex high) == Just high)

  putStrLn "-- big"
  let big = BS.pack (counting 100000)
  t "big length" (BS.length big)
  t "big fold" (BS.foldl (\a, w => a + cast w) (the Integer 0) big)
  t "big roundtrip" (length (BS.unpack big), BS.unpack big == counting 100000)
  t "big reverse" (BS.take 3 (BS.reverse big), BS.index 99999 (BS.reverse big))
  t "big concat" (BS.length (BS.concat (List.replicate 10000 hi)))
  t "big eq" (big == BS.copy big, BS.copy big == BS.snoc (BS.take 99999 big) 0)
  t "big split" (length (forget (BS.split 0 big)), length (forget (BS.split 255 big)))
  t "big hex" (BS.length (BS.fromString (BS.toHex big)), BS.fromHex (BS.toHex big) == Just big)
  let eacutes = BS.fromString (pack (List.replicate 50000 'é'))
  t "big utf8" (BS.length eacutes, map length (BS.toString eacutes))
