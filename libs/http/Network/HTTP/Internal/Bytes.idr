||| Byte-level helpers shared by the modules of the `http` library.
|||
||| These work on the representation of `Data.ByteString` (a slice of a
||| buffer) and are written as monomorphic loops over `Int` indices and
||| `Bits8` values, because the parsers that use them are on the hot path of
||| a server.  They are not part of the public interface of the library.  The
||| reads of the bytes are those of `Data.ByteString.Internal`.
module Network.HTTP.Internal.Bytes

import Data.Bits
import Data.Buffer
import Data.ByteString
import Data.ByteString.Internal

%default total

--------------------------------------------------------------------------
-- Access
--------------------------------------------------------------------------

-- The reads of single bytes and words are those of
-- `Data.ByteString.Internal` (`unsafeIndex`, `unsafeBufferByte`,
-- `unsafeBufferWord32LE`, `findByteFrom`, `sameBytes`).

||| Does a word have a byte below `n` (for `n <= 128`)?  Exact as a test of
||| the whole word, not of which byte it is.
export %inline
hasByteBelow : Bits32 -> Bits32 -> Bool
hasByteBelow w n = prim__and_Bits32 (prim__and_Bits32 (w - n * 0x01010101) (prim__xor_Bits32 w 0xFFFFFFFF)) 0x80808080 /= 0

||| Does a word have a byte equal to `c`?
export %inline
hasByteEq : Bits32 -> Bits32 -> Bool
hasByteEq w c = hasByteBelow (prim__xor_Bits32 w (c * 0x01010101)) 1

||| Does a word have a byte of 0x80 or above?
export %inline
hasHighByte : Bits32 -> Bool
hasHighByte w = prim__and_Bits32 w 0x80808080 /= 0

||| The slice `[start, end)` of a byte string, sharing its buffer.
||| Precondition: `0 <= start <= end <= lengthInt bs` (not checked).
export %inline
sliceFromTo : (start, end : Int) -> ByteString -> ByteString
sliceFromTo start end (UnsafeBS b o _) = UnsafeBS b (o + start) (end - start)

||| The bytes of a byte string from an index to its end.  Precondition:
||| `0 <= start <= lengthInt bs` (not checked).
export %inline
dropInt : Int -> ByteString -> ByteString
dropInt start (UnsafeBS b o n) = UnsafeBS b (o + start) (n - start)

||| The first `n` bytes.  Precondition: `0 <= n <= lengthInt bs`.
export %inline
takeInt : Int -> ByteString -> ByteString
takeInt n (UnsafeBS b o _) = UnsafeBS b o n

--------------------------------------------------------------------------
-- Character classes (RFC 5234 and RFC 9110 section 5.6)
--------------------------------------------------------------------------

