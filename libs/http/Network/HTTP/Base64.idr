||| Base64 (RFC 4648 sections 4 and 5) over `ByteString`.
|||
||| Two alphabets: the standard one (`+` and `/`, used by MIME, HTTP Basic
||| authentication and the WebSocket handshake) and the URL- and
||| filename-safe one (`-` and `_`, used by JWT and HTTP/2 `HTTP2-Settings`).
||| Encoding pads with `=` unless asked not to.  Decoding is strict, as
||| RFC 4648 section 3.3 allows an implementation to be: it rejects any
||| character outside the alphabet (including whitespace and line breaks),
||| padding in the wrong place or of the wrong amount, a length that no
||| encoding has, and non-zero bits after the last byte (section 3.5), so
||| that every byte string has exactly one accepted encoding.
|||
||| ```idris
||| encode (fromString "foob") == fromString "Zm9vYg=="
||| decode (fromString "Zm9vYg==") == Just (fromString "foob")
||| ```
module Network.HTTP.Base64

import Data.Buffer
import Data.ByteString
import Data.ByteString.Internal

%default total

||| Which of the two alphabets of RFC 4648.
public export
data Alphabet
  = ||| `A-Z a-z 0-9 + /` (section 4).
    Standard
  | ||| `A-Z a-z 0-9 - _` (section 5).
    UrlSafe

||| Whether an encoding ends with `=` padding to a multiple of four
||| characters.
public export
data Padding
  = ||| Padded to a multiple of four characters with `=`.
    Padded
  | ||| No `=`; the length of the last group says how many bytes it holds.
    Unpadded

||| The same alphabet.
export
Eq Alphabet where
  Standard == Standard = True
  UrlSafe == UrlSafe = True
  _ == _ = False

||| The same padding.
export
Eq Padding where
  Padded == Padded = True
  Unpadded == Unpadded = True
  _ == _ = False

--------------------------------------------------------------------------
-- The alphabets, computed (no table to load)
--------------------------------------------------------------------------

-- The character of a 6-bit value.
encodeChar : Bool -> Bits8 -> Bits8
encodeChar url v =
  if v < 26 then v + 65
  else if v < 52 then v + 71
  else if v < 62 then v - 4
  else if v == 62 then (if url then 45 else 43)
  else (if url then 95 else 47)

-- The 6-bit value of a character, or 255 if it is not in the alphabet.
decodeChar : Bool -> Bits8 -> Bits8
decodeChar url c =
  if c >= 65 && c <= 90 then c - 65
  else if c >= 97 && c <= 122 then c - 71
  else if c >= 48 && c <= 57 then c + 4
  else if url then (if c == 45 then 62 else if c == 95 then 63 else 255)
  else (if c == 43 then 62 else if c == 47 then 63 else 255)

isUrl : Alphabet -> Bool
isUrl UrlSafe = True
isUrl Standard = False

%inline
step : IO a -> (1 w : %World) -> IORes a
step act w = toPrim act w

%inline
inAt : ByteString -> Int -> Bits8
inAt = unsafeIndex

--------------------------------------------------------------------------
-- Encoding
--------------------------------------------------------------------------

-- Encode the full groups of three bytes: `k` groups left, input at `i`,
-- output at `o`.
encodeGroups : Bool -> ByteString -> Buffer -> Int -> Int -> Int ->
               (1 w : %World) -> IORes ()
encodeGroups url bs out k i o w =
  if k <= 0 then MkIORes () w
  else
    let b0 = inAt bs i
        b1 = inAt bs (i + 1)
        b2 = inAt bs (i + 2)
    in case step (setBits8 out o (encodeChar url (prim__shr_Bits8 b0 2))) w of
      MkIORes () w1 => case step (setBits8 out (o + 1) (encodeChar url
                               (prim__or_Bits8 (prim__shl_Bits8 (prim__and_Bits8 b0 3) 4)
                                               (prim__shr_Bits8 b1 4)))) w1 of
        MkIORes () w2 => case step (setBits8 out (o + 2) (encodeChar url
                                 (prim__or_Bits8 (prim__shl_Bits8 (prim__and_Bits8 b1 15) 2)
                                                 (prim__shr_Bits8 b2 6)))) w2 of
          MkIORes () w3 => case step (setBits8 out (o + 3) (encodeChar url (prim__and_Bits8 b2 63))) w3 of
            MkIORes () w4 => encodeGroups url bs out (assert_smaller k (k - 1)) (i + 3) (o + 4) w4

