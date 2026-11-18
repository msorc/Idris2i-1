||| Immutable sequences of bytes.
|||
||| A `ByteString` is a slice (buffer, offset, length) of a `Data.Buffer.Buffer`
||| that is never written after it has been filled.  Slicing (`take`, `drop`,
||| `splitAt`, `span`, `split`...) therefore takes constant time and shares the
||| storage of the original; use `copy` to release a large parent buffer that
||| a small slice keeps alive.
|||
||| The names follow `Data.List` and `Data.String`, and many of them clash
||| with those of the `Prelude`, so import the module qualified:
|||
||| ```idris
||| import Data.ByteString as BS
|||
||| greeting : ByteString
||| greeting = BS.pack [72, 105] <+> BS.singleton 33
||| ```
|||
||| Indices and lengths are `Nat`; out-of-range arguments never fail: `take`
||| and `drop` clamp, and `index` and the integer readers return `Nothing`.
|||
||| The unsafe construction code is in `Data.ByteString.Internal` and is
||| small; everything below is ordinary total code on top of it.
module Data.ByteString

import public Data.ByteString.Types
import Data.ByteString.Internal
import Data.Bits
import Data.Buffer
import Data.Fin
import Data.List
import Data.List1
import Data.String

%default total

--------------------------------------------------------------------------
-- Helpers (not exported)
--------------------------------------------------------------------------

-- The number of steps of a loop over `n` elements, so that loops are
-- structurally recursive on a `Nat`.
fuel : Int -> Nat
fuel n = cast n

-- `n` as an `Int` no bigger than the length of `bs`.
clampTo : Nat -> ByteString -> Int
clampTo n bs = if n >= cast (lengthInt bs) then lengthInt bs else cast n

-- The sum of a function of the elements of a list (without using stack).
sumOver : (a -> Int) -> List a -> Int
sumOver f xs = go xs 0
  where
    go : List a -> Int -> Int
    go [] acc = acc
    go (y :: ys) acc = go ys (acc + f y)

-- The first index at which the predicate holds.
firstIndex : (Bits8 -> Bool) -> ByteString -> Maybe Int
firstIndex p bs = go (fuel (lengthInt bs)) 0
  where
    go : Nat -> Int -> Maybe Int
    go Z _ = Nothing
    go (S k) i = if p (unsafeIndex bs i) then Just i else go k (i + 1)

-- Do the `lengthInt pat` bytes of `pat` equal those of `bs` from `at`?
-- Precondition: they are within `bs`.
matchesAt : (pat : ByteString) -> (bs : ByteString) -> (at : Int) -> Bool
matchesAt pat bs at = go (fuel (lengthInt pat)) 0
  where
    go : Nat -> Int -> Bool
    go Z _ = True
    go (S k) i = if unsafeIndex pat i == unsafeIndex bs (at + i)
                    then go k (i + 1)
                    else False

--------------------------------------------------------------------------
-- Construction and conversion to and from lists
--------------------------------------------------------------------------

||| The byte string of length 0.
export
empty : ByteString
empty = unsafeCreate 0 (\_ => pure ())

||| A byte string of one byte.
export
singleton : Bits8 -> ByteString
singleton w = unsafeCreate 1 (\b => setBits8 b 0 w)

||| A byte string with the bytes of a list.  Linear in the length of the list.
export
pack : List Bits8 -> ByteString
pack xs = unsafeCreate (cast (List.length xs)) $ \b =>
            ioForList xs 0 $ \i, w =>
              do setBits8 b i w
                 pure (i + 1)

||| The bytes of a byte string as a list.  Linear, and does not use stack
||| space.
export
unpack : ByteString -> List Bits8
unpack bs = go (fuel (lengthInt bs)) (lengthInt bs - 1) []
  where
    go : Nat -> Int -> List Bits8 -> List Bits8
    go Z _ acc = acc
    go (S k) i acc = go k (i - 1) (unsafeIndex bs i :: acc)