-- The token characters of RFC 9110 section 5.6.2, as bit masks over the
-- ASCII codes 0..63 and 64..127:
--   "!" / "#" / "$" / "%" / "&" / "'" / "*" / "+" / "-" / "." /
--   "^" / "_" / "`" / "|" / "~" / DIGIT / ALPHA
-- (0..63: ! # $ % & ' * + - . 0-9; 64..127: A-Z ^ _ ` a-z | ~)
%inline
tcharLow : Bits64
tcharLow = 0x03FF6CFA00000000

%inline
tcharHigh : Bits64
tcharHigh = 0x57FFFFFFC7FFFFFE

||| Is bit `i` (0..63) of a mask set?
export %inline
maskHas : Bits64 -> Bits8 -> Bool
maskHas mask i = prim__and_Bits64 (prim__shr_Bits64 mask (cast i)) 1 /= 0

||| Is the byte a token character (`tchar` of RFC 9110)?
export %inline
isTChar : Bits8 -> Bool
isTChar w =
  if w < 64 then maskHas tcharLow w
  else if w < 128 then maskHas tcharHigh (w - 64)
  else False

||| Is the byte a field-value character: visible ASCII, space, horizontal
||| tab or obs-text (0x80..0xFF)?  Not CR, LF, NUL or the other controls.
export %inline
isFieldVChar : Bits8 -> Bool
isFieldVChar w = (w >= 0x20 && w /= 0x7F) || w == 0x09

||| A decimal digit.
export %inline
isDigit : Bits8 -> Bool
isDigit w = w >= 48 && w <= 57

||| The value of a hexadecimal digit (either case), or `-1`.
export %inline
hexValue : Bits8 -> Int
hexValue w =
  if w >= 48 && w <= 57 then cast w - 48
  else if w >= 97 && w <= 102 then cast w - 87
  else if w >= 65 && w <= 70 then cast w - 55
  else -1

||| An ASCII letter in lower case; other bytes as they are.
export %inline
toLowerByte : Bits8 -> Bits8
toLowerByte w = if w >= 65 && w <= 90 then w + 32 else w

||| Space or horizontal tab (`OWS` characters).
export %inline
isOWS : Bits8 -> Bool
isOWS w = w == 32 || w == 9

--------------------------------------------------------------------------
-- Buffers, in IO
--------------------------------------------------------------------------

-- The primitives of Data.Buffer, called in IO directly: the exported
-- functions of Data.Buffer are polymorphic in `HasIO`, and on RefC a call
-- through the dictionary of `HasIO IO` allocates a closure for the action.

%foreign "scheme:blodwen-new-buffer"
         "RefC:newBuffer"
         "node:lambda:s=>Buffer.alloc(s)"
prim__newBufferIO : Int -> PrimIO Buffer

%foreign "scheme:blodwen-buffer-copydata"
         "RefC:copyBuffer"
         "node:lambda:(b1,o1,length,b2,o2)=>b1.copy(b2,o2,o1,o1+length)"
prim__copyDataIO : Buffer -> Int -> Int -> Buffer -> Int -> PrimIO ()

%foreign "scheme:blodwen-buffer-setbyte"
         "RefC:setBufferUInt8"
         "node:lambda:(buf,offset,value)=>buf.writeUInt8(value, offset)"
prim__setBits8IO : Buffer -> Int -> Bits8 -> PrimIO ()

%foreign "scheme:blodwen-buffer-size"
         "RefC:getBufferSize"
         "node:lambda:b => b.length"
prim__bufferSizeIO : Buffer -> Int

||| A new zeroed buffer of `n` bytes (`n` not negative).
export %inline
bufNew : Int -> IO Buffer
bufNew n = fromPrim (prim__newBufferIO n)

||| `copyData`, in IO.
export %inline
bufCopy : (src : Buffer) -> (srcOffset, len : Int) -> (dst : Buffer) -> (dstOffset : Int) -> IO ()
bufCopy s o n d at = fromPrim (prim__copyDataIO s o n d at)

||| `setBits8`, in IO.
export %inline
bufSetByte : Buffer -> Int -> Bits8 -> IO ()
bufSetByte b i w = fromPrim (prim__setBits8IO b i w)

||| The size of a buffer.
export %inline
bufSize : Buffer -> Int
bufSize = prim__bufferSizeIO

--------------------------------------------------------------------------
-- Comparison
--------------------------------------------------------------------------

-- (The loops below take the buffers and offsets of the byte strings, so
-- that a step does not take the byte strings apart again.)

eqIgnoreCaseFrom : Buffer -> Int -> Buffer -> Int -> (i, n : Int) -> Bool
eqIgnoreCaseFrom xb xo yb yo i n =
  if i >= n then True
  else if toLowerByte (unsafeBufferByte xb (xo + i)) == toLowerByte (unsafeBufferByte yb (yo + i))
          then eqIgnoreCaseFrom xb xo yb yo (assert_smaller i (i + 1)) n
          else False

eqLowerFrom : Buffer -> Int -> Buffer -> Int -> (i, n : Int) -> Bool
eqLowerFrom xb xo yb yo i n =
  if i >= n then True
  else if toLowerByte (unsafeBufferByte xb (xo + i)) == unsafeBufferByte yb (yo + i)
          then eqLowerFrom xb xo yb yo (assert_smaller i (i + 1)) n
          else False

||| Equal as ASCII with the case of letters ignored.  Does not allocate.
export
eqIgnoreCase : ByteString -> ByteString -> Bool
eqIgnoreCase (UnsafeBS xb xo xn) (UnsafeBS yb yo yn) =
  xn == yn && eqIgnoreCaseFrom xb xo yb yo 0 xn

||| Does the byte string, with ASCII case ignored, equal the second one,
||| which must be in lower case?  Cheaper than `eqIgnoreCase`.
export
eqLower : ByteString -> (lower : ByteString) -> Bool
eqLower (UnsafeBS xb xo xn) (UnsafeBS yb yo yn) =
  xn == yn && eqLowerFrom xb xo yb yo 0 xn

hasUpperFrom : Buffer -> (i, e : Int) -> Bool
hasUpperFrom b i e =
  if i >= e then False
  else let w = unsafeBufferByte b i in
       if w >= 65 && w <= 90 then True else hasUpperFrom b (assert_smaller i (i + 1)) e

lowerInto : Buffer -> Int -> Buffer -> (i, n : Int) -> IO ()
lowerInto src o dst i n =
  if i >= n then pure () else do
    () <- bufSetByte dst i (toLowerByte (unsafeBufferByte src (o + i)))
    lowerInto src o dst (assert_smaller i (i + 1)) n

||| The byte string with ASCII letters in lower case.  Returns its argument
||| (without copying) if it has no upper-case letter.
export
lowerAscii : ByteString -> ByteString
lowerAscii bs@(UnsafeBS b o n) =
  if hasUpperFrom b o (o + n) then unsafeCreate n (\dst => lowerInto b o dst 0 n) else bs

--------------------------------------------------------------------------
-- Trimming
--------------------------------------------------------------------------

||| Without leading and trailing spaces and horizontal tabs.
export
trimOWS : ByteString -> ByteString
trimOWS bs =
  let s = front 0
      e = back (lengthInt bs)
  in if s >= e then takeInt 0 bs else sliceFromTo s e bs
  where
    front : Int -> Int
    front i = if i < lengthInt bs && isOWS (unsafeIndex bs i)
                 then front (assert_smaller i (i + 1)) else i
    back : Int -> Int
    back i = if i > 0 && isOWS (unsafeIndex bs (i - 1))
                then back (assert_smaller i (i - 1)) else i

||| Does a comma-separated list hold the token (compared ignoring case),
||| with optional whitespace around the elements?  Does not allocate.
export
listHasToken : (token, list : ByteString) -> Bool
listHasToken tok v = go 0 0
  where
    elemIs : Int -> Int -> Bool
    elemIs s e = eqIgnoreCase (trimOWS (sliceFromTo s e v)) tok
    go : Int -> Int -> Bool
    go s i =
      if i >= lengthInt v then elemIs s i
      else if unsafeIndex v i == 44
              then if elemIs s i then True else go (i + 1) (assert_smaller i (i + 1))
              else go s (assert_smaller i (i + 1))

--------------------------------------------------------------------------
-- Numbers
--------------------------------------------------------------------------

-- The largest value that `parseDecimal` accepts: 2^62 - 1, so that the
-- arithmetic cannot overflow on any back end with 64-bit `Int`.
maxDecimal : Int
maxDecimal = 0x3FFFFFFFFFFFFFFF

decimalFrom : Buffer -> (i, e : Int) -> Int -> Int
decimalFrom b i e acc =
  if i >= e then acc
  else let w = unsafeBufferByte b i in
       if isDigit w
          then let acc' = acc * 10 + (cast w - 48) in
               if acc' > maxDecimal || acc > 0x0666666666666666
                  then -1 else decimalFrom b (assert_smaller i (i + 1)) e acc'
          else -1

||| A non-empty run of decimal digits as a number, or `-1` if the byte
||| string is empty, has a byte that is not a digit, or is above 2^62 - 1.
export
parseDecimal : ByteString -> Int
parseDecimal (UnsafeBS b o n) = if n == 0 then -1 else decimalFrom b o (o + n) 0

||| `n` divided by 10, rounded towards zero.
export %inline
quot10 : Int -> Int
quot10 n = assert_total (prim__div_Int n 10)

||| The remainder of `n` divided by 10 (of the sign of `n`).
export %inline
rem10 : Int -> Int
rem10 n = assert_total (prim__mod_Int n 10)

||| The decimal digits of a non-negative number.
export
decimalBytes : Int -> ByteString
decimalBytes n =
  if n <= 0 then Data.ByteString.singleton 48
  else let k = digits n 0 in
       unsafeCreate k (\buf => fill buf (k - 1) n)
  where
    digits : Int -> Int -> Int
    digits m acc = if m <= 0 then acc else digits (assert_smaller m (quot10 m)) (acc + 1)
    fill : Buffer -> Int -> Int -> IO ()
    fill buf i m =
      if i < 0 then pure ()
      else do setBits8 buf i (cast (48 + rem10 m))
              fill buf (assert_smaller i (i - 1)) (quot10 m)

||| The lower-case hexadecimal digits of a non-negative number (no leading
||| zeros; `"0"` for zero).
export
hexBytes : Int -> ByteString
hexBytes n =
  if n <= 0 then Data.ByteString.singleton 48
  else let k = digits n 0 in
       unsafeCreate k (\buf => fill buf (k - 1) n)
  where
    digits : Int -> Int -> Int
    digits m acc = if m <= 0 then acc else digits (assert_smaller m (m `shiftR` 4)) (acc + 1)
    hexDigit : Int -> Bits8
    hexDigit d = if d < 10 then cast (48 + d) else cast (87 + d)
    fill : Buffer -> Int -> Int -> IO ()
    fill buf i m =
      if i < 0 then pure ()
      else do setBits8 buf i (hexDigit (m .&. 15))
              fill buf (assert_smaller i (i - 1)) (m `shiftR` 4)

