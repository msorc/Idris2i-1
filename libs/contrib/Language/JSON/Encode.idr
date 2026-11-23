||| A fast compact encoder of JSON values into bytes.
|||
||| `encode` writes the value into a buffer that grows by doubling, so it
||| takes time linear in the size of the output.  The output has no
||| whitespace, and
|||
|||  * a string is written as its UTF-8 bytes between quotes, with `"`, `\`
|||    and the control characters U+0000..U+001F escaped (as `\"`, `\\`,
|||    `\b`, `\f`, `\n`, `\r`, `\t` or `\u00XX`); every other character,
|||    U+007F and non-ASCII ones included, is written as it is;
|||  * a number that is an integer of magnitude below 10^21 is written as
|||    its exact value, without a fraction or exponent (`1`, `-0`,
|||    `9007199254740992`, `100000000000000000000`); any other finite number is written with the fewest
|||    significant digits that read back as the same `Double` (`0.1`,
|||    `123.456`, `2.5e-7`, `1e300`: positional notation from 1e-6 up, while
|||    the digits fit in 2^53, and the notation of `show` otherwise); NaN and
|||    the infinities, which JSON cannot represent, are written as `null`.
|||
||| So `parseBytes (encode x) == Right x` for every value without NaN or
||| infinities (with `==` of `JSON`, which compares objects regardless of the
||| order of their keys; in fact the order is kept).
|||
||| The `Show` instance of `JSON` is not this encoder: it writes numbers with
||| `show` (`1.0`) and escapes non-ASCII characters, and it is kept as it was.
module Language.JSON.Encode

import Data.Bits
import Data.Buffer
import Data.ByteString
import Data.ByteString.Builder
import Data.ByteString.Internal
import Data.IORef
import Data.String

import public Language.JSON.Data

%default total

------------------------------------------------------------------------
-- A growing output buffer.  The writers are functions of the world token
-- (`PrimIO`), which the backends compile to plain functions that return
-- the new position: with `IO` and `do`, every step made a closure.
------------------------------------------------------------------------

-- The buffer, which `room` replaces by a bigger one when needed.
Out : Type
Out = IORef Buffer

||| The output of a writer of JSON text (see `JSONWriter`): a buffer that
||| grows.
export
data JSONOut : Type where
  MkJSONOut : Out -> JSONOut

||| A writer of JSON text: from a position of the output, it writes and
||| gives the position after what it wrote.  `encode` and the `toWriter` of
||| `Language.JSON.Typed` are made of them.
public export
JSONWriter : Type
JSONWriter = JSONOut -> Int -> PrimIO Int

%inline
set8 : Buffer -> Int -> Bits8 -> PrimIO ()
set8 b i v = toPrim (setBits8 b i v)

%inline
get8 : Buffer -> Int -> PrimIO Bits8
get8 b i = toPrim (getBits8 b i)

-- A buffer with room for `n` bytes at `pos`, of which the first `used`
-- bytes must be kept.
room : Out -> (used : Int) -> (pos : Int) -> (n : Int) -> PrimIO Buffer
room out used pos n w =
  case toPrim (readIORef out) w of
    MkIORes b w => case toPrim (rawSize b) w of
      MkIORes sz w =>
        if pos + n <= sz then MkIORes b w else
        case toPrim (newBuffer (max (2 * sz) (pos + n + 64))) w of
          MkIORes Nothing w => MkIORes (assert_total (idris_crash "Language.JSON.Encode: out of memory")) w
          MkIORes (Just nb) w => case toPrim (copyData b 0 used nb 0) w of
            MkIORes () w => case toPrim (writeIORef out nb) w of
              MkIORes () w => MkIORes nb w

-- Write the bytes of an ASCII string at `pos`; the position after them.
putAscii : Out -> String -> Int -> PrimIO Int
putAscii out s pos w =
  let n = stringByteLength s in
  case room out pos pos n w of
    MkIORes b w => case toPrim (setString b pos s) w of
      MkIORes () w => MkIORes (pos + n) w

putByte : Out -> Bits8 -> Int -> PrimIO Int
putByte out c pos w =
  case room out pos pos 1 w of
    MkIORes b w => case set8 b pos c w of
      MkIORes () w => MkIORes (pos + 1) w