||| `replicate n w` has `n` bytes, all equal to `w`.
export
replicate : Nat -> Bits8 -> ByteString
replicate n w = unsafeCreate (cast n) (\b => ioForRange 0 (cast n) (\i => setBits8 b i w))

||| A copy of a byte string that owns its storage.  A slice keeps all of the
||| buffer that it was cut from alive; copying a small slice of a large buffer
||| lets the large buffer be freed.  Linear in the length.
export
copy : ByteString -> ByteString
copy bs = unsafeCreate (lengthInt bs) (\b => unsafeCopyTo bs b 0)

--------------------------------------------------------------------------
-- Size and indexing
--------------------------------------------------------------------------

||| The number of bytes.  Constant time.
export
length : ByteString -> Nat
length bs = cast (lengthInt bs)

||| Is the byte string empty?
export
null : ByteString -> Bool
null bs = lengthInt bs == 0

||| The byte at an index (counting from 0), or `Nothing` if the index is not
||| less than the length.  Constant time.
export
index : Nat -> ByteString -> Maybe Bits8
index n bs = if n < length bs then Just (unsafeIndex bs (cast n)) else Nothing

||| The byte at an index that is known to be in range.  Constant time.
export
index' : (bs : ByteString) -> Fin (length bs) -> Bits8
index' bs i = unsafeIndex bs (cast (finToNat i))

||| The first byte, if there is one.  Constant time.
export
head : ByteString -> Maybe Bits8
head bs = if null bs then Nothing else Just (unsafeIndex bs 0)

||| The last byte, if there is one.  Constant time.
export
last : ByteString -> Maybe Bits8
last bs = if null bs then Nothing else Just (unsafeIndex bs (lengthInt bs - 1))

||| All but the first byte; the empty byte string if it is empty.  Constant
||| time.
export
tail : ByteString -> ByteString
tail bs = if null bs then bs else unsafeSlice 1 (lengthInt bs - 1) bs

||| All but the last byte; the empty byte string if it is empty.  Constant
||| time.
export
init : ByteString -> ByteString
init bs = if null bs then bs else unsafeSlice 0 (lengthInt bs - 1) bs

||| The first byte and the rest, if it is not empty.  Constant time.
export
uncons : ByteString -> Maybe (Bits8, ByteString)
uncons bs = if null bs then Nothing else Just (unsafeIndex bs 0, tail bs)

||| The all but last bytes and the last byte, if it is not empty.  Constant
||| time.
export
unsnoc : ByteString -> Maybe (ByteString, Bits8)
unsnoc bs = if null bs then Nothing
               else Just (init bs, unsafeIndex bs (lengthInt bs - 1))

--------------------------------------------------------------------------
-- Slicing (all constant time, all share the storage)
--------------------------------------------------------------------------

||| The first `n` bytes, or all of them if there are fewer.  Constant time;
||| shares storage.
export
take : Nat -> ByteString -> ByteString
take n bs = unsafeSlice 0 (clampTo n bs) bs

||| All but the first `n` bytes, or nothing if there are fewer.  Constant
||| time; shares storage.
export
drop : Nat -> ByteString -> ByteString
drop n bs = let k = clampTo n bs in unsafeSlice k (lengthInt bs - k) bs

||| The last `n` bytes, or all of them if there are fewer.  Constant time;
||| shares storage.
export
takeEnd : Nat -> ByteString -> ByteString
takeEnd n bs = let k = clampTo n bs in unsafeSlice (lengthInt bs - k) k bs

||| All but the last `n` bytes, or nothing if there are fewer.  Constant
||| time; shares storage.
export
dropEnd : Nat -> ByteString -> ByteString
dropEnd n bs = unsafeSlice 0 (lengthInt bs - clampTo n bs) bs

||| `(take n bs, drop n bs)`.  Constant time; shares storage.
export
splitAt : Nat -> ByteString -> (ByteString, ByteString)
splitAt n bs = (take n bs, drop n bs)

