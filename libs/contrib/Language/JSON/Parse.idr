||| A strict JSON parser that reads bytes (RFC 8259).
|||
||| ```idris
||| import Data.ByteString
||| import Language.JSON.Parse
|||
||| example : Either JSONError JSON
||| example = parseBytes (fromString "{\"a\": [1, 2.5, null]}")
||| ```
|||
||| The parser reads the bytes of a `ByteString` once, from left to right,
||| and builds the `JSON` value as it goes.  It accepts exactly the documents
||| of RFC 8259 and rejects everything else with the byte offset of the
||| problem and the reason:
|||
|||  * whitespace is space, tab, line feed and carriage return only, and a
|||    byte order mark is not skipped;
|||  * a trailing comma in an array or object, a number with a leading zero
|||    (`01`), a `.` or exponent without digits and a `+` sign are errors;
|||  * a string must be valid UTF-8 (no overlong forms, no encoded
|||    surrogates, nothing above U+10FFFF) and must not contain the control
|||    characters U+0000..U+001F unescaped;
|||  * a `\u` escape of a high surrogate (`\uD800`..`\uDBFF`) must be followed
|||    by a `\u` escape of a low surrogate, and the pair stands for one
|||    character; any other surrogate escape is an error (`LoneSurrogate`),
|||    because an Idris `String` cannot hold it;
|||  * after the value only whitespace may follow;
|||  * arrays and objects may be nested `maxDepth` deep (512 by default, see
|||    `ParseOptions`), so that hostile input cannot exhaust the stack.
|||
||| Duplicate keys are kept, in the order in which they appear.
|||
||| Numbers become a `Double`, correctly rounded: a number with at most 15
||| significant digits and a decimal exponent of at most 22 in magnitude is
||| computed exactly with one multiplication or division of two exact
||| doubles, and any other number is converted by the backend's
||| `cast {to = Double}` of its text (`strtod` with RefC).  So an integer
||| beyond 2^53 in magnitude loses precision, as in JavaScript.  A number
||| that is too large for a `Double` becomes an infinity.
module Language.JSON.Parse

import Data.Bits
import Data.Buffer
import Data.ByteString
import Data.ByteString.Internal

import public Language.JSON.Data

%default total

------------------------------------------------------------------------
-- Errors
------------------------------------------------------------------------

||| Why a document is not JSON.
public export
data JSONErrorReason : Type where
  ||| The input ends where the argument (what was expected) should be.
  UnexpectedEnd : (expected : String) -> JSONErrorReason
  ||| A byte that cannot start what was expected.
  UnexpectedByte : (found : Bits8) -> (expected : String) -> JSONErrorReason
  ||| A number with a leading zero, such as `01`.
  LeadingZero : JSONErrorReason
  ||| A number that is cut short: `-`, `1.`, `1e`, `1e+`.
  InvalidNumber : JSONErrorReason
  ||| A backslash followed by something other than `"\/bfnrtu`.
  InvalidEscape : JSONErrorReason
  ||| `\u` not followed by four hexadecimal digits.
  InvalidUnicodeEscape : JSONErrorReason
  ||| A `\u` escape of a surrogate that is not part of a high-low pair.
  LoneSurrogate : JSONErrorReason
  ||| An unescaped control character (U+0000..U+001F) in a string.
  ControlCharacter : Bits8 -> JSONErrorReason
  ||| Bytes in a string that are not valid UTF-8.
  InvalidUtf8 : JSONErrorReason
  ||| A string without its closing quote (the offset is that of the
  ||| opening quote).
  UnterminatedString : JSONErrorReason
  ||| A comma right before `]` or `}`.
  TrailingComma : JSONErrorReason
  ||| Arrays and objects are nested deeper than the limit.
  TooDeep : (limit : Nat) -> JSONErrorReason
  ||| Something other than whitespace after the value.
  TrailingGarbage : JSONErrorReason

-- A byte as a character, or in hexadecimal if it is not printable ASCII.
showByte : Bits8 -> String
showByte b =
  if b >= 0x20 && b < 0x7F
     then show (cast {to = Char} (cast {to = Int} b))
     else "byte 0x" ++ hex2 b
  where
    digit : Bits8 -> String
    digit n = cast {to = String} (if n < 10 then chr (48 + cast n) else chr (87 + cast n))

    hex2 : Bits8 -> String
    hex2 n = digit (shiftR n 4) ++ digit (n .&. 15)