------------------------------------------------------------------------
-- Strings
------------------------------------------------------------------------

-- How many more bytes the escaped form of a byte takes.
%inline
escapeExtra : Bits8 -> Int
escapeExtra c =
  if c == 34 || c == 92 then 1
  else if c >= 32 then 0
  else if c == 8 || c == 9 || c == 10 || c == 12 || c == 13 then 1
  else 5

%inline
hasZero : Bits32 -> Bits32
hasZero y = (y - 0x01010101) .&. complement y

-- Does a byte of the four (a little-endian word) need an escape: a quote,
-- a backslash or a control character?  (May say yes when none does, after
-- a byte that does; never no when one does.)
%inline
escape4 : Bits32 -> Bool
escape4 x =
  (((x - 0x20202020) .&. complement x) .|. hasZero (x `xor` 0x22222222) .|. hasZero (x `xor` 0x5C5C5C5C))
     .&. 0x80808080 /= 0

-- The extra bytes for the escapes of `[i, stop)`, four bytes at a time
-- where none of them needs one.
covering
countEscapes : Buffer -> Int -> Int -> Int -> PrimIO Int
countEscapes b i stop acc w =
  if i + 4 <= stop
     then case toPrim (getBits32 b i) w of
            MkIORes x w =>
              if escape4 x
                 then case get8 b i w of
                        MkIORes c w => countEscapes b (i + 1) stop (acc + escapeExtra c) w
                 else countEscapes b (i + 4) stop acc w
     else if i >= stop then MkIORes acc w
     else case get8 b i w of
            MkIORes c w => countEscapes b (i + 1) stop (acc + escapeExtra c) w

hexDigit : Int -> Bits8
hexDigit n = if n < 10 then cast (48 + n) else cast (87 + n)

-- Spread the escapes of the bytes `[from, i]` so that they end just before
-- `o + 1`, from the last byte to the first (the output does not overlap
-- the input that has yet to be read, as `o >= i`).
covering
expand : Buffer -> (from : Int) -> (i : Int) -> (o : Int) -> PrimIO ()
expand b from i o w =
  if i < from then MkIORes () w
  else case get8 b i w of
    MkIORes c w =>
      if c == 34 || c == 92 then two c w
      else if c >= 32 then
        case set8 b o c w of
          MkIORes () w => expand b from (i - 1) (o - 1) w
      else if c == 8 then two 98 w
      else if c == 9 then two 116 w
      else if c == 10 then two 110 w
      else if c == 12 then two 102 w
      else if c == 13 then two 114 w
      else let n = cast {to = Int} c in
        case set8 b o (hexDigit (n .&. 15)) w of
          MkIORes () w => case set8 b (o - 1) (hexDigit (shiftR n 4)) w of
            MkIORes () w => case set8 b (o - 2) 48 w of
              MkIORes () w => case set8 b (o - 3) 48 w of
                MkIORes () w => case set8 b (o - 4) 117 w of
                  MkIORes () w => case set8 b (o - 5) 92 w of
                    MkIORes () w => expand b from (i - 1) (o - 6) w
  where
    covering
    two : Bits8 -> PrimIO ()
    two e w = case set8 b o e w of
      MkIORes () w => case set8 b (o - 1) 92 w of
        MkIORes () w => expand b from (i - 1) (o - 2) w

-- Write a string literal at `pos`, and then the byte `after` unless it is
-- 0.  The bytes are copied first, and in the (rare) case that some need an
-- escape, spread out in place.
putStringThen : Out -> String -> Bits8 -> Int -> PrimIO Int
putStringThen out s after pos w =
  let n = stringByteLength s
      t = the Int (if after == 0 then 0 else 1) in
  case room out pos pos (n + 2 + t) w of
    MkIORes b w => case set8 b pos 34 w of
      MkIORes () w => case toPrim (setString b (pos + 1) s) w of
        MkIORes () w => case assert_total (countEscapes b (pos + 1) (pos + 1 + n) 0 w) of
          MkIORes 0 w => case set8 b (pos + 1 + n) 34 w of
            MkIORes () w => close b (pos + n + 2) w
          MkIORes extra w => case room out (pos + 1 + n) pos (n + 2 + extra + t) w of
            MkIORes b w => case assert_total (expand b (pos + 1) (pos + n) (pos + n + extra) w) of
              MkIORes () w => case set8 b (pos + 1 + n + extra) 34 w of
                MkIORes () w => close b (pos + n + extra + 2) w
  where
    close : Buffer -> Int -> PrimIO Int
    close b p w = if after == 0 then MkIORes p w
                  else case set8 b p after w of
                         MkIORes () w => MkIORes (p + 1) w