-- The number of characters of the encoding of `n` bytes.
encodedLength : Padding -> Int -> Int
encodedLength pad n =
  let full = assert_total (prim__div_Int n 3)
      rest = n - 3 * full
  in case pad of
       Padded => 4 * full + (if rest == 0 then 0 else 4)
       Unpadded => 4 * full + (if rest == 0 then 0 else rest + 1)

-- Encode the last one or two bytes (`rest`) at `i` into `out` at `o`.
-- (A function of its own, called only when there are such bytes: the
-- `let`s of a `do` block are evaluated when the action is built, so a read
-- under `when c $ do let x = ...` happens even when `c` is false, and the
-- reads must stay within the input.)
encodeTail : Bool -> Padding -> ByteString -> Buffer -> Int -> Int -> Int -> IO ()
encodeTail url pad bs out rest i o = do
  let b0 = inAt bs i
      b1 = if rest == 2 then inAt bs (i + 1) else 0
  setBits8 out o (encodeChar url (prim__shr_Bits8 b0 2))
  setBits8 out (o + 1) (encodeChar url
    (prim__or_Bits8 (prim__shl_Bits8 (prim__and_Bits8 b0 3) 4) (prim__shr_Bits8 b1 4)))
  if rest == 2
     then setBits8 out (o + 2) (encodeChar url (prim__shl_Bits8 (prim__and_Bits8 b1 15) 2))
     else when (pad == Padded) $ setBits8 out (o + 2) 61
  when (pad == Padded) $ setBits8 out (o + 3) 61

||| Encode with an alphabet and a padding rule.
export
encodeWith : Alphabet -> Padding -> ByteString -> ByteString
encodeWith alpha pad bs =
  let n = lengthInt bs
      url = isUrl alpha
      full = assert_total (prim__div_Int n 3)
      rest = n - 3 * full
      size = encodedLength pad n
  in unsafeCreate size $ \out => do
       fromPrim (encodeGroups url bs out full 0 0)
       if rest /= 0 then encodeTail url pad bs out rest (3 * full) (4 * full) else pure ()

||| Standard alphabet, padded: the encoding of RFC 4648 section 4.
export
encode : ByteString -> ByteString
encode = encodeWith Standard Padded

||| URL-safe alphabet, padded (RFC 4648 section 5).
export
encodeUrl : ByteString -> ByteString
encodeUrl = encodeWith UrlSafe Padded

||| URL-safe alphabet without padding (as JWT and `HTTP2-Settings` use).
export
encodeUrlUnpadded : ByteString -> ByteString
encodeUrlUnpadded = encodeWith UrlSafe Unpadded

--------------------------------------------------------------------------
-- Decoding
--------------------------------------------------------------------------

-- Decode `k` full groups of four characters from `i` into `out` at `o`.
-- False at the first character that is not in the alphabet.
decodeGroups : Bool -> ByteString -> Buffer -> Int -> Int -> Int ->
               (1 w : %World) -> IORes Bool
decodeGroups url bs out k i o w =
  if k <= 0 then MkIORes True w
  else
    let c0 = decodeChar url (inAt bs i)
        c1 = decodeChar url (inAt bs (i + 1))
        c2 = decodeChar url (inAt bs (i + 2))
        c3 = decodeChar url (inAt bs (i + 3))
    in if c0 == 255 || c1 == 255 || c2 == 255 || c3 == 255
          then MkIORes False w
          else case step (setBits8 out o (prim__or_Bits8 (prim__shl_Bits8 c0 2) (prim__shr_Bits8 c1 4))) w of
            MkIORes () w1 => case step (setBits8 out (o + 1)
                                   (prim__or_Bits8 (prim__shl_Bits8 c1 4) (prim__shr_Bits8 c2 2))) w1 of
              MkIORes () w2 => case step (setBits8 out (o + 2) (prim__or_Bits8 (prim__shl_Bits8 c2 6) c3)) w2 of
                MkIORes () w3 => decodeGroups url bs out (assert_smaller k (k - 1)) (i + 4) (o + 3) w3