||| The longest prefix of bytes that satisfy the predicate.  Linear in
||| the length of the result; shares storage.
export
takeWhile : (Bits8 -> Bool) -> ByteString -> ByteString
takeWhile p bs = unsafeSlice 0 (fromMaybe (lengthInt bs) (firstIndex (not . p) bs)) bs

||| What remains after `takeWhile`.  Linear in the length of the prefix
||| that is dropped; shares storage.
export
dropWhile : (Bits8 -> Bool) -> ByteString -> ByteString
dropWhile p bs = let k = fromMaybe (lengthInt bs) (firstIndex (not . p) bs)
                 in unsafeSlice k (lengthInt bs - k) bs

||| `(takeWhile p bs, dropWhile p bs)`, with one pass.  Shares storage.
export
span : (Bits8 -> Bool) -> ByteString -> (ByteString, ByteString)
span p bs = let k = fromMaybe (lengthInt bs) (firstIndex (not . p) bs)
            in (unsafeSlice 0 k bs, unsafeSlice k (lengthInt bs - k) bs)

||| `span (not . p)`: split before the first byte that satisfies the
||| predicate.  Shares storage.
export
break : (Bits8 -> Bool) -> ByteString -> (ByteString, ByteString)
break p = span (not . p)

||| Split at the bytes that satisfy a predicate, which are dropped.  The
||| result always has at least one element: splitting the empty byte
||| string gives one empty piece, and `n` separators give `n + 1` pieces
||| (some of them possibly empty).  Linear; the pieces share storage.
export
splitWith : (Bits8 -> Bool) -> ByteString -> List1 ByteString
splitWith p bs = go (fuel (lengthInt bs)) 0 0 []
  where
    -- The pieces come in reverse order.
    finish : List ByteString -> List1 ByteString
    finish rev = case reverse rev of
                      [] => empty ::: []
                      (x :: xs) => x ::: xs

    -- `start` is where the current piece starts, `i` the next index to look at.
    go : Nat -> (start : Int) -> (i : Int) -> List ByteString -> List1 ByteString
    go Z start _ acc = finish (unsafeSlice start (lengthInt bs - start) bs :: acc)
    go (S k) start i acc =
      if p (unsafeIndex bs i)
         then go k (i + 1) (i + 1) (unsafeSlice start (i - start) bs :: acc)
         else go k start (i + 1) acc

||| Split at the occurrences of a byte, which are dropped:
||| `split 44 "a,b,,c"` is `["a", "b", "", "c"]`.  See `splitWith`.
export
split : Bits8 -> ByteString -> List1 ByteString
split w = splitWith (== w)

--------------------------------------------------------------------------
-- Combining
--------------------------------------------------------------------------

||| The concatenation of a list of byte strings, with one allocation of the
||| total size.  Linear in the total length.
export
concat : List ByteString -> ByteString
concat bss = unsafeCreate (sumOver lengthInt bss) $ \b =>
               ioForList bss 0 $ \at, x =>
                 do unsafeCopyTo x b at
                    pure (at + lengthInt x)

||| The concatenation of two byte strings.  Linear in the total length (it
||| returns an argument unchanged if the other is empty).
export
append : ByteString -> ByteString -> ByteString
append x y = if null x then y
             else if null y then x
             else unsafeCreate (lengthInt x + lengthInt y) $ \b =>
                    do unsafeCopyTo x b 0
                       unsafeCopyTo y b (lengthInt x)

||| Put the byte string between the elements of a list and concatenate.
export
intercalate : ByteString -> List ByteString -> ByteString
intercalate sep = concat . intersperse sep

||| Add a byte at the front.  Linear.
export
cons : Bits8 -> ByteString -> ByteString
cons w bs = unsafeCreate (lengthInt bs + 1) $ \b =>
              do setBits8 b 0 w
                 unsafeCopyTo bs b 1

||| Add a byte at the end.  Linear.
export
snoc : ByteString -> Bits8 -> ByteString
snoc bs w = unsafeCreate (lengthInt bs + 1) $ \b =>
              do unsafeCopyTo bs b 0
                 setBits8 b (lengthInt bs) w

