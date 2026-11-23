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
import Data.Hashable
import Data.List
import Data.List1
import Data.String

%default total

--------------------------------------------------------------------------
-- Helpers (not exported)
--------------------------------------------------------------------------

-- The loops over the bytes count with `Int` indices, which are C integers
-- with RefC, and tell the totality checker that the index gets closer to the
-- end with `assert_smaller` (counting down a `Nat` as well costs an
-- arithmetic operation on a `Nat` for every byte).

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
firstIndex p bs = go 0
  where
    go : Int -> Maybe Int
    go i = if i >= lengthInt bs then Nothing
           else if p (unsafeIndex bs i) then Just i
           else go (assert_smaller i (i + 1))

-- The first index of a byte, if it occurs.
byteIndex : Bits8 -> ByteString -> Maybe Int
byteIndex w bs = let r = findByteFrom w 0 bs in if r < 0 then Nothing else Just r

-- Do the `lengthInt pat` bytes of `pat` equal those of `bs` from `at`?
-- Precondition: they are within `bs`.
matchesAt : (pat : ByteString) -> (bs : ByteString) -> (at : Int) -> Bool
matchesAt = unsafeMatchesAt

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
unpack bs = go (lengthInt bs - 1) []
  where
    go : Int -> List Bits8 -> List Bits8
    go i acc = if i < 0 then acc
               else go (assert_smaller i (i - 1)) (unsafeIndex bs i :: acc)

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
splitWith p bs = go 0 0 []
  where
    -- The pieces come in reverse order.
    finish : List ByteString -> List1 ByteString
    finish rev = case reverse rev of
                      [] => empty ::: []
                      (x :: xs) => x ::: xs

    -- `start` is where the current piece starts, `i` the next index to look at.
    go : (start : Int) -> (i : Int) -> List ByteString -> List1 ByteString
    go start i acc =
      if i >= lengthInt bs then finish (unsafeSlice start (lengthInt bs - start) bs :: acc)
      else if p (unsafeIndex bs i)
         then go (i + 1) (assert_smaller i (i + 1)) (unsafeSlice start (i - start) bs :: acc)
         else go start (assert_smaller i (i + 1)) acc

||| Split at the occurrences of a byte, which are dropped:
||| `split 44 "a,b,,c"` is `["a", "b", "", "c"]`.  See `splitWith`, which
||| this is with a search for the byte (`memchr` with RefC).
export
split : Bits8 -> ByteString -> List1 ByteString
split w bs = go 0 []
  where
    finish : List ByteString -> List1 ByteString
    finish rev = case reverse rev of
                      [] => empty ::: []
                      (x :: xs) => x ::: xs

    -- `start` is where the current piece starts.
    go : (start : Int) -> List ByteString -> List1 ByteString
    go start acc =
      let i = findByteFrom w start bs in
      if i < 0 then finish (unsafeSlice start (lengthInt bs - start) bs :: acc)
      else go (assert_smaller start (i + 1)) (unsafeSlice start (i - start) bs :: acc)

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
foldl f z bs = go 0 z
  where
    go : Int -> acc -> acc
    go i a = if i >= lengthInt bs then a
             else go (assert_smaller i (i + 1)) (f a (unsafeIndex bs i))

||| Fold from the right (the last byte is combined first).  Linear, and does
||| not use stack space: it visits the bytes from the end, so `f` cannot
||| be lazy in its second argument to cut the fold short.
export
foldr : (Bits8 -> acc -> acc) -> acc -> ByteString -> acc
foldr f z bs = go (lengthInt bs - 1) z
  where
    go : Int -> acc -> acc
    go i a = if i < 0 then a
             else go (assert_smaller i (i - 1)) (f (unsafeIndex bs i) a)

||| Does some byte satisfy the predicate?  Stops at the first.
export
any : (Bits8 -> Bool) -> ByteString -> Bool
any p bs = isJust (firstIndex p bs)

||| Do all bytes satisfy the predicate?  Stops at the first that does not.
export
all : (Bits8 -> Bool) -> ByteString -> Bool
all p bs = not (any (not . p) bs)

||| Does the byte occur?  Linear (a `memchr` with RefC).
export
elem : Bits8 -> ByteString -> Bool
elem w bs = findByteFrom w 0 bs >= 0

||| Does the byte not occur?  Linear.
export
notElem : Bits8 -> ByteString -> Bool
notElem w = not . elem w

||| The index of the first byte that satisfies the predicate.
export
findIndex : (Bits8 -> Bool) -> ByteString -> Maybe Nat
findIndex p bs = Prelude.map cast (firstIndex p bs)

