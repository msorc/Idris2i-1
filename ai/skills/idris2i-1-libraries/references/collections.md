# Collections and bytes

Every example is a complete program: its imports are in the first block, and
`main = exSorted` (or another example) runs it. `Data.SortedMap`, `Data.SortedSet`,
`Data.Array` (this fork), `Data.IOArray`, `Data.Buffer`, `Data.Vect`,
`Data.List1` are in `base` (no flag);
`Data.HashMap`, `Data.HashSet`, `Data.Hashable`, `Data.ByteString`,
`Data.ByteString.Builder` and `System.File.ByteString` are in `contrib`
(`-p contrib`, `depends = contrib`) and are this fork's: upstream 0.8 has none of
them.

```idris
import Data.Array
import Data.Buffer
import Data.ByteString
import Data.ByteString.Builder
import Data.Fin
import Data.HashMap
import Data.HashSet
import Data.IOArray
import Data.List1
import Data.SortedMap
import Data.SortedSet
import Data.String
import Data.Vect
import System.File
import System.File.ByteString
```

Several of these modules export the same names (`empty`, `insert`, `lookup`,
`fromList`, `toList`, `length`, `readFile`...). Idris2i-1 picks the one whose type
fits, so **annotate the collection** (`let m : SortedMap String Int = ...`):
without it, "Sorry, I can't find any elaboration which works" lists every
candidate. With `Data.ByteString` imported, a string literal can also be a
`ByteString`, which is one more reason to annotate. Or qualify the name:
`SortedMap.lookup`, `ByteString.length`, `System.File.ByteString.readFile`.

## `SortedMap` and `SortedSet`

A balanced tree, `Ord k`. `lookup k m` (key first), `insert k v m`,
`insertWith f k v m`, `update (Maybe v -> Maybe v) k m`, `delete k m`, `keys`,
`values`, `toList` (ascending), `fromList`, `mergeWith`, `pop` (smallest),
`leftMost`/`rightMost`. `Functor`, `Foldable`, `Traversable`, `Semigroup`
(right-biased: `merge` needs a `Semigroup v`), `Show`.

```idris
exSorted : IO ()
exSorted = do
  let counts : SortedMap String Int
      counts = foldl (\m, w => insertWith (+) w 1 m) empty (words "the cat and the dog and the bird")
  printLn (SortedMap.toList counts)    -- [("and", 2), ("bird", 1), ...]
  printLn (SortedMap.lookup "the" counts)        -- Just 3
  printLn (keys (SortedMap.delete "cat" counts))
  let s : SortedSet Int = fromList [3, 1, 2, 3]
  printLn (Prelude.toList (insert 0 s))   -- [0, 1, 2, 3]: Foldable, ascending
  printLn (contains 2 s)
```

`Data.SortedMap.Dependent` has `SortedDMap k v` whose value type depends on the
key.

## `HashMap`, `HashSet`, `Hashable` (contrib, this fork)

A persistent hash trie with the interface of `SortedMap`: `insert`, `insertWith`,
`lookup`, `lookupDefault`, `member`, `delete`, `update`, `alter`, `fromList`,
`fromListWith`, `toList`, `keys`, `values`, `foldrWithKey`, `mapWithKey`,
`filter`, `unionWith`, `size`. The order of `toList` is the order of the hashes,
not of insertion; `Eq` does not depend on it. Faster than `SortedMap` for
insertion and lookup (17-59% fewer instructions on RefC), 10-50% more memory.

A key type needs `Hashable` (methods `hashWithSalt : Bits64 -> a -> Bits64` and
`hash`) and `Eq`. There are instances for the numbers, `Char`, `String`, `Bool`,
tuples, `Maybe`, `Either`, `List`, `Vect`, `Fin`, and `ByteString` (in
`Data.ByteString`). For a type of your own, combine the fields:

```idris
record Point where
  constructor MkPoint
  x : Int
  y : Int

Eq Point where
  a == b = a.x == b.x && a.y == b.y

Hashable Point where
  hashWithSalt s p = hashWithSalt (hashWithSalt s p.x) p.y

exHash : IO ()
exHash = do
  let m : HashMap Point String = fromList [(MkPoint 0 0, "origin"), (MkPoint 1 2, "a")]
  printLn (HashMap.lookup (MkPoint 1 2) m)                 -- Just "a"
  let m' = HashMap.insertWith (++) (MkPoint 0 0) "zero/" m
  printLn (HashMap.lookupDefault "-" (MkPoint 0 0) m')     -- "zero/origin"
  printLn (HashMap.size m')
  let hs = HashSet.fromList ["a", "b", "a"]
  printLn (HashSet.size hs, HashSet.member "b" hs)         -- (2, True)
```

## `ByteString`, `Builder`, byte files (contrib, this fork)

`ByteString` is an immutable slice of a `Buffer`: `take`, `drop`, `splitAt`,
`span`, `split` share storage and take constant time. Indices and lengths are
`Nat`. Element type is `Bits8`. `fromString` encodes UTF-8 (so string literals
are byte strings: `FromString` instance); `toString` returns `Maybe String`
(`Nothing` for invalid UTF-8) and `toStringLossy` replaces bad bytes with U+FFFD.
`pack`/`unpack` convert from/to `List Bits8`; `toHex`/`fromHex`; `index`,
`head`, `uncons`, `isPrefixOf`, `isInfixOf`, `elemIndex`, `split 10 bs` (split on
a byte, gives a `List1`), big/little-endian reads `indexBits32BE` and friends.

A byte string literal cannot be matched in a `case` (it is not a constructor):
compare with `==`.

`Builder` concatenates pieces in linear time and allocates once in
`toByteString`: `byteString`, `utf8String`, `word8`, `word16BE`, `word32LE`,
`int64BE`..., `<+>` to join (`Semigroup`), string literals.

`System.File.ByteString`: `readFile`, `writeFile`, `appendFile`, `hGet h n`,
`hGetContents h`, `hPut h bs`. The write functions fail with
`(FileError, Int)` (the error and the number of bytes written).

```idris
covering
exBytes : IO ()
exBytes = do
  let bs : ByteString = "GET /index.html HTTP/1.1"
  printLn (ByteString.length bs)                         -- 24
  let (method, rest) = ByteString.break (== 32) bs       -- 32 is ' '
  printLn (toString method)                              -- Just "GET"
  printLn ("/index" `isPrefixOf` ByteString.drop 1 rest)
  printLn (map toStringLossy (forget (ByteString.split 32 bs)))
  let frame = toByteString (word8 1 <+> word16BE 513 <+> byteString "hi")
  putStrLn (toHex frame)                                 -- 0102016869
  printLn (indexBits16BE 1 frame)                        -- Just 513
  let path = "/tmp/idris-bytes.bin"
  Right () <- System.File.ByteString.writeFile path frame
    | Left (e, n) => putStrLn "write failed after \{show n} bytes: \{show e}"
  Right back <- System.File.ByteString.readFile path
    | Left e => putStrLn (show e)
  printLn (back == frame)                                -- True
  ignore (removeFile path)
```

## `Data.Array` (base, this fork): immutable, O(1) indexing

`Array n a` holds `n` values in one block of memory. `index : Fin n -> Array n a
-> a` takes constant time and cannot be out of range. Build with `tabulate (\i
=> ...)`, `replicate n x`, `fromVect`, or `fromList xs : (n ** Array n a)` (the
length is only known at run time, so it comes in a dependent pair).
`replaceAt i x arr` and `updateAt i f arr` **copy** the array (O(n)); `map`,
`zipWith` (`Zippable`), `sum`/`foldr` (`Foldable`), `toVect`, `size`, `Eq`,
`Show`. For in-place updates use `Data.IOArray` (below) or the linear arrays of
`Data.Linear.Array` (contrib). It is newer than some builds of this fork: if
`:module Data.Array` fails, the compiler predates it.