||| The bytes in the opposite order.  Linear.
export
reverse : ByteString -> ByteString
reverse bs = let n = lengthInt bs in
  unsafeCreate n (\b => ioForRange 0 n (\i => setBits8 b i (unsafeIndex bs (n - 1 - i))))

||| Apply a function to every byte.  Linear.
export
map : (Bits8 -> Bits8) -> ByteString -> ByteString
map f bs = unsafeCreate (lengthInt bs) $ \b =>
             ioForRange 0 (lengthInt bs) (\i => setBits8 b i (f (unsafeIndex bs i)))

--------------------------------------------------------------------------
-- Folds and searches
--------------------------------------------------------------------------

||| Fold from the left (the first byte is combined first).  Linear, and does
||| not use stack space.
export
foldl : (acc -> Bits8 -> acc) -> acc -> ByteString -> acc
foldl f z bs = go (fuel (lengthInt bs)) 0 z
  where
    go : Nat -> Int -> acc -> acc
    go Z _ a = a
    go (S k) i a = go k (i + 1) (f a (unsafeIndex bs i))

||| Fold from the right (the last byte is combined first).  Linear, and does
||| not use stack space: it visits the bytes from the end, so `f` cannot
||| be lazy in its second argument to cut the fold short.
export
foldr : (Bits8 -> acc -> acc) -> acc -> ByteString -> acc
foldr f z bs = go (fuel (lengthInt bs)) (lengthInt bs - 1) z
  where
    go : Nat -> Int -> acc -> acc
    go Z _ a = a
    go (S k) i a = go k (i - 1) (f (unsafeIndex bs i) a)

||| Does some byte satisfy the predicate?  Stops at the first.
export
any : (Bits8 -> Bool) -> ByteString -> Bool
any p bs = isJust (firstIndex p bs)

||| Do all bytes satisfy the predicate?  Stops at the first that does not.
export
all : (Bits8 -> Bool) -> ByteString -> Bool
all p bs = not (any (not . p) bs)

||| Does the byte occur?  Linear.
export
elem : Bits8 -> ByteString -> Bool
elem w = any (== w)

||| Does the byte not occur?  Linear.
export
notElem : Bits8 -> ByteString -> Bool
notElem w = not . elem w

||| The index of the first byte that satisfies the predicate.
export
findIndex : (Bits8 -> Bool) -> ByteString -> Maybe Nat
findIndex p bs = Prelude.map cast (firstIndex p bs)

||| The index of the first occurrence of the byte.
export
elemIndex : Bits8 -> ByteString -> Maybe Nat
elemIndex w = findIndex (== w)

||| Does the second byte string start with the first?  Linear in the
||| length of the first.
export
isPrefixOf : (prefix_ : ByteString) -> ByteString -> Bool
isPrefixOf p bs = lengthInt p <= lengthInt bs && matchesAt p bs 0

||| Does the second byte string end with the first?  Linear in the length
||| of the first.
export
isSuffixOf : (suffix_ : ByteString) -> ByteString -> Bool
isSuffixOf p bs = lengthInt p <= lengthInt bs && matchesAt p bs (lengthInt bs - lengthInt p)

||| Does the first byte string occur in the second?  The empty one occurs
||| in every byte string.  A simple search: `O(n * m)` for a haystack of
||| `n` and a needle of `m` bytes in the worst case.
export
isInfixOf : (needle : ByteString) -> (haystack : ByteString) -> Bool
isInfixOf p bs =
  let m = lengthInt p
      n = lengthInt bs
  in if m > n then False else go (fuel (n - m + 1)) 0
  where
    go : Nat -> Int -> Bool
    go Z _ = False
    go (S k) i = if matchesAt p bs i then True else go k (i + 1)

--------------------------------------------------------------------------
-- Fixed-width integers
--------------------------------------------------------------------------

