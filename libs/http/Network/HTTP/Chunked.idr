||| The chunked transfer coding of HTTP/1.1 (RFC 9112 section 7.1): an
||| incremental decoder and an encoder.
|||
||| The decoder is fed the bytes of the body as they arrive and returns the
||| data that they hold as slices of its input (no copy), until the last
||| chunk and the trailer section, after which it returns the bytes that
||| follow the body:
|||
||| ```idris
||| case decodeChunks dec bytes of
|||   More pieces dec'      => -- deliver the pieces, read more, feed dec'
|||   End pieces trailers rest => -- deliver the pieces; `rest` is the next message
|||   ChunkFailed err       => -- answer 400 and close
||| ```
module Network.HTTP.Chunked

import Data.Bits
import Data.ByteString
import Data.ByteString.Builder
import Data.ByteString.Internal
import Data.List
import Network.HTTP.Internal.Bytes
import Network.HTTP.Parser
import Network.HTTP.Render
import Network.HTTP.Types

%default total

--------------------------------------------------------------------------
-- Decoder
--------------------------------------------------------------------------

||| Limits of the decoder.
public export
record ChunkLimits where
  constructor MkChunkLimits
  ||| The most bytes of chunk extensions (after the size, before the CRLF) on
  ||| one chunk-size line.
  maxChunkExt : Int
  ||| The limits of the trailer section: `maxHeaderLine`, `maxHeaders` and
  ||| `maxHeadSize` (the size of the whole section) apply.
  trailerLimits : Limits

||| 4 KiB of extensions per chunk, and a trailer section of at most 100 field
||| lines of 8 KiB and 16 KiB in all.
export
defaultChunkLimits : ChunkLimits
defaultChunkLimits = MkChunkLimits 4096 ({ maxHeadSize := 16384 } defaultLimits)

||| Why a chunked body was rejected.  A server answers 400 to each.
public export
data ChunkError
  = ||| A chunk-size line that does not start with a hexadecimal digit, or
    ||| has something else than an extension after the size.
    BadChunkSize
  | ||| A chunk size of 2^60 or more.
    ChunkSizeTooLarge
  | ||| Chunk extensions longer than `maxChunkExt`, or with a control
    ||| character.
    BadChunkExt
  | ||| Chunk data not followed by CRLF.
    MissingChunkCRLF
  | ||| A CR not followed by LF, or an LF without CR, in a chunk-size line.
    BadLineEnd
  | ||| The trailer section is not valid or is beyond the limits.
    BadTrailer HeadError

||| The same error.
export
Eq ChunkError where
  BadChunkSize == BadChunkSize = True
  ChunkSizeTooLarge == ChunkSizeTooLarge = True
  BadChunkExt == BadChunkExt = True
  MissingChunkCRLF == MissingChunkCRLF = True
  BadLineEnd == BadLineEnd = True
  BadTrailer a == BadTrailer b = a == b
  _ == _ = False

||| The constructor.
export
Show ChunkError where
  show BadChunkSize = "BadChunkSize"
  show ChunkSizeTooLarge = "ChunkSizeTooLarge"
  show BadChunkExt = "BadChunkExt"
  show MissingChunkCRLF = "MissingChunkCRLF"
  show BadLineEnd = "BadLineEnd"
  show (BadTrailer e) = "BadTrailer " ++ show e

-- Where the decoder is.
data DState
  = -- In the hexadecimal digits of a size: the value so far and whether
    -- there was a digit.
    SizeDigits Int Bool
  | -- After the digits, in the extensions (or the whitespace before them):
    -- the size, the bytes of extensions so far, and whether a `;` was seen.
    Ext Int Int Bool
  | -- After the CR of a chunk-size line.
    SizeLF Int
  | -- In the data of a chunk: the bytes that are left.
    InData Int
  | -- After the data, before its CR, or before its LF.
    DataCR
  | DataLF
  | -- In the trailer section.
    InTrailer (HeadParser Headers)

||| The state of a decoder of a chunked body.  An immutable value.
export
record ChunkDecoder where
  constructor MkChunkDecoder
  limits : ChunkLimits
  state : DState
  ||| The bytes of chunk data decoded so far.
  decoded : Int

||| What decoding gave.
public export
data ChunkResult
  = ||| The data in the input, in order (slices of it; no empty ones), and
    ||| the decoder for what follows: all the input was used.
    More (List ByteString) ChunkDecoder
  | ||| The data in the input, the trailer fields, and the bytes after the
    ||| body.
    End (List ByteString) Headers ByteString
  | ||| The body is not valid.
    ChunkFailed ChunkError

||| A decoder at the start of a body.
export
chunkDecoder : ChunkLimits -> ChunkDecoder
chunkDecoder l = MkChunkDecoder l (SizeDigits 0 False) 0

||| The number of bytes of chunk data that the decoder has produced.
export
decodedLength : ChunkDecoder -> Int
decodedLength d = d.decoded