||| An English description of the reason.
export
Show JSONErrorReason where
  show (UnexpectedEnd e) = "unexpected end of input, expected " ++ e
  show (UnexpectedByte b e) = "unexpected " ++ showByte b ++ ", expected " ++ e
  show LeadingZero = "leading zero in a number"
  show InvalidNumber = "invalid number"
  show InvalidEscape = "invalid escape sequence"
  show InvalidUnicodeEscape = "invalid \\u escape (expected four hexadecimal digits)"
  show LoneSurrogate = "\\u escape of a surrogate that is not part of a pair"
  show (ControlCharacter b) = "unescaped control character " ++ showByte b ++ " in a string"
  show InvalidUtf8 = "invalid UTF-8 in a string"
  show UnterminatedString = "unterminated string"
  show TrailingComma = "trailing comma"
  show (TooDeep n) = "arrays and objects nested deeper than " ++ show n
  show TrailingGarbage = "unexpected data after the JSON value"

||| Equality of reasons, for tests.
export
Eq JSONErrorReason where
  a == b = show a == show b

||| A document that is not JSON: the offset of the offending byte from the
||| start of the input (counting from 0) and the reason.  Use `errorLocation`
||| for a line and column.
public export
record JSONError where
  constructor MkJSONError
  offset : Nat
  reason : JSONErrorReason

||| `byte <offset>: <reason>`.  See `showErrorIn` for a line and a column.
export
Show JSONError where
  show e = "byte " ++ show e.offset ++ ": " ++ show e.reason

||| Same offset and reason.
export
Eq JSONError where
  a == b = a.offset == b.offset && a.reason == b.reason

||| The line and column (both counting from 1) of a byte offset in the
||| input.  Lines end at line feeds; a column counts characters (UTF-8
||| sequences), not bytes.  Linear in the offset; meant for error messages.
export
location : ByteString -> (offset : Nat) -> (Nat, Nat)
location bs off = go (cast {to = Nat} stop) 0 1 1
  where
    stop : Int
    stop = min (cast off) (lengthInt bs)

    go : Nat -> Int -> Nat -> Nat -> (Nat, Nat)
    go Z _ l c = (l, c)
    go (S k) i l c =
      let b = unsafeIndex bs i in
      if b == 10 then go k (i + 1) (S l) 1
      else if (b .&. 0xC0) == 0x80 then go k (i + 1) l c
      else go k (i + 1) l (S c)

||| The line and column of an error in the input that it is about.
export
errorLocation : ByteString -> JSONError -> (Nat, Nat)
errorLocation bs e = location bs e.offset

||| `line <l>, column <c> (byte <offset>): <reason>`.
export
showErrorIn : ByteString -> JSONError -> String
showErrorIn bs e =
  let (l, c) = errorLocation bs e in
  "line " ++ show l ++ ", column " ++ show c ++ " (byte " ++ show e.offset ++ "): " ++ show e.reason

------------------------------------------------------------------------
-- Options
------------------------------------------------------------------------

||| Limits of the parser.
public export
record ParseOptions where
  constructor MkParseOptions
  ||| How deep arrays and objects may be nested.  Every level takes a few
  ||| frames of the C stack (RefC) or of the Scheme stack, so a limit in the
  ||| thousands is safe, and one in the millions is not.
  maxDepth : Nat

||| A nesting depth of 512.
export
defaultParseOptions : ParseOptions
defaultParseOptions = MkParseOptions 512

------------------------------------------------------------------------
-- The scanner.  Positions are offsets in the buffer; `end` is the offset
-- just after the last byte of the input.  The loops are written on `Int`
-- and `Bits8` with explicit accumulators so that they compile to loops.
------------------------------------------------------------------------

-- The byte at a position.  The buffer is never written (see
-- `Data.ByteString.Internal`), so reading it is pure.
%inline
byteAt : Buffer -> Int -> Bits8
byteAt = unsafeBufferByte

-- (the bytes have been checked to be UTF-8)
%inline
bytesToString : Buffer -> Int -> Int -> String
bytesToString = unsafeBufferString

-- A value and the position after it, or an error.
data Res : Type where
  ROk : JSON -> Int -> Res
  RErr : Int -> JSONErrorReason -> Res

-- A string and the position after it, or an error.
data SRes : Type where
  SOk : String -> Int -> SRes
  SErr : Int -> JSONErrorReason -> SRes

%inline
isWs : Bits8 -> Bool
isWs b = b == 32 || b == 10 || b == 13 || b == 9