`Data.Vect` exports `fromList`, `replicate`, `index`, `replaceAt`, `updateAt`
too, and `Data.IOArray` `fromList`/`toList`: most resolve by type, but
`fromList` of a list literal is ambiguous with `Data.Vect` imported, so write
`Array.fromList`. `Data.Linear.Array` has an interface called `Array`; with
both imported, write `Data.Array.Array` if a type is ambiguous.

```idris
squares : Array 5 Nat
squares = tabulate (\i => finToNat i * finToNat i)

exArray : IO ()
exArray = do
  printLn squares                              -- [0, 1, 4, 9, 16]
  printLn (index 3 squares)                    -- 9
  printLn (replaceAt 0 100 squares, squares)   -- a copy; squares is unchanged
  printLn (updateAt last (+ 1) squares)        -- [0, 1, 4, 9, 17]
  printLn (zipWith (+) squares (replicate 5 1))
  printLn (map (* 2) squares, sum squares, size squares)
  let (n ** arr) = Array.fromList [the Int 10, 20, 30]
  case natToFin 2 n of                         -- a run-time index needs a check
    Just i => printLn (index i arr)            -- 30
    Nothing => putStrLn "out of range"
  printLn (toVect arr)
```

## `IOArray` and `Buffer`

`Data.IOArray`: a mutable boxed array. `newArray n`, `readArray a i : io (Maybe
elem)` (`Nothing` out of range or never written), `writeArray a i x : io Bool`
(`False` out of range), `max a` (the size), `toList`, `fromList`. Indices are
`Int`.

`Data.Buffer`: mutable raw bytes. `newBuffer n : io (Maybe Buffer)`,
`setBits8`/`getBits8`, `setInt32`, `setDouble`, `setString`/`getString buf off
len`, `rawSize`. An access outside the buffer crashes the program (a crash that
`catchCrash` can catch, see `concurrency.md`). Sockets and files read into
buffers (`System.File.Buffer`, `Network.Socket.Async`).

```idris
exArrays : IO ()
exArrays = do
  arr <- newArray {elem = String} 3
  ok <- writeArray arr 0 "zero"
  bad <- writeArray arr 7 "seven"          -- False: out of range
  printLn (ok, bad)
  printLn !(readArray arr 0)               -- Just "zero"
  printLn !(readArray arr 1)               -- Nothing: never written
  Just buf <- newBuffer 8
    | Nothing => putStrLn "out of memory"
  setBits8 buf 0 255
  setString buf 1 "abc"
  printLn !(getBits8 buf 0)
  putStrLn !(getString buf 1 3)
```

## `Vect`, `Fin`, `List1`

`Vect n a` is a list of length `n`; `index : Fin n -> Vect n a -> a` cannot be
out of range. `natToFin : Nat -> (n : Nat) -> Maybe (Fin n)` turns a run-time
number into an index; `fromList` gives a `Vect (length xs)`; `toList` goes back.
`replicate`, `zip`, `head`/`tail` on `Vect (S n)`, `updateAt`, `replaceAt`.

`List1 a` (`x ::: xs`) is a non-empty list: `head`, `forget : List1 a -> List a`,
`fromList : List a -> Maybe (List1 a)`, `singleton`. `split` of `Data.String`
and of `Data.ByteString` return one.

```idris
exVect : IO ()
exVect = do
  let v : Vect 3 Int = [10, 20, 30]
  printLn (index 1 v)                           -- 20
  case natToFin 2 3 of
    Just i => printLn (index i v)               -- 30
    Nothing => putStrLn "out of range"
  printLn (natToFin 5 3)                        -- Nothing
  printLn (toList (map (* 2) v))
  let xs = 1 ::: [2, 3]
  printLn (head xs, forget xs)
  printLn (List1.fromList (the (List Int) []))  -- Nothing
```
