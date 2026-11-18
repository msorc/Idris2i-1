||| Hashing of values to 64 bits, for hash maps and hash sets.
|||
||| A `Hashable` type has a function `hashWithSalt` that mixes a value into a
||| running 64-bit state.  Hashes of compound values are built by threading the
||| state through the components, so that `hash (a, b)` depends on both `a`
||| and `b` and on their order.
|||
||| The hash functions of this module are fully specified and use only
||| arithmetic on `Bits64`, `Int` and `Integer`, so the same value has the same
||| hash on every back end (Chez Scheme, Racket, RefC, JavaScript, ...), with
||| two exceptions that come from the back ends and not from the hashing: `Int`
||| has 32 bits on the JavaScript back ends, so an `Int` that does not fit in 32
||| bits is not the same number there, and the JavaScript back ends see a
||| string as UTF-16 code units (see the instance for `String`).  Hashes are
||| not meant to be a cryptographic hash or to be stable between versions of the
||| library.
|||
||| The mixing step is `mix s w = fmix64 ((s * 0x100000001b3) `xor` w)`: the
||| FNV-1 combination step with the 64-bit FNV prime, followed by the 64-bit
||| finaliser of MurmurHash3 (`fmix64`), which makes every input bit affect
||| every output bit.  Strings are hashed with 32-bit FNV-1a over their characters
||| followed by `fmix64`.
module Data.Hashable

import Data.Fin
import Data.List1
import Data.SnocList
import Data.String.Iterator
import Data.Vect

%default total

-- The murmur3 finaliser on 64 bits: a bijection with full avalanche.
fmix64 : Bits64 -> Bits64
fmix64 h0 =
  let h1 = prim__xor_Bits64 h0 (prim__shr_Bits64 h0 33)
      h2 = h1 * 0xff51afd7ed558ccd
      h3 = prim__xor_Bits64 h2 (prim__shr_Bits64 h2 33)
      h4 = h3 * 0xc4ceb9fe1a85ec53
  in prim__xor_Bits64 h4 (prim__shr_Bits64 h4 33)

-- Mix one 64-bit word into a running state.
mix : Bits64 -> Bits64 -> Bits64
mix s w = fmix64 (prim__xor_Bits64 (s * 0x100000001b3) w)

-- The 64-bit FNV offset basis, used as the default salt.
defaultSalt : Bits64
defaultSalt = 0xcbf29ce484222325

-- An injective map from Int to Bits64 that does not rely on how the back
-- end wraps negative numbers: n >= 0 goes to n, n < 0 to complement of (-n-1).
intWord : Int -> Bits64
intWord n =
  if n >= 0
     then cast n
     else prim__xor_Bits64 (cast (negate n - 1)) 0xffffffffffffffff

-- Hash a non-negative integer 64 bits at a time.
natLimbs : Bits64 -> Integer -> Bits64
natLimbs s n =
  if n < 18446744073709551616
     then mix s (cast n)
     else natLimbs (mix s (cast (n `mod` 18446744073709551616)))
                   -- n >= 2^64, so n `div` 2^64 is a smaller non-negative
                   -- number; the recursion stops when n < 2^64.
                   (assert_smaller n (n `div` 18446744073709551616))

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
  hash = hashWithSalt 0xcbf29ce484222325

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
  hashWithSalt s x = mix s (intWord x)

||| Hashes the number, like `Int`.
export
Hashable Int8 where
  hashWithSalt s x = mix s (intWord (cast x))

||| Hashes the number, like `Int`.
export
Hashable Int16 where
  hashWithSalt s x = mix s (intWord (cast x))

||| Hashes the number, like `Int`.
export
Hashable Int32 where
  hashWithSalt s x = mix s (intWord (cast x))

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
  hashWithSalt s c = mix s (intWord (ord c))

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

||| Strings are hashed by their characters, so the hash does not depend on the
||| encoding the back end uses internally.  The characters go through 32-bit
||| FNV-1a (`h = (h `xor` c) * 16777619 mod 2^32`), which keeps all the
||| arithmetic in small numbers (64-bit arithmetic allocates on the Chez back
||| end), and the state and the salt are then mixed into 64 bits with `fmix64`.
||| The hash of a string therefore has 32 bits of entropy, which is enough for
||| the hash maps of this library (they use 30 bits).
|||
||| The JavaScript back ends iterate over the UTF-16 code units of a string, so
||| on them a character outside the Basic Multilingual Plane is hashed as two
||| units and the hash of a string that has one differs from the hash on the
||| other back ends.
export
Hashable String where
  hashWithSalt s str =
    let h = withString str (loop (prim__xor_Bits64 (prim__and_Bits64
                                    (prim__xor_Bits64 s (prim__shr_Bits64 s 32))
                                    0xffffffff)
                                  0x811c9dc5))
    in fmix64 (prim__xor_Bits64 h (prim__shl_Bits64 s 32))
  where
    loop : Bits64 -> (1 it : StringIterator str) -> Bits64
    loop h it =
      case uncons str it of
        EOF => h
        Character c it' =>
          loop (prim__and_Bits64 (prim__xor_Bits64 h (cast (ord c)) * 16777619)
                                 0xffffffff)
               (assert_smaller it it')

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