covering
skipWs : Buffer -> Int -> Int -> Int
skipWs buf end i =
  if i < end && isWs (byteAt buf i) then skipWs buf end (i + 1) else i

%inline
isCont : Bits8 -> Bool
isCont b = (b .&. 0xC0) == 0x80

-- The length of the UTF-8 sequence that starts with the byte at `i`, which
-- is at least 0x80, or 0 if it is not a valid sequence (the rules of
-- `Data.ByteString.toString`).
utf8Width : Buffer -> Int -> Int -> Int
utf8Width buf end i =
  let b0 = byteAt buf i in
  if b0 < 0xC2 then 0
  else if b0 < 0xE0 then
    (if i + 1 < end && isCont (byteAt buf (i + 1)) then 2 else 0)
  else if b0 < 0xF0 then
    (if i + 2 < end
        then let b1 = byteAt buf (i + 1)
                 b2 = byteAt buf (i + 2) in
             if isCont b1 && isCont b2
                && (b0 /= 0xE0 || b1 >= 0xA0)
                && (b0 /= 0xED || b1 < 0xA0)
                then 3 else 0
        else 0)
  else if b0 < 0xF5 then
    (if i + 3 < end
        then let b1 = byteAt buf (i + 1)
                 b2 = byteAt buf (i + 2)
                 b3 = byteAt buf (i + 3) in
             if isCont b1 && isCont b2 && isCont b3
                && (b0 /= 0xF0 || b1 >= 0x90)
                && (b0 /= 0xF4 || b1 < 0x90)
                then 4 else 0
        else 0)
  else 0

-- The value of a hexadecimal digit, or -1.
hexVal : Bits8 -> Int
hexVal b =
  if b >= 48 && b <= 57 then cast b - 48
  else if b >= 97 && b <= 102 then cast b - 87
  else if b >= 65 && b <= 70 then cast b - 55
  else -1

-- The four hexadecimal digits at `i`, or -1.
hex4 : Buffer -> Int -> Int -> Int
hex4 buf end i =
  if i + 4 > end then -1
  else let a = hexVal (byteAt buf i)
           b = hexVal (byteAt buf (i + 1))
           c = hexVal (byteAt buf (i + 2))
           d = hexVal (byteAt buf (i + 3)) in
       if a < 0 || b < 0 || c < 0 || d < 0 then -1
       else a * 4096 + b * 256 + c * 16 + d

-- The number of bytes of the UTF-8 form of a code point.
cpWidth : Int -> Int
cpWidth cp = if cp < 0x80 then 1 else if cp < 0x800 then 2 else if cp < 0x10000 then 3 else 4

-- The value of a simple escape (the byte after the backslash), or -1.
simpleEscape : Bits8 -> Int
simpleEscape e =
  if e == 34 then 34
  else if e == 92 then 92
  else if e == 47 then 47
  else if e == 98 then 8
  else if e == 102 then 12
  else if e == 110 then 10
  else if e == 114 then 13
  else if e == 116 then 9
  else -1

-- The result of measuring a string with escapes: the position of the
-- closing quote and the number of bytes of the decoded string.
data MRes : Type where
  MOk : (quote : Int) -> (len : Int) -> MRes
  MErr : Int -> JSONErrorReason -> MRes

-- Check the rest of a string that has an escape, from `i` (with `n`
-- decoded bytes so far), and measure it.  `opn` is the position of the
-- opening quote.
covering
measure : Buffer -> Int -> (opn : Int) -> (i : Int) -> (n : Int) -> MRes
measure buf end opn i n =
  if i >= end then MErr opn UnterminatedString else
  let b = byteAt buf i in
  if b == 34 then MOk i n
  else if b == 92 then
    (if i + 1 >= end then MErr opn UnterminatedString else
     let e = byteAt buf (i + 1) in
     if e == 117 -- u
        then let cp = hex4 buf end (i + 2) in
             if cp < 0 then MErr i InvalidUnicodeEscape
             else if cp >= 0xD800 && cp < 0xDC00
               then (if i + 7 < end && byteAt buf (i + 6) == 92 && byteAt buf (i + 7) == 117
                        then let lo = hex4 buf end (i + 8) in
                             if lo < 0 then MErr (i + 6) InvalidUnicodeEscape
                             else if lo >= 0xDC00 && lo < 0xE000
                               then measure buf end opn (i + 12) (n + 4)
                               else MErr i LoneSurrogate
                        else MErr i LoneSurrogate)
             else if cp >= 0xDC00 && cp < 0xE000 then MErr i LoneSurrogate
             else measure buf end opn (i + 6) (n + cpWidth cp)
        else if simpleEscape e >= 0 then measure buf end opn (i + 2) (n + 1)
        else MErr i InvalidEscape)
  else if b < 32 then MErr i (ControlCharacter b)
  else if b < 128 then measure buf end opn (i + 1) (n + 1)
  else let w = utf8Width buf end i in
       if w == 0 then MErr i InvalidUtf8 else measure buf end opn (i + w) (n + w)