-- Decode the last group of `r` (2 or 3) characters at `i` into `out` at
-- `o`; checks the alphabet and that the unused low bits are zero.
decodeTail : Bool -> ByteString -> Buffer -> Int -> Int -> Int -> IO Bool
decodeTail url bs out r i o =
  let c0 = decodeChar url (inAt bs i)
      c1 = decodeChar url (inAt bs (i + 1))
  in if c0 == 255 || c1 == 255 then pure False
     else if r == 2
       then if prim__and_Bits8 c1 15 /= 0 then pure False
            else do setBits8 out o (prim__or_Bits8 (prim__shl_Bits8 c0 2) (prim__shr_Bits8 c1 4))
                    pure True
       else let c2 = decodeChar url (inAt bs (i + 2)) in
            if c2 == 255 || prim__and_Bits8 c2 3 /= 0 then pure False
            else do setBits8 out o (prim__or_Bits8 (prim__shl_Bits8 c0 2) (prim__shr_Bits8 c1 4))
                    setBits8 out (o + 1) (prim__or_Bits8 (prim__shl_Bits8 c1 4) (prim__shr_Bits8 c2 2))
                    pure True

-- Decode `full` groups and a tail of `r` characters (0, 2 or 3) starting
-- at the beginning of `bs`.
decodeBody : Bool -> ByteString -> Int -> Int -> Maybe ByteString
decodeBody url bs full r =
  let size = 3 * full + (if r == 0 then 0 else r - 1) in
  if size == 0 then Just empty
  else unsafePerformIO $ do
    Just out <- newBuffer size
      | Nothing => assert_total (idris_crash "Network.HTTP.Base64: out of memory")
    ok <- fromPrim (decodeGroups url bs out full 0 0)
    ok' <- if ok && r /= 0 then decodeTail url bs out r (4 * full) (3 * full) else pure ok
    pure (if ok' then Just (UnsafeBS out 0 size) else Nothing)

||| Decode with an alphabet and a padding rule, strictly: `Nothing` for a
||| character outside the alphabet (whitespace included), for padding that
||| is missing (`Padded`), present (`Unpadded`) or misplaced, for a length
||| that no encoding has, and for non-zero bits after the last byte.
export
decodeWith : Alphabet -> Padding -> ByteString -> Maybe ByteString
decodeWith alpha pad bs =
  let n = lengthInt bs
      url = isUrl alpha
  in case pad of
       Padded =>
         if prim__and_Int n 3 /= 0 then Nothing
         else if n == 0 then Just empty
         else let p = if inAt bs (n - 1) == 61
                         then (if inAt bs (n - 2) == 61 then 2 else 1) else 0
                  full = assert_total (prim__div_Int n 4) - (if p == 0 then 0 else 1)
              in decodeBody url bs full (if p == 0 then 0 else 4 - p)
       Unpadded =>
         let full = assert_total (prim__div_Int n 4)
             r = n - 4 * full
         in if r == 1 then Nothing else decodeBody url bs full r

||| Standard alphabet, padding required (RFC 4648 section 4).
export
decode : ByteString -> Maybe ByteString
decode = decodeWith Standard Padded

||| URL-safe alphabet, padding required (RFC 4648 section 5).
export
decodeUrl : ByteString -> Maybe ByteString
decodeUrl = decodeWith UrlSafe Padded

||| URL-safe alphabet, no padding allowed.
export
decodeUrlUnpadded : ByteString -> Maybe ByteString
decodeUrlUnpadded = decodeWith UrlSafe Unpadded
