||| Hashing of values, for hash maps and hash sets.
|||
||| A `Hashable` type has a function `hashWithSalt` that mixes a value into a
||| running hash state.  Hashes of compound values are built by threading the
||| state through the components, so that `hash (a, b)` depends on both `a`
||| and `b` and on their order.
|||
||| The hashes of this module are numbers of 31 bits (in a `Bits64`, which is
||| the type that the interface fixes), computed with products below 2^58,
||| masks, shifts and exclusive ors only.  The products stay below 2^60 so that
||| the arithmetic stays in the small numbers of the Chez Scheme back end (its
||| fixnums have 61 bits; a product of 64-bit numbers would allocate a big
||| number for every operation), and the numbers are of 31 bits so that the RefC
||| back end can do the arithmetic on machine words.  The same value has the same
||| hash on every back end (Chez Scheme, RefC, JavaScript, ...), with
||| two exceptions that come from the back ends and not from the hashing: `Int`
||| has 32 bits on the JavaScript back ends, so an `Int` that does not fit in 32
||| bits is not the same number there, and the JavaScript back ends see a
||| string as UTF-16 code units (see the instance for `String`).  Hashes are
||| not meant to be a cryptographic hash or to be stable between versions of the
||| library.  An instance that you write may return any 64-bit number from
||| `hashWithSalt`, but the hash maps use only 30 bits of it, and the salt it
||| receives is folded to 32 bits by the instances of this module.
|||
||| The mixing step is `mix s w = fin31 (((s * 16777619) `xor` w) mod 2^31)`:
||| the FNV-1 combination step with the 32-bit FNV prime, followed by the
||| finaliser of Thomas Mueller's 32-bit integer hash (`x = (x `xor` (x >> 16))
||| * 0x45d9f3b mod 2^31` twice, and a last `x `xor` (x >> 16)`), which makes
||| every input bit affect every output bit.  A word of more than 31 bits is
||| mixed in as several words.  Strings are hashed with FNV-1a over their
||| characters, on 31 bits, followed by the same finaliser.
module Data.Hashable

import Data.Fin
import Data.List1
import Data.SnocList
import Data.String.Iterator
import Data.Vect

%default total

-- The hashing is done on `Int`s that hold 31-bit numbers, because the RefC back
-- end does the arithmetic of `Int` on machine words, and that of `Bits64` on
-- boxed values, and the Chez back end does that of `Bits64` and of an `Int`
-- that is above 2^60 on big numbers.  A number of 31 bits is not negative as
-- an `Int` of 32 bits, either (the JavaScript back ends), and the products
-- below are taken mod 2^32 there and are below 2^58 elsewhere, so that every
-- operation gives the same low 31 bits on all the back ends.  (A literal that
-- is above 2^31 is built from an `Integer` constant at every use by the RefC
-- back end, which is why the numbers are not of 32 bits.)

-- The 31 low bits.
%inline
mask31 : Int -> Int
mask31 x = prim__and_Int x 0x7fffffff

-- The 32-bit FNV offset basis, 0x811c9dc5, without its top bit: the state of a
-- string that is hashed without a salt.
%inline
basis : Int
basis = 0x011c9dc5

-- The finaliser of Thomas Mueller's 32-bit integer hash, adapted to 31 bits:
-- a bijection of the numbers below 2^31 with a good avalanche.  The products
-- are of a number of 31 bits and one of 27 bits.
%inline
fin31 : Int -> Int
fin31 x0 =
  let x1 = mask31 (prim__mul_Int (prim__xor_Int x0 (prim__shr_Int x0 16)) 0x45d9f3b)
      x2 = mask31 (prim__mul_Int (prim__xor_Int x1 (prim__shr_Int x1 16)) 0x45d9f3b)
  in prim__xor_Int x2 (prim__shr_Int x2 16)

-- Mix a word of 31 bits into a state of 31 bits.
%inline
mix31 : Int -> Int -> Int
mix31 s w = fin31 (mask31 (prim__xor_Int (prim__mul_Int s 16777619) w))

-- `mix31 basis`: the product of the basis and the prime, mod 2^31, is 0x050c5d1f.
%inline
mix31Basis : Int -> Int
mix31Basis w = fin31 (prim__xor_Int 0x050c5d1f w)

-- The state for a salt of the interface: a salt of this module is below 2^31
-- already, and any other is folded.
%inline
saltInt : Bits64 -> Int
saltInt s =
  if s <= 0x7fffffff
     then cast s
     else cast (prim__and_Bits64 (prim__xor_Bits64 s (prim__shr_Bits64 s 31))
                                 0x7fffffff)

-- The hash, a number in [0, 2^31).
%inline
wordOf : Int -> Bits64
wordOf p = cast p

-- Mix a 64-bit word into a state, 31 bits at a time (the last of them is of 2).
mixWord : Int -> Bits64 -> Int
mixWord s w =
  if w <= 0x7fffffff
     then mix31 s (cast w)
     else mix31 (mix31 (mix31 s (cast (prim__and_Bits64 w 0x7fffffff)))
                       (cast (prim__and_Bits64 (prim__shr_Bits64 w 31) 0x7fffffff)))
                (cast (prim__shr_Bits64 w 62))

-- Mix an `Int` that is not a number of 31 bits (a negative one, or one above
-- 2^31 - 1 on the back ends where `Int` has 64 bits) into a state, as two
-- words: the 31 low bits and the rest, shifted right (arithmetically, and by
-- 31, which the 32 bits of the JavaScript back ends allow).
mixBigInt : Int -> Int -> Int
mixBigInt s x =
  mix31 (mix31 s (mask31 x)) (mask31 (prim__shr_Int x 31))

-- Mix an `Int` into a state.
%inline
mixInt : Int -> Int -> Int
mixInt s x =
  if x >= 0
     then (if x <= 0x7fffffff then mix31 s x else mixBigInt s x)
     else mixBigInt s x

-- Mix a word into a salt, for the other types.
mix : Bits64 -> Bits64 -> Bits64
mix s w = wordOf (mixWord (saltInt s) w)

-- Hash a non-negative integer 64 bits at a time.
natLimbs : Bits64 -> Integer -> Bits64
natLimbs s n =
  if n < 18446744073709551616
     then mix s (cast n)
     else natLimbs (mix s (cast (assert_total $ n `mod` 18446744073709551616)))
                   -- n >= 2^64, so n `div` 2^64 is a smaller non-negative
                   -- number; the recursion stops when n < 2^64.  (The
                   -- divisor is not zero.)
                   (assert_smaller n (assert_total $ n `div` 18446744073709551616))

hashInteger : Bits64 -> Integer -> Bits64
hashInteger s n =
  if n >= 0
     then natLimbs s n
     else natLimbs (mix s 0x9e3779b97f4a7c15) (negate n)

||| Types with a hash function.
|||
||| Law: `x == y` implies `hashWithSalt s x == hashWithSalt s y` for every
||| salt `s`.  Different values should usually have different hashes, and a
||| change of a single input bit should change about half of the output bits;
||| the instances of this module do so.
public export
interface Eq a => Hashable a where
  ||| Mix a value into a running hash state.
  hashWithSalt : (salt : Bits64) -> a -> Bits64

  ||| The hash of a value, with a fixed default salt.
  hash : a -> Bits64
  hash = hashWithSalt 0x011c9dc5

--------------------------------------------------------------------------------
-- Primitive types
--------------------------------------------------------------------------------

||| Hashes the value as a 64-bit word.
export
Hashable Bits8 where
  hashWithSalt s x = mix s (cast x)

||| Hashes the value as a 64-bit word.
export
Hashable Bits16 where
  hashWithSalt s x = mix s (cast x)

||| Hashes the value as a 64-bit word.
export
Hashable Bits32 where
  hashWithSalt s x = mix s (cast x)

||| Hashes the word itself.
export
Hashable Bits64 where
  hashWithSalt = mix

||| Hashes the number; the hash does not depend on how a back end wraps negative numbers.
export
Hashable Int where
  hashWithSalt s x = wordOf (mixInt (saltInt s) x)
  hash x = if x >= 0
              then (if x <= 0x7fffffff
                       then wordOf (mix31Basis x)
                       else wordOf (mixBigInt basis x))
              else wordOf (mixBigInt basis x)

||| Hashes the number, like `Int`.
export
Hashable Int8 where
  hashWithSalt s x = wordOf (mixInt (saltInt s) (cast x))

||| Hashes the number, like `Int`.
export
Hashable Int16 where
  hashWithSalt s x = wordOf (mixInt (saltInt s) (cast x))

||| Hashes the number, like `Int`.
export
Hashable Int32 where
  hashWithSalt s x = wordOf (mixInt (saltInt s) (cast x))

||| `Int64` does not go through `Int`, which has only 32 bits on the JavaScript
||| back ends.
export
Hashable Int64 where
  hashWithSalt s x =
    mix s (if x >= 0
              then cast x
              else prim__xor_Bits64 (cast (negate x - 1)) 0xffffffffffffffff)

||| Hashes the number in blocks of 64 bits, so that a small `Integer` has the same hash as the `Int` of the same value.
export
Hashable Integer where
  hashWithSalt = hashInteger

||| Hashes the number, like `Integer`.
export
Hashable Nat where
  hashWithSalt s n = hashInteger s (natToInteger n)

||| Hashes the code point.
export
Hashable Char where
  hashWithSalt s c = wordOf (mix31 (saltInt s) (ord c))
  hash c = wordOf (mix31Basis (ord c))

||| Hashes `False` and `True` as 0 and 1.
export
Hashable Bool where
  hashWithSalt s False = mix s 0
  hashWithSalt s True = mix s 1

||| Hashes `()` as a constant.
export
Hashable () where
  hashWithSalt s () = mix s 0x1f

||| Hashes `LT`, `EQ` and `GT` as 0, 1 and 2.
export
Hashable Ordering where
  hashWithSalt s LT = mix s 0
  hashWithSalt s EQ = mix s 1
  hashWithSalt s GT = mix s 2

||| Hashes the number of the `Fin`.
export
Hashable (Fin n) where
  hashWithSalt s x = hashWithSalt s (finToNat x)

||| The finalised FNV-1a hash of a string, on 31 bits, from a state: its
||| characters go through `h = (h `xor` c) * 16777619 mod 2^31`, and the state is
||| finalised as for the other types.  The state is a number of 31 bits, the
||| salt xor the FNV offset basis for `hashString`.  It is not inlined so that the code that
||| is specialised by it (see `%spec`) does not mention the string iterator.
export %noinline
hashStringFrom : Int -> String -> Int
hashStringFrom h0 str = fin31 (withString str (loop h0))
  where
    loop : Int -> (1 it : StringIterator str) -> Int
    loop h it =
      case uncons str it of
        EOF => h
        Character c it' =>
          loop (mask31 (prim__mul_Int (prim__xor_Int h (ord c)) 16777619))
               (assert_smaller it it')

||| The hash of a string with a salt (see `hashStringFrom`).
export %noinline
hashString : (salt : Bits64) -> String -> Bits64
hashString s str = wordOf (hashStringFrom (prim__xor_Int (saltInt s) basis) str)

||| Strings are hashed by their characters, so the hash does not depend on the
||| encoding the back end uses internally (see `hashString`).
|||
||| The JavaScript back ends iterate over the UTF-16 code units of a string, so
||| on them a character outside the Basic Multilingual Plane is hashed as two
||| units and the hash of a string that has one differs from the hash on the
||| other back ends.
export
Hashable String where
  hashWithSalt = hashString
  hash str = wordOf (hashStringFrom 0 str)

-- The steps of `hashString`, for the instances of other modules that hash a
-- sequence of small numbers (such as the bytes of a `ByteString`) in the same
-- way: `fnvFinish (loop (fnvStart salt))`, where the loop applies `fnvStep` to
-- the state and each number.  (A state of 0 stays 0 for the number 0, so a
-- sequence that can have zeros should mix in its length too.)

||| The initial state of a hash of a sequence of small numbers: the salt xor
||| the FNV offset basis (the state is a number of 31 bits).
export %inline
fnvStart : (salt : Bits64) -> Int
fnvStart s = prim__xor_Int (saltInt s) basis

||| One step of FNV-1a on 31 bits: `(state `xor` word) * 16777619 mod 2^31`.
||| The word must be a number below 2^31 (a byte, a character).
export %inline
fnvStep : (state : Int) -> (word : Int) -> Int
fnvStep h w = mask31 (prim__mul_Int (prim__xor_Int h w) 16777619)

||| The hash of a sequence of small numbers from the state after the last
||| `fnvStep` (the finaliser that all the instances of this module use).
export %inline
fnvFinish : (state : Int) -> Bits64
fnvFinish h = wordOf (fin31 h)

||| Doubles are hashed by their integral part and by the first 52 bits of their
||| fractional part, because Idris has no portable way to read the bits of a
||| `Double`.  Numbers that are `==` have the same hash (in particular `0.0` and
||| `-0.0`); all NaNs hash alike, although a NaN is not equal to itself.
export
Hashable Double where
  hashWithSalt s d =
    if d /= d then mix s 0x7ff8000000000001                -- NaN
    else if d == 1.0 / 0.0 then mix s 0x7ff0000000000000   -- +infinity
    else if d == -1.0 / 0.0 then mix s 0xfff0000000000000  -- -infinity
    else
      let whole = floor d
          frac = d - whole                                 -- in [0, 1)
          fracBits : Integer
          fracBits = cast (frac * 4503599627370496.0)      -- 2^52
      in mix (hashInteger s (cast whole)) (cast fracBits)

--------------------------------------------------------------------------------
-- Compound types
--------------------------------------------------------------------------------

||| Tuples with more than two components are nested pairs, so they are hashed
||| by this instance too.
export
(Hashable a, Hashable b) => Hashable (a, b) where
  hashWithSalt s (x, y) = hashWithSalt (hashWithSalt s x) y

||| `Nothing` is a tag; `Just x` is a different tag and the hash of `x`.
export
Hashable a => Hashable (Maybe a) where
  hashWithSalt s Nothing = mix s 0
  hashWithSalt s (Just x) = hashWithSalt (mix s 1) x

||| `Left` and `Right` have different tags before the hash of the value.
export
(Hashable a, Hashable b) => Hashable (Either a b) where
  hashWithSalt s (Left x) = hashWithSalt (mix s 0) x
  hashWithSalt s (Right y) = hashWithSalt (mix s 1) y

-- Lists, vectors, snoc lists and non-empty lists hash their elements from
-- the first to the last and then the number of elements, so that the four
-- types give the same hash to the same sequence of elements.
hashSeq : Hashable a => Bits64 -> Nat -> List a -> Bits64
hashSeq s n [] = hashWithSalt s n
hashSeq s n (x :: xs) = hashSeq (hashWithSalt s x) (S n) xs

||| A list is hashed by its elements, from the first to the last, and its length.
export
Hashable a => Hashable (List a) where
  hashWithSalt s xs = hashSeq s 0 xs

||| Hashed like the list of its elements.
export
Hashable a => Hashable (Vect n a) where
  hashWithSalt s xs = hashSeq s 0 (toList xs)

||| Hashed like the list of its elements, from the first to the last.
export
Hashable a => Hashable (SnocList a) where
  hashWithSalt s xs = hashSeq s 0 (xs <>> [])

||| Hashed like the list of its elements.
export
Hashable a => Hashable (List1 a) where
  hashWithSalt s xs = hashSeq s 0 (forget xs)