-- Write a code point as UTF-8 at `o`, and give the position after it.
putCp : Buffer -> Int -> Int -> (1 w : %World) -> IORes Int
putCp dst o cp w =
  if cp < 0x80
     then case toPrim (setBits8 dst o (cast cp)) w of
            MkIORes () w => MkIORes (o + 1) w
  else if cp < 0x800
     then case toPrim (setBits8 dst o (cast (0xC0 .|. shiftR cp 6))) w of
            MkIORes () w => case toPrim (setBits8 dst (o + 1) (cast (0x80 .|. (cp .&. 0x3F)))) w of
              MkIORes () w => MkIORes (o + 2) w
  else if cp < 0x10000
     then case toPrim (setBits8 dst o (cast (0xE0 .|. shiftR cp 12))) w of
            MkIORes () w => case toPrim (setBits8 dst (o + 1) (cast (0x80 .|. (shiftR cp 6 .&. 0x3F)))) w of
              MkIORes () w => case toPrim (setBits8 dst (o + 2) (cast (0x80 .|. (cp .&. 0x3F)))) w of
                MkIORes () w => MkIORes (o + 3) w
  else case toPrim (setBits8 dst o (cast (0xF0 .|. shiftR cp 18))) w of
         MkIORes () w => case toPrim (setBits8 dst (o + 1) (cast (0x80 .|. (shiftR cp 12 .&. 0x3F)))) w of
           MkIORes () w => case toPrim (setBits8 dst (o + 2) (cast (0x80 .|. (shiftR cp 6 .&. 0x3F)))) w of
             MkIORes () w => case toPrim (setBits8 dst (o + 3) (cast (0x80 .|. (cp .&. 0x3F)))) w of
               MkIORes () w => MkIORes (o + 4) w

-- Decode the checked bytes `[i, stop)` of a string with escapes into `dst`
-- from `o`.
covering
unescape : Buffer -> Buffer -> (i : Int) -> (stop : Int) -> (o : Int) ->
           (1 w : %World) -> IORes ()
unescape buf dst i stop o w =
  if i >= stop then MkIORes () w else
  let b = byteAt buf i in
  if b /= 92
     then case toPrim (setBits8 dst o b) w of
            MkIORes () w => unescape buf dst (i + 1) stop (o + 1) w
     else let e = byteAt buf (i + 1) in
          if e == 117
             then let cp = hex4 buf stop (i + 2) in
                  if cp >= 0xD800 && cp < 0xDC00
                     then let lo = hex4 buf stop (i + 8)
                              full = 0x10000 + shiftL (cp - 0xD800) 10 + (lo - 0xDC00) in
                          case putCp dst o full w of
                            MkIORes o' w => unescape buf dst (i + 12) stop o' w
                     else case putCp dst o cp w of
                            MkIORes o' w => unescape buf dst (i + 6) stop o' w
             else case toPrim (setBits8 dst o (cast (simpleEscape e))) w of
                    MkIORes () w => unescape buf dst (i + 2) stop (o + 1) w

-- A string with an escape at `i`; it starts at `start` (after the quote).
covering
escapedString : Buffer -> Int -> (start : Int) -> (i : Int) -> SRes
escapedString buf end start i =
  case measure buf end (start - 1) i (i - start) of
    MErr p r => SErr p r
    MOk q n => SOk (unsafePerformIO (fill q n)) (q + 1)
  where
    fill : Int -> Int -> IO String
    fill q n = do
      Just dst <- newBuffer n
        | Nothing => pure ""
      copyData buf start (i - start) dst 0
      fromPrim (unescape buf dst i q (i - start))
      getString dst 0 n

-- Is a byte of the four (a little-endian word) a quote, a backslash, a
-- control character or not ASCII?  (May say yes when none is, after a byte
-- that is: the borrows of the subtractions; never no when one is.)
%inline
hasZero : Bits32 -> Bits32
hasZero y = (y - 0x01010101) .&. complement y