-- `w` bytes from `i`, the first one the least significant.
littleEndian : ByteString -> (i : Int) -> (w : Nat) -> Bits64
littleEndian bs i w = go w (i + cast w - 1) 0
  where
    go : Nat -> Int -> Bits64 -> Bits64
    go Z _ acc = acc
    go (S k) j acc = go k (j - 1) (shiftL acc 8 .|. cast (unsafeIndex bs j))

-- `w` bytes from `i`, the first one the most significant.
bigEndian : ByteString -> (i : Int) -> (w : Nat) -> Bits64
bigEndian bs i w = go w i 0
  where
    go : Nat -> Int -> Bits64 -> Bits64
    go Z _ acc = acc
    go (S k) j acc = go k (j + 1) (shiftL acc 8 .|. cast (unsafeIndex bs j))

inRange : Nat -> Nat -> ByteString -> Bool
inRange i w bs = i + w <= length bs

||| The 16 bits at an index, the first byte the least significant.
||| `Nothing` if they are not all within the byte string.
export
indexBits16LE : Nat -> ByteString -> Maybe Bits16
indexBits16LE i bs = if inRange i 2 bs then Just (cast (littleEndian bs (cast i) 2)) else Nothing

||| The 16 bits at an index, the first byte the most significant.
||| `Nothing` if they are not all within the byte string.
export
indexBits16BE : Nat -> ByteString -> Maybe Bits16
indexBits16BE i bs = if inRange i 2 bs then Just (cast (bigEndian bs (cast i) 2)) else Nothing

||| The 32 bits at an index, the first byte the least significant.
||| `Nothing` if they are not all within the byte string.
export
indexBits32LE : Nat -> ByteString -> Maybe Bits32
indexBits32LE i bs = if inRange i 4 bs then Just (cast (littleEndian bs (cast i) 4)) else Nothing

||| The 32 bits at an index, the first byte the most significant.
||| `Nothing` if they are not all within the byte string.
export
indexBits32BE : Nat -> ByteString -> Maybe Bits32
indexBits32BE i bs = if inRange i 4 bs then Just (cast (bigEndian bs (cast i) 4)) else Nothing

||| The 64 bits at an index, the first byte the least significant.
||| `Nothing` if they are not all within the byte string.
export
indexBits64LE : Nat -> ByteString -> Maybe Bits64
indexBits64LE i bs = if inRange i 8 bs then Just (littleEndian bs (cast i) 8) else Nothing

||| The 64 bits at an index, the first byte the most significant.
||| `Nothing` if they are not all within the byte string.
export
indexBits64BE : Nat -> ByteString -> Maybe Bits64
indexBits64BE i bs = if inRange i 8 bs then Just (bigEndian bs (cast i) 8) else Nothing

--------------------------------------------------------------------------
-- Interfaces
--------------------------------------------------------------------------

-- Equal lengths and bytes.
sameBytes : ByteString -> ByteString -> Bool
sameBytes x y = if lengthInt x == lengthInt y then go (fuel (lengthInt x)) 0 else False
  where
    go : Nat -> Int -> Bool
    go Z _ = True
    go (S k) i = if unsafeIndex x i == unsafeIndex y i then go k (i + 1) else False

-- Lexicographic, bytes unsigned, a proper prefix is smaller.
compareBytes : ByteString -> ByteString -> Ordering
compareBytes x y =
  let nx = lengthInt x
      ny = lengthInt y
  in go (fuel (if nx < ny then nx else ny)) 0 (compare nx ny)
  where
    go : Nat -> Int -> Ordering -> Ordering
    go Z _ lens = lens
    go (S k) i lens =
      let a = unsafeIndex x i
          b = unsafeIndex y i
      in if a == b then go k (i + 1) lens else compare a b

||| Equal if they have the same bytes (whatever buffers they are slices of).
||| Linear.
export
Eq ByteString where
  (==) = sameBytes

||| Lexicographic order on the bytes as unsigned numbers.
export
Ord ByteString where
  compare = compareBytes

||| The bytes as the characters of Latin-1, escaped as a Haskell/Idris
||| string literal: `show (pack [104, 105, 10, 200])` is `"\"hi\\n\\200\""`.
export
Show ByteString where
  show bs = show (fastPack (foldr (\w, acc => chr (cast w) :: acc) [] bs))