%inline
putString : Out -> String -> Int -> PrimIO Int
putString out s = putStringThen out s 0

------------------------------------------------------------------------
-- Numbers
------------------------------------------------------------------------

-- Division and remainder by a divisor that is not zero.
%inline
idiv : Int -> Int -> Int
idiv a b = assert_total (div a b)

%inline
imod : Int -> Int -> Int
imod a b = assert_total (mod a b)

-- The decimal digits of a non-negative Int, written so that they end just
-- before `o`, from the last.
-- (two at a time: the last two digits as the 16 bits of their characters,
-- the first one the least significant)
covering
putDigitsBack : Buffer -> Int -> Int -> PrimIO ()
putDigitsBack b n o w =
  if n < 10 then set8 b (o - 1) (cast (48 + n)) w
  else let r = n `imod` 100
           pair = 0x3030 + (r `idiv` 10) + 256 * (r `imod` 10) in
       case toPrim (setBits16 b (o - 2) (cast pair)) w of
         MkIORes () w => if n < 100 then MkIORes () w
                         else putDigitsBack b (n `idiv` 100) (o - 2) w

-- The number of decimal digits of a non-negative Int.
covering
digitCount : Int -> Int -> Int
digitCount k acc = if k < 10 then acc else digitCount (k `idiv` 10) (acc + 1)

-- `n` zeros from `i`.
covering
putZeros : Buffer -> Int -> Int -> PrimIO ()
putZeros b i n w =
  if n <= 0 then MkIORes () w
  else case set8 b i 48 w of
    MkIORes () w => putZeros b (i + 1) (n - 1) w

-- Write a non-negative Int in at least `width` digits (with leading zeros)
-- into a buffer that has room for them.
writeNat : Buffer -> Int -> (width : Int) -> Int -> PrimIO Int
writeNat b n width pos w =
  let d = assert_total (digitCount n 1)
      k = max width d in
  case assert_total (putZeros b pos (k - d) w) of
    MkIORes () w => case assert_total (putDigitsBack b n (pos + k) w) of
      MkIORes () w => MkIORes (pos + k) w

-- 10 to a power in [0, 22]: these are exact doubles.
pow10 : Int -> Double
pow10 0 = 1.0
pow10 1 = 10.0
pow10 2 = 100.0
pow10 3 = 1000.0
pow10 4 = 10000.0
pow10 5 = 100000.0
pow10 6 = 1000000.0
pow10 7 = 10000000.0
pow10 8 = 100000000.0
pow10 9 = 1000000000.0
pow10 10 = 10000000000.0
pow10 11 = 100000000000.0
pow10 12 = 1000000000000.0
pow10 13 = 10000000000000.0
pow10 14 = 100000000000000.0
pow10 15 = 1000000000000000.0
pow10 16 = 10000000000000000.0
pow10 17 = 100000000000000000.0
pow10 18 = 1000000000000000000.0
pow10 19 = 10000000000000000000.0
pow10 20 = 100000000000000000000.0
pow10 21 = 1000000000000000000000.0
pow10 _ = 10000000000000000000000.0

two53 : Double
two53 = 9007199254740992.0

-- For a positive `x` that is not an integer below 2^53: the fewest decimals
-- `p` (at most 22) such that an integer `m` below 2^53 has `m / 10^p == x`,
-- or -1.  `m / 10^p` is a division of exact doubles and is therefore what
-- reading the decimal number `m * 10^-p` gives, so the text reads back as
-- `x`; and `m` is the nearest integer to `x * 10^p`, the only candidate
-- with `p` decimals.
covering
fixedDigits : Double -> Int -> Double -> Int
fixedDigits x p scale =
  if p > 22 then -1 else
  let s = x * scale in
  if s >= two53 then -1 else
  if floor (s + 0.5) / scale == x then p
  else fixedDigits x (p + 1) (scale * 10.0)