%inline
special4 : Bits32 -> Bool
special4 x =
  ((x .|. (x - 0x20202020) .|. hasZero (x `xor` 0x22222222) .|. hasZero (x `xor` 0x5C5C5C5C))
     .&. 0x80808080) /= 0

-- The rest of a string from `i`; it starts at `start` (after the quote).
covering
scanString : Buffer -> Int -> (start : Int) -> (i : Int) -> SRes
scanString buf end start i =
  if i + 4 <= end && not (special4 (unsafeBufferWord32LE buf i))
     then scanString buf end start (i + 4) else
  if i >= end then SErr (start - 1) UnterminatedString else
  let b = byteAt buf i in
  if b == 34 then SOk (bytesToString buf start (i - start)) (i + 1)
  else if b == 92 then escapedString buf end start i
  else if b < 32 then SErr i (ControlCharacter b)
  else if b < 128 then scanString buf end start (i + 1)
  else let w = utf8Width buf end i in
       if w == 0 then SErr i InvalidUtf8 else scanString buf end start (i + w)

------------------------------------------------------------------------
-- Numbers
------------------------------------------------------------------------

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

-- The Double of the number text `[start, i)`, which has been checked.
-- `m` holds its first significant digits (all of them if `nd <= 15`), as
-- a `Double` (exact: below 10^15; and an `Int` has only 32 bits with the
-- JavaScript backends), `nd` is the number of significant digits, `fd`
-- that of the digits after the point that are in `m`, and `ex` the exponent
-- (capped).
numberValue : Buffer -> (start : Int) -> (i : Int) -> (neg : Bool) ->
              (m : Double) -> (nd : Int) -> (fd : Int) -> (ex : Int) -> Double
numberValue buf start i neg m nd fd ex =
  let e10 = ex - fd in
  if nd == 0 then (if neg then -0.0 else 0.0)
  else if nd <= 15 && e10 >= -22 && e10 <= 22
    then let r = if e10 >= 0 then m * pow10 e10 else m / pow10 (negate e10) in
         if neg then negate r else r
    else cast (bytesToString buf start (i - start))

%inline
isDig : Bits8 -> Bool
isDig b = b >= 48 && b <= 57

-- Add a digit to the mantissa and the count of significant digits.
%inline
addM : Double -> Int -> Bits8 -> Double
addM m nd b = if nd < 15 then m * 10.0 + cast (the Int (cast b - 48)) else m

%inline
addNd : Int -> Bits8 -> Int
addNd nd b = if nd == 0 && b == 48 then nd else nd + 1

-- The end of a number at `i`.
numDone : Buffer -> (start : Int) -> (i : Int) -> (neg : Bool) ->
          (m : Double) -> (nd : Int) -> (fd : Int) -> (ex : Int) -> (eneg : Bool) -> Res
numDone buf start i neg m nd fd ex eneg =
  ROk (JNumber (numberValue buf start i neg m nd fd (if eneg then negate ex else ex))) i

-- The number states: 1 after the integer digits (the first not a zero),
-- 2 after a leading zero, 3 after the point, 4 in the fraction digits, 5
-- after the `e`, 6 after its sign, 7 in the exponent digits.
covering
numLoop : Buffer -> Int -> (start : Int) -> (neg : Bool) -> (st : Int) ->
          (i : Int) -> (m : Double) -> (nd : Int) -> (fd : Int) ->
          (ex : Int) -> (eneg : Bool) -> Res
numLoop buf end start neg st i m nd fd ex eneg =
  let b = the Bits8 (if i < end then byteAt buf i else 0)
  in case st of
       1 => if isDig b then numLoop buf end start neg 1 (i + 1) (addM m nd b) (addNd nd b) fd ex eneg
            else if b == 46 then numLoop buf end start neg 3 (i + 1) m nd fd ex eneg
            else if b == 101 || b == 69 then numLoop buf end start neg 5 (i + 1) m nd fd ex eneg
            else numDone buf start i neg m nd fd ex eneg
       2 => if isDig b then RErr i LeadingZero
            else if b == 46 then numLoop buf end start neg 3 (i + 1) m nd fd ex eneg
            else if b == 101 || b == 69 then numLoop buf end start neg 5 (i + 1) m nd fd ex eneg
            else numDone buf start i neg m nd fd ex eneg
       3 => if isDig b
               then numLoop buf end start neg 4 (i + 1) (addM m nd b) (addNd nd b)
                            (if nd < 15 then fd + 1 else fd) ex eneg
               else RErr i InvalidNumber
       4 => if isDig b
               then numLoop buf end start neg 4 (i + 1) (addM m nd b) (addNd nd b)
                            (if nd < 15 then fd + 1 else fd) ex eneg
            else if b == 101 || b == 69 then numLoop buf end start neg 5 (i + 1) m nd fd ex eneg
            else numDone buf start i neg m nd fd ex eneg
       5 => if b == 43 || b == 45 then numLoop buf end start neg 6 (i + 1) m nd fd ex (b == 45)
            else if isDig b then numLoop buf end start neg 7 (i + 1) m nd fd (cast b - 48) eneg
            else RErr i InvalidNumber
       6 => if isDig b then numLoop buf end start neg 7 (i + 1) m nd fd (cast b - 48) eneg
            else RErr i InvalidNumber
       _ => if isDig b
               then numLoop buf end start neg 7 (i + 1) m nd fd
                            (if ex < 100000 then ex * 10 + (cast b - 48) else ex) eneg
               else numDone buf start i neg m nd fd ex eneg