||| `<+>` is `append`.
export
Semigroup ByteString where
  (<+>) = append

||| `neutral` is `empty`.  (`concat` of this module is a better way to join
||| a list than the `concat` of the `Prelude`, which appends one by one.)
export
Monoid ByteString where
  neutral = empty

--------------------------------------------------------------------------
-- UTF-8
--------------------------------------------------------------------------
--
-- The backends differ in what they do with bytes that are not UTF-8: the
-- primitive `getString` of `Data.Buffer` replaces them with U+FFFD, but a
-- truncated three-byte sequence gives one replacement character with Chez and
-- Node and two with RefC, and a surrogate gives one with Chez and three with
-- RefC and Node (measured).  So encoding and decoding are done here, with the
-- same strict rules everywhere: a code point is encoded in the shortest form;
-- decoding rejects truncated sequences, stray continuation bytes, overlong
-- forms, the surrogates U+D800..U+DFFF and anything above U+10FFFF.

-- The number of bytes of the UTF-8 form of a character.
charWidth : Char -> Int
charWidth c =
  let n = ord c
  in if n < 0x80 then 1 else if n < 0x800 then 2 else if n < 0x10000 then 3 else 4

-- Write the UTF-8 form of a character at an offset.
putChar_ : Buffer -> Int -> Char -> IO ()
putChar_ b at c =
  let n = ord c
      put : Int -> Int -> IO ()
      put k v = setBits8 b (at + k) (cast v)
  in if n < 0x80 then put 0 n
     else if n < 0x800
       then do put 0 (0xC0 .|. shiftR n 6)
               put 1 (0x80 .|. (n .&. 0x3F))
     else if n < 0x10000
       then do put 0 (0xE0 .|. shiftR n 12)
               put 1 (0x80 .|. (shiftR n 6 .&. 0x3F))
               put 2 (0x80 .|. (n .&. 0x3F))
     else do put 0 (0xF0 .|. shiftR n 18)
             put 1 (0x80 .|. (shiftR n 12 .&. 0x3F))
             put 2 (0x80 .|. (shiftR n 6 .&. 0x3F))
             put 3 (0x80 .|. (n .&. 0x3F))

||| The UTF-8 encoding of a string.  Linear in the length of the string.
export
fromString : String -> ByteString
fromString s =
  let cs = fastUnpack s in
  unsafeCreate (sumOver charWidth cs) $ \b =>
    ioForList cs 0 $ \at, c =>
      do putChar_ b at c
         pure (at + charWidth c)

-- The character that starts at `i` and the number of bytes that it takes, or
-- `Nothing` if the bytes there are not a valid UTF-8 sequence.
-- Precondition: `0 <= i < lengthInt bs`.
decodeAt : ByteString -> Int -> Maybe (Char, Int)
decodeAt bs i =
  let n = lengthInt bs
      b0 : Int
      b0 = cast (unsafeIndex bs i)
      cont : Int -> Maybe Int
      cont k = if i + k < n
                  then let c : Int
                           c = cast (unsafeIndex bs (i + k))
                       in if (c .&. 0xC0) == 0x80 then Just (c .&. 0x3F) else Nothing
                  else Nothing
  in if b0 < 0x80 then Just (chr b0, 1)
     else if b0 < 0xC2 then Nothing
     else if b0 < 0xE0 then
       (do c1 <- cont 1
           Just (chr (shiftL (b0 .&. 0x1F) 6 .|. c1), 2))
     else if b0 < 0xF0 then
       (do c1 <- cont 1
           c2 <- cont 2
           let cp = shiftL (b0 .&. 0x0F) 12 .|. shiftL c1 6 .|. c2
           if cp < 0x800 || (cp >= 0xD800 && cp < 0xE000)
              then Nothing
              else Just (chr cp, 3))
     else if b0 < 0xF5 then
       (do c1 <- cont 1
           c2 <- cont 2
           c3 <- cont 3
           let cp = shiftL (b0 .&. 0x07) 18 .|. shiftL c1 12 .|. shiftL c2 6 .|. c3
           if cp < 0x10000 || cp > 0x10FFFF
              then Nothing
              else Just (chr cp, 4))
     else Nothing