two31 : Double
two31 = 2147483648.0

-- An integer in a Double, below 2^53, in at least `width` digits.  (The
-- digits are made with `Int` arithmetic on parts below 2^31: an `Int` has
-- 32 bits with the JavaScript backends.)
writeWhole : Buffer -> Double -> (width : Int) -> Int -> PrimIO Int
writeWhole b n width pos w =
  if n < two31 then writeNat b (cast n) width pos w else
  let hi0 = floor (n / 1.0e9)
      lo0 = n - hi0 * 1.0e9
      hi = if lo0 < 0.0 then hi0 - 1.0 else if lo0 >= 1.0e9 then hi0 + 1.0 else hi0
      lo = n - hi * 1.0e9 in
  case writeNat b (cast hi) (max 1 (width - 9)) pos w of
    MkIORes pos w => writeNat b (cast lo) 9 pos w

-- The text of `show`, without the `|<bits>` that it adds to a subnormal
-- number (a JSON number has no such suffix).
showNumber : Double -> String
showNumber x = fst (break (== '|') (show x))

infinity : Double
infinity = 1.0 / 0.0

-- A finite number that is not negative, in a buffer with room for 40
-- bytes (a positional number has at most 16 digits, a point and 22
-- decimals), and the position after it, or -1 for one to be written as
-- `show` writes it.
writeMagnitude : Buffer -> Double -> Int -> PrimIO Int
writeMagnitude b a pos w =
  if a < two53 && floor a == a then writeWhole b a 1 pos w
  else if a >= 1.0e-6
    then let p = assert_total (fixedDigits a 1 10.0) in
         if p < 0 then MkIORes (-1) w else
         let scale = pow10 p
             m = floor (a * scale + 0.5)
             ip0 = floor (m / scale)
             fr0 = m - ip0 * scale
             ip = if fr0 < 0.0 then ip0 - 1.0 else if fr0 >= scale then ip0 + 1.0 else ip0 in
         case writeWhole b ip 1 pos w of
           MkIORes pos w => case set8 b pos 46 w of
             MkIORes () w => writeWhole b (m - ip * scale) p (pos + 1) w
    else MkIORes (-1) w

-- A finite number, its sign written at `pos` in a buffer with room for 41
-- bytes if it is negative.
putFinite : Out -> Buffer -> Double -> Int -> PrimIO Int
putFinite out b x pos w =
  if x < 0.0 || (x == 0.0 && 1.0 / x < 0.0)
     then case set8 b pos 45 w of
            MkIORes () w => magnitude (abs x) (pos + 1) w
     else magnitude x pos w
  where
    magnitude : Double -> Int -> PrimIO Int
    magnitude a p0 w = case writeMagnitude b a p0 w of
      MkIORes p w =>
        if p >= 0 then MkIORes p w
        else if floor a == a && a < 1.0e21
           then putAscii out (show (cast {to = Integer} a)) p0 w
           else putAscii out (showNumber a) p0 w

putNumber : Out -> Double -> Int -> PrimIO Int
putNumber out x pos w =
  if x /= x || x == infinity || x == negate infinity then putAscii out "null" pos w
  else case room out pos pos 41 w of
         MkIORes b w => putFinite out b x pos w

------------------------------------------------------------------------
-- Values
------------------------------------------------------------------------