-- A number that starts at `i` (with a `-` or a digit).
covering
number : Buffer -> Int -> Int -> Res
number buf end start =
  let neg = byteAt buf start == 45
      i = if neg then start + 1 else start
      b = the Bits8 (if i < end then byteAt buf i else 0)
  in if b == 48 then numLoop buf end start neg 2 (i + 1) 0.0 0 0 0 False
     else if isDig b then numLoop buf end start neg 1 (i + 1) (cast (the Int (cast b - 48))) 1 0 0 False
     else if i >= end then RErr i (UnexpectedEnd "a digit")
     else RErr i InvalidNumber

------------------------------------------------------------------------
-- Values
------------------------------------------------------------------------

-- Do the bytes at `i` spell the ASCII word?
matchWord : Buffer -> Int -> Int -> List Bits8 -> Bool
matchWord buf end i [] = True
matchWord buf end i (c :: cs) = i < end && byteAt buf i == c && matchWord buf end (i + 1) cs

trueBytes, falseBytes, nullBytes : List Bits8
trueBytes = [116, 114, 117, 101]
falseBytes = [102, 97, 108, 115, 101]
nullBytes = [110, 117, 108, 108]

expectedValue : String
expectedValue = "a value"

expectedArraySep : String
expectedArraySep = "',' or ']'"

expectedObjectSep : String
expectedObjectSep = "',' or '}'"

expectedKey : String
expectedKey = "a string (an object key)"

expectedColon : String
expectedColon = "':'"

-- `UnexpectedEnd` at the end and `UnexpectedByte` elsewhere.
unexpected : Buffer -> Int -> Int -> String -> Res
unexpected buf end i what =
  if i >= end then RErr i (UnexpectedEnd what) else RErr i (UnexpectedByte (byteAt buf i) what)