-- The characters in reverse order, and whether all bytes were valid; an
-- invalid byte becomes `replacement` if there is one and stops the decoding
-- otherwise.
decode : (replacement : Maybe Char) -> ByteString -> Maybe (List Char)
decode repl bs = go (fuel (lengthInt bs)) 0 []
  where
    go : Nat -> Int -> List Char -> Maybe (List Char)
    go Z _ acc = Just acc
    go (S k) i acc =
      if i >= lengthInt bs then Just acc
      else case decodeAt bs i of
             Just (c, w) => go k (i + w) (c :: acc)
             Nothing => case repl of
                             Nothing => Nothing
                             Just r => go k (i + 1) (r :: acc)

||| Is the byte string valid UTF-8?  Linear.
export
isValidUtf8 : ByteString -> Bool
isValidUtf8 bs = isJust (decode Nothing bs)

||| Decode UTF-8, or `Nothing` if the byte string is not valid UTF-8
||| (overlong forms, surrogates, values above U+10FFFF and truncated
||| sequences are not valid).  The same on every backend.  Linear.
export
toString : ByteString -> Maybe String
toString bs = map (fastPack . reverse) (decode Nothing bs)
  where
    map : (a -> b) -> Maybe a -> Maybe b
    map f Nothing = Nothing
    map f (Just x) = Just (f x)

||| Decode UTF-8, replacing each byte that does not start a valid sequence
||| with U+FFFD (one replacement character per such byte, and decoding
||| goes on at the next byte), which makes the decoding total.  The same on
||| every backend.  Linear.
export
toStringLossy : ByteString -> String
toStringLossy bs = case decode (Just (chr 0xFFFD)) bs of
                        Nothing => ""
                        Just cs => fastPack (reverse cs)

||| Literals of type `ByteString` are the UTF-8 encoding of the literal.
export
FromString ByteString where
  fromString = Data.ByteString.fromString

--------------------------------------------------------------------------
-- Hexadecimal
--------------------------------------------------------------------------

hexDigit : Bits8 -> Char
hexDigit n = if n < 10 then chr (48 + cast n) else chr (87 + cast n)

hexValue : Char -> Maybe Bits8
hexValue c =
  let n = ord c
  in if n >= 48 && n <= 57 then Just (cast (n - 48))
     else if n >= 97 && n <= 102 then Just (cast (n - 87))
     else if n >= 65 && n <= 70 then Just (cast (n - 55))
     else Nothing

||| The lower-case hexadecimal digits of the bytes, two per byte, with no
||| separators: `toHex (pack [1, 255])` is `"01ff"`.  Linear.
export
toHex : ByteString -> String
toHex bs = fastPack (foldr (\w, acc => hexDigit (shiftR w 4) :: hexDigit (w .&. 15) :: acc) [] bs)

||| Decode hexadecimal digits (both cases) to bytes, two digits per byte.
||| `Nothing` if the string has an odd length or a character that is not a
||| hexadecimal digit.  Linear.
export
fromHex : String -> Maybe ByteString
fromHex s = map (pack . reverse) (go [] (fastUnpack s))
  where
    map : (a -> b) -> Maybe a -> Maybe b
    map f Nothing = Nothing
    map f (Just x) = Just (f x)

    -- The values in reverse order.
    go : List Bits8 -> List Char -> Maybe (List Bits8)
    go acc [] = Just acc
    go _ [_] = Nothing
    go acc (h :: l :: rest) =
      -- (with `case`, not `do`: a bind in `Maybe` is not a tail call with every backend)
      case hexValue h of
           Nothing => Nothing
           Just hi => case hexValue l of
                           Nothing => Nothing
                           Just lo => go ((shiftL hi 4 .|. lo) :: acc) rest