mutual
  putValue : Out -> JSON -> Int -> PrimIO Int
  putValue out JNull pos w = putAscii out "null" pos w
  putValue out (JBoolean True) pos w = putAscii out "true" pos w
  putValue out (JBoolean False) pos w = putAscii out "false" pos w
  putValue out (JNumber x) pos w = putNumber out x pos w
  putValue out (JString s) pos w = putString out s pos w
  putValue out (JArray []) pos w = putAscii out "[]" pos w
  putValue out (JArray (x :: xs)) pos w =
    case putByte out 91 pos w of
      MkIORes pos w => case putValue out x pos w of
        MkIORes pos w => case putElems out xs pos w of
          MkIORes pos w => putByte out 93 pos w
  putValue out (JObject []) pos w = putAscii out "{}" pos w
  putValue out (JObject (m :: ms)) pos w =
    case putByte out 123 pos w of
      MkIORes pos w => case putMember out m pos w of
        MkIORes pos w => case putMembers out ms pos w of
          MkIORes pos w => putByte out 125 pos w

  putElems : Out -> List JSON -> Int -> PrimIO Int
  putElems out [] pos w = MkIORes pos w
  putElems out (x :: xs) pos w =
    case putByte out 44 pos w of
      MkIORes pos w => case putValue out x pos w of
        MkIORes pos w => putElems out xs pos w

  putMember : Out -> (String, JSON) -> Int -> PrimIO Int
  putMember out (k, v) pos w =
    case putStringThen out k 58 pos w of
      MkIORes pos w => putValue out v pos w

  putMembers : Out -> List (String, JSON) -> Int -> PrimIO Int
  putMembers out [] pos w = MkIORes pos w
  putMembers out (m :: ms) pos w =
    case putByte out 44 pos w of
      MkIORes pos w => case putMember out m pos w of
        MkIORes pos w => putMembers out ms pos w

||| Write a JSON value.
export
writeValue : JSON -> JSONWriter
writeValue j (MkJSONOut out) pos = putValue out j pos

||| Write a string literal (quoted and escaped).
export
writeString : String -> JSONWriter
writeString s (MkJSONOut out) pos = putString out s pos

||| Write a number (as `encode` does).
export
writeNumber : Double -> JSONWriter
writeNumber x (MkJSONOut out) pos = putNumber out x pos

||| Write an `Int` (exactly, as `encode` writes an integral number).
export
writeInt : Int -> JSONWriter
writeInt n o@(MkJSONOut out) pos w =
  -- (below 2^31: an `Int` has 32 bits with the JavaScript backends)
  if n < 0 || n >= 2147483648 then writeNumber (cast n) o pos w
  else case room out pos pos 20 w of
         MkIORes b w => writeNat b n 1 pos w

||| Write the bytes of an ASCII string as they are (punctuation, or a key
||| and its colon written in advance: `"\"name\":"`).
export
writeRaw : String -> JSONWriter
writeRaw s (MkJSONOut out) pos = putAscii out s pos

||| Write a byte as it is.
export
writeByte : Bits8 -> JSONWriter
writeByte c (MkJSONOut out) pos = putByte out c pos

||| Write a boolean.
export
writeBool : Bool -> JSONWriter
writeBool True (MkJSONOut out) pos = putAscii out "true" pos
writeBool False (MkJSONOut out) pos = putAscii out "false" pos

-- Run a writer from an empty buffer of a guessed size, and take the bytes
-- that it wrote.
runOut : Int -> (Out -> Int -> PrimIO Int) -> ByteString
runOut guess act = unsafePerformIO $ do
  Just b <- newBuffer guess
    | Nothing => assert_total (idris_crash "Language.JSON.Encode: out of memory")
  out <- newIORef b
  n <- fromPrim (act out 0)
  final <- readIORef out
  -- `final` is not written again and nothing else refers to it.
  pure (UnsafeBS final 0 n)

||| The bytes that a writer writes from an empty output.
export
runWriter : JSONWriter -> ByteString
runWriter wr = runOut 256 (\out, pos => wr (MkJSONOut out) pos)

||| The compact JSON text of a value, as UTF-8 bytes.  See the module header
||| for the format.  Linear in the size of the output.
export
encode : JSON -> ByteString
encode j = runOut 256 (\out, pos => putValue out j pos)

||| The compact JSON text of a value as a `Builder` (see `encode`).
export
encodeBuilder : JSON -> Builder
encodeBuilder j = byteString (encode j)

||| The compact JSON text of a value as a `String` (see `encode`).
export
encodeText : JSON -> String
encodeText j =
  let bs = encode j in
  unsafePerformIO (getString (unsafeBuffer bs) (unsafeOffset bs) (lengthInt bs))

||| The JSON string literal of a string, quoted and escaped as by `encode`.
export
encodeString : String -> ByteString
encodeString s = runOut (stringByteLength s + 16) (\out, pos => putString out s pos)

||| The JSON text of a number, as written by `encode`.
export
encodeNumber : Double -> ByteString
encodeNumber x = runOut 32 (\out, pos => putNumber out x pos)