mutual
  -- A value at `i` (after whitespace), at nesting depth `d`.
  covering
  value : Buffer -> Int -> (maxD : Int) -> (d : Int) -> Int -> Res
  value buf end maxD d i =
    if i >= end then RErr i (UnexpectedEnd expectedValue) else
    let b = byteAt buf i in
    if b == 34 then
      (case scanString buf end (i + 1) (i + 1) of
         SOk s p => ROk (JString s) p
         SErr p r => RErr p r)
    else if b == 123 then
      (if d >= maxD then RErr i (TooDeep (cast maxD)) else object buf end maxD (d + 1) (i + 1))
    else if b == 91 then
      (if d >= maxD then RErr i (TooDeep (cast maxD)) else array buf end maxD (d + 1) (i + 1))
    else if b == 45 || isDig b then number buf end i
    else if b == 116 then
      (if matchWord buf end i trueBytes then ROk (JBoolean True) (i + 4) else unexpected buf end i expectedValue)
    else if b == 102 then
      (if matchWord buf end i falseBytes then ROk (JBoolean False) (i + 5) else unexpected buf end i expectedValue)
    else if b == 110 then
      (if matchWord buf end i nullBytes then ROk JNull (i + 4) else unexpected buf end i expectedValue)
    else RErr i (UnexpectedByte b expectedValue)

  -- After `[`.
  covering
  array : Buffer -> Int -> Int -> Int -> Int -> Res
  array buf end maxD d i =
    let j = skipWs buf end i in
    if j < end && byteAt buf j == 93 then ROk (JArray []) (j + 1)
    else elements buf end maxD d j []

  -- The elements of an array from `i` (after whitespace), in reverse order
  -- so far.
  covering
  elements : Buffer -> Int -> Int -> Int -> Int -> List JSON -> Res
  elements buf end maxD d i acc =
    case value buf end maxD d i of
      RErr p r => RErr p r
      ROk v p =>
        let j = skipWs buf end p in
        if j >= end then RErr j (UnexpectedEnd expectedArraySep) else
        let b = byteAt buf j in
        if b == 44 then
          (let k = skipWs buf end (j + 1) in
           if k < end && byteAt buf k == 93 then RErr j TrailingComma
           else elements buf end maxD d k (v :: acc))
        else if b == 93 then ROk (JArray (reverse (v :: acc))) (j + 1)
        else RErr j (UnexpectedByte b expectedArraySep)

  -- After `{`.
  covering
  object : Buffer -> Int -> Int -> Int -> Int -> Res
  object buf end maxD d i =
    let j = skipWs buf end i in
    if j < end && byteAt buf j == 125 then ROk (JObject []) (j + 1)
    else members buf end maxD d j []

  -- The members of an object from `i` (after whitespace), in reverse order
  -- so far.
  covering
  members : Buffer -> Int -> Int -> Int -> Int -> List (String, JSON) -> Res
  members buf end maxD d i acc =
    if i >= end || byteAt buf i /= 34 then unexpected buf end i expectedKey else
    case scanString buf end (i + 1) (i + 1) of
      SErr p r => RErr p r
      SOk key p =>
        let c = skipWs buf end p in
        if c >= end || byteAt buf c /= 58 then unexpected buf end c expectedColon else
        case value buf end maxD d (skipWs buf end (c + 1)) of
          RErr p r => RErr p r
          ROk v p =>
            let j = skipWs buf end p in
            if j >= end then RErr j (UnexpectedEnd expectedObjectSep) else
            let b = byteAt buf j in
            if b == 44 then
              (let k = skipWs buf end (j + 1) in
               if k < end && byteAt buf k == 125 then RErr j TrailingComma
               else members buf end maxD d k ((key, v) :: acc))
            else if b == 125 then ROk (JObject (reverse ((key, v) :: acc))) (j + 1)
            else RErr j (UnexpectedByte b expectedObjectSep)

------------------------------------------------------------------------
-- Reading values in place, for decoders that do not build a `JSON` value
-- (see `fromJSONAt` of `Language.JSON.Typed`).  Positions are offsets in
-- the buffer of the input and `end` is the offset after its last byte, as
-- above.  These accept exactly what the parser accepts, and say only
-- whether it worked: a decoder that fails parses the input again with
-- `parseBytesWith` to find the error.
------------------------------------------------------------------------

||| The input of a decoder in place: the buffer of the bytes, the offset
||| after the last of them, and how deep the arrays and objects around the
||| value being decoded are nested, and may be.
export
data Input : Type where
  MkInput : Buffer -> (end : Int) -> (maxDepth, depth : Int) -> Input

||| The input of the bytes of a byte string, for values nested at most
||| `maxDepth` deep, and the position of its first byte.
export
inputOf : (maxDepth : Int) -> ByteString -> (Input, Int)
inputOf maxD bs = (MkInput (unsafeBuffer bs) (unsafeOffset bs + lengthInt bs) maxD 0, unsafeOffset bs)

||| Is the position at the end of the input?
export
atEnd : Input -> Int -> Bool
atEnd (MkInput _ end _ _) pos = pos >= end

||| The input for the values inside an array or object (one level deeper),
||| or `Nothing` if they would be nested too deep.
export
enter : Input -> Maybe Input
enter (MkInput b e m d) = if d >= m then Nothing else Just (MkInput b e m (d + 1))

||| A value read in place and the position after it, or a failure.
public export
data Step : Type -> Type where
  StepOk : a -> (next : Int) -> Step a
  StepFail : Step a

||| The position after the whitespace at `pos`.
export
skipWsAt : Input -> (pos : Int) -> Int
skipWsAt (MkInput buf end _ _) pos = assert_total (skipWs buf end pos)

||| Any value at `pos` (after whitespace).
export
valueAt : Input -> (pos : Int) -> Step JSON
valueAt (MkInput buf end maxD d) pos = case assert_total (value buf end maxD d pos) of
  ROk v p => StepOk v p
  RErr _ _ => StepFail

||| A string at `pos` (its opening quote).
export
stringAt : Input -> (pos : Int) -> Step String
stringAt (MkInput buf end _ _) pos =
  if pos >= end || byteAt buf pos /= 34 then StepFail
  else case assert_total (scanString buf end (pos + 1) (pos + 1)) of
         SOk s p => StepOk s p
         SErr _ _ => StepFail