||| The index of the first occurrence of the byte.  Linear (a `memchr` with
||| RefC).
export
elemIndex : Bits8 -> ByteString -> Maybe Nat
elemIndex w bs = Prelude.map cast (byteIndex w bs)

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
  in if m > n then False else if m == 0 then True else go 0 (n - m)
  where
    -- the candidates are the occurrences of the first byte of the needle at
    -- or before `lastStart`
    go : Int -> (lastStart : Int) -> Bool
    go i lastStart =
      let j = findByteFrom (unsafeIndex p 0) i bs in
      if j < 0 || j > lastStart then False
      else if matchesAt p bs j then True
      else go (assert_smaller i (j + 1)) lastStart

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
indexBits32LE i bs = if inRange i 4 bs then Just (unsafeIndexWord32LE bs (cast i)) else Nothing

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

||| Equal if they have the same bytes (whatever buffers they are slices of).
||| Linear (a `memcmp` with RefC).
export
Eq ByteString where
  (==) = sameBytes

||| Lexicographic order on the bytes as unsigned numbers (a `memcmp` with
||| RefC).
export
Ord ByteString where
  compare = compareBytes

-- FNV-1a over the bytes of the slice, as `hashString` does over characters,
-- and then the length (low 31 bits) as one more word.  The length keeps the
-- byte strings of zeros apart: a zero byte leaves the state 0 as it is, so
-- without it all of them would hash alike when the state starts at 0.
hashBytes : Int -> ByteString -> Int
hashBytes h0 bs =
  fnvStep (unsafeHashRange h0 (unsafeBuffer bs) (unsafeOffset bs) (lengthInt bs))
          (prim__and_Int (lengthInt bs) 0x7fffffff)

||| Hashed by its bytes only, with FNV-1a over the bytes and then the length,
||| and the finaliser of the other instances of `Data.Hashable`, in time
||| linear in the length.  Byte strings that are `==` have the same hash,
||| whatever buffers and offsets they are slices of, and the hash is the
||| same with every back end.
|||
||| This instance is in this module, which imports `Data.Hashable` (a small
||| module), so that `Data.Hashable` does not depend on `Data.ByteString`.
export
Hashable ByteString where
  hashWithSalt s bs = fnvFinish (hashBytes (fnvStart s) bs)

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
-- RefC and Node (measured).  So the bytes are checked here, with the same
-- strict rules everywhere: decoding rejects truncated sequences, stray
-- continuation bytes, overlong forms, the surrogates U+D800..U+DFFF and
-- anything above U+10FFFF; valid UTF-8 is then read by the backend, which
-- all do alike.  Encoding is the backend's `setString`, which writes the
-- shortest form of every character.  (A string that holds a surrogate,
-- which only `chr` can make, need not be encoded alike by the backends.)

||| The UTF-8 encoding of a string.  Linear in the length of the string.
|||
||| (The bytes are copied from the string by `Data.Buffer.setString`, which
||| writes the UTF-8 encoding with every backend: with RefC, a string is
||| its UTF-8 bytes, and this is a copy.)
export
fromString : String -> ByteString
fromString s = unsafeCreate (stringByteLength s) (\b => setString b 0 s)

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
decode repl bs = go 0 []
  where
    go : Int -> List Char -> Maybe (List Char)
    go i acc =
      if i >= lengthInt bs then Just acc
      else case decodeAt bs i of
             Just (c, w) => go (assert_smaller i (i + w)) (c :: acc)
             Nothing => case repl of
                             Nothing => Nothing
                             Just r => go (assert_smaller i (i + 1)) (r :: acc)

-- Are the bytes from `i` valid UTF-8?  Without allocating: the width of
-- each sequence is what `decodeAt` finds.
validFrom : ByteString -> Int -> Bool
validFrom bs i =
  if i >= lengthInt bs then True
  else if unsafeIndex bs i < 0x80 then validFrom bs (assert_smaller i (i + 1))
  else case decodeAt bs i of
         Just (_, w) => validFrom bs (assert_smaller i (i + w))
         Nothing => False

||| Is the byte string valid UTF-8?  Linear.
export
isValidUtf8 : ByteString -> Bool
isValidUtf8 bs = validFrom bs 0

||| Decode UTF-8, or `Nothing` if the byte string is not valid UTF-8
||| (overlong forms, surrogates, values above U+10FFFF and truncated
||| sequences are not valid).  The same on every backend.  Linear.
|||
||| (The bytes are checked here, and then copied into the string by the
||| backend, which reads valid UTF-8 the same way with every backend.)
export
toString : ByteString -> Maybe String
toString bs =
  if isValidUtf8 bs
     then Just (unsafeBufferString (unsafeBuffer bs) (unsafeOffset bs) (lengthInt bs))
     else Nothing

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