-- 2^56: a size that is this or more before one more digit is 2^60 or more
-- after it.
%inline
sizeLimit16 : Int
sizeLimit16 = 0x0100000000000000

-- Decode from index i of bs.  `out` is the data so far, the last first.
step : ChunkLimits -> DState -> (decoded : Int) -> ByteString -> Int -> List ByteString -> ChunkResult
step l st dec bs i out =
  let n = lengthInt bs in
  case st of
    InTrailer p => case feed p (dropInt i bs) of
                     NeedMore p' => More (reverse out) (MkChunkDecoder l (InTrailer p') dec)
                     Done hs rest => End (reverse out) hs rest
                     Failed err => ChunkFailed (BadTrailer err)
    _ =>
      if i >= n then More (reverse out) (MkChunkDecoder l st dec) else
      case st of
        SizeDigits v seen =>
          let c = unsafeIndex bs i
              h = hexValue c
          in if h >= 0
                then if v >= sizeLimit16 then ChunkFailed ChunkSizeTooLarge
                     else step l (SizeDigits (v * 16 + h) True) dec bs (assert_smaller i (i + 1)) out
                else if not seen then ChunkFailed BadChunkSize
                else if c == 13 then step l (SizeLF v) dec bs (assert_smaller i (i + 1)) out
                else if c == 10 then ChunkFailed BadLineEnd
                else if c == 59 || isOWS c
                        then step l (Ext v 1 (c == 59)) dec bs (assert_smaller i (i + 1)) out
                        else ChunkFailed BadChunkSize
        Ext v k semi =>
          let c = unsafeIndex bs i in
          if c == 13 then step l (SizeLF v) dec bs (assert_smaller i (i + 1)) out
          else if c == 10 then ChunkFailed BadLineEnd
          else if k >= l.maxChunkExt then ChunkFailed BadChunkExt
          else if not (isFieldVChar c) then ChunkFailed BadChunkExt
          else if not semi && not (isOWS c) && c /= 59 then ChunkFailed BadChunkSize
          else step l (Ext v (k + 1) (semi || c == 59)) dec bs (assert_smaller i (i + 1)) out
        SizeLF v =>
          if unsafeIndex bs i /= 10 then ChunkFailed BadLineEnd
          else if v == 0
                  then step l (InTrailer (fieldsParser l.trailerLimits)) dec bs (assert_smaller i (i + 1)) out
                  else step l (InData v) dec bs (assert_smaller i (i + 1)) out
        InData left =>
          let avail = n - i in
          if avail >= left
             then step l DataCR (dec + left) bs (assert_smaller i (i + left))
                       (sliceFromTo i (i + left) bs :: out)
             else More (reverse (sliceFromTo i n bs :: out)) (MkChunkDecoder l (InData (left - avail)) (dec + avail))
        DataCR => if unsafeIndex bs i == 13 then step l DataLF dec bs (assert_smaller i (i + 1)) out
                  else ChunkFailed MissingChunkCRLF
        DataLF => if unsafeIndex bs i == 10 then step l (SizeDigits 0 False) dec bs (assert_smaller i (i + 1)) out
                  else ChunkFailed MissingChunkCRLF
        InTrailer _ => ChunkFailed BadChunkSize -- (handled above)

||| Decode the next bytes of a chunked body.
|||
||| The extensions of a chunk are checked for size and for control
||| characters but not parsed (no extension is defined; RFC 9112 says to
||| ignore the ones a recipient does not understand).  The trailer fields
||| are returned as they are; a recipient must not use those that are only
||| allowed in a head (RFC 9110 section 6.5.1).
export
decodeChunks : ChunkDecoder -> ByteString -> ChunkResult
decodeChunks d bs = step d.limits d.state d.decoded bs 0 []

--------------------------------------------------------------------------
-- Encoder
--------------------------------------------------------------------------

crlf : ByteString
crlf = "\r\n"

lastChunkLine : ByteString
lastChunkLine = "0\r\n"

||| One chunk with these data: the size in hexadecimal, CRLF, the data and
||| CRLF.  Empty data give nothing (a chunk of size 0 would end the body).
export
encodeChunk : ByteString -> Builder
encodeChunk bs =
  if lengthInt bs == 0 then neutral
  else byteString (hexBytes (lengthInt bs)) <+> byteString crlf <+> byteString bs <+> byteString crlf

||| The last chunk and the trailer section: `0`, CRLF, the trailer fields
||| (not checked: see `isValidHeaderValue`) and CRLF.
export
encodeLastChunk : (trailers : Headers) -> Builder
encodeLastChunk hs =
  byteString lastChunkLine <+> renderHeaders hs <+> byteString crlf

||| A whole chunked body: a chunk for each non-empty piece, then the last
||| chunk with the trailers.
export
encodeChunked : List ByteString -> (trailers : Headers) -> Builder
encodeChunked pieces hs = foldl (\acc, p => acc <+> encodeChunk p) neutral pieces <+> encodeLastChunk hs