||| A number at `pos`, given to the continuation with the position after
||| it (so that no value is made for the pair).
export
numberAt : Input -> (pos : Int) -> (Double -> Int -> Step a) -> Step a
numberAt (MkInput buf end _ _) pos k =
  if pos >= end then StepFail else
  let b = byteAt buf pos in
  if b == 45 || isDig b
     then case assert_total (number buf end pos) of
            ROk (JNumber x) p => k x p
            _ => StepFail
     else StepFail

||| `true` or `false` at `pos`: 1 or 0, or -1.
export
boolAt : Input -> (pos : Int) -> Int
boolAt (MkInput buf end _ _) pos =
  if matchWord buf end pos trueBytes then 1
  else if matchWord buf end pos falseBytes then 0
  else -1

||| Is there `null` at `pos`?
export
nullAt : Input -> (pos : Int) -> Bool
nullAt (MkInput buf end _ _) pos = matchWord buf end pos nullBytes

||| The byte at `pos`, or 0 at the end.
export
byteAtOr0 : Input -> (pos : Int) -> Bits8
byteAtOr0 (MkInput buf end _ _) pos = if pos < end then byteAt buf pos else 0

||| The key of a member that a decoder looks for (see `keyAt`): its UTF-8
||| bytes, made once.
export
data Key : Type where
  -- The bytes, and whether its literal can be them without escapes (not
  -- for a key with a quote, a backslash or a control character).
  MkKey : ByteString -> (plain : Bool) -> Key

-- Has the byte string a quote, a backslash or a control character?
needsEscape : ByteString -> Int -> Bool
needsEscape bs i =
  if i >= lengthInt bs then False
  else let c = unsafeIndex bs i in
       c == 34 || c == 92 || c < 32 || needsEscape bs (assert_smaller i (i + 1))

||| The key of a member, for `keyAt`.
export
jsonKey : String -> Key
jsonKey k = let bs = fromString k in MkKey bs (not (needsEscape bs 0))

||| The key of a member of an object at `pos` (after whitespace), as a
||| string literal without escapes, and its colon: the position of the
||| value (after whitespace), or -1 if the key there is another one or is
||| written otherwise.  A key with a quote, a backslash or a control
||| character is never found.
export
keyAt : Input -> (pos : Int) -> Key -> Int
keyAt (MkInput buf end _ _) pos (MkKey (UnsafeBS kb ko n) plain) =
  if not plain || pos + n + 2 > end || byteAt buf pos /= 34 then -1
  else if unsafeCompareRange kb ko buf (pos + 1) n /= 0 || byteAt buf (pos + n + 1) /= 34 then -1
  else let c = assert_total (skipWs buf end (pos + n + 2)) in
       if c < end && byteAt buf c == 58 then assert_total (skipWs buf end (c + 1)) else -1

------------------------------------------------------------------------
-- Entry points
------------------------------------------------------------------------

||| Parse a JSON document (RFC 8259) from its bytes, with the given limits.
||| See the module header for what is accepted.  Linear in the input; uses
||| stack in proportion to the nesting depth only.
export
parseBytesWith : ParseOptions -> ByteString -> Either JSONError JSON
parseBytesWith opts bs =
  let buf = unsafeBuffer bs
      off = unsafeOffset bs
      end = off + lengthInt bs
      maxD = cast {to = Int} opts.maxDepth
      res = assert_total (value buf end maxD 0 (skipWs buf end off))
  in case res of
       RErr p r => Left (MkJSONError (cast (p - off)) r)
       ROk v p =>
         let q = assert_total (skipWs buf end p) in
         if q < end then Left (MkJSONError (cast (q - off)) TrailingGarbage) else Right v

||| Parse a JSON document (RFC 8259) from its bytes, with a nesting limit of
||| 512.  See the module header for what is accepted.
export
parseBytes : ByteString -> Either JSONError JSON
parseBytes = parseBytesWith defaultParseOptions

||| Parse a JSON document from a string (its UTF-8 bytes), with a nesting
||| limit of 512.  The offsets of errors count bytes of the UTF-8 form.
export
parseText : String -> Either JSONError JSON
parseText s = parseBytes (fromString s)

||| `parseText` with the given limits.
export
parseTextWith : ParseOptions -> String -> Either JSONError JSON
parseTextWith opts s = parseBytesWith opts (fromString s)
