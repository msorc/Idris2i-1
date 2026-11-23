||| HPACK, the header compression of HTTP/2 (RFC 7541).
|||
||| # Overview
|||
||| A connection has two independent compression contexts, one per
||| direction: the sender keeps an `EncoderState` and the receiver a
||| `DecoderState`, and each header block (the HEADERS or PUSH_PROMISE frame
||| and its CONTINUATION frames, concatenated) must be encoded and decoded
||| in the order the frames are sent, with the state each call returns
||| passed to the next.
|||
||| ```idris
||| (block, enc') = encodeHeaderBlock enc [MkHeaderField ":method" "GET" False, ...]
||| case decodeHeaderBlock dec (toByteString block) of
|||   Right (fields, dec') => ...
|||   Left (HeaderListTooLarge dec') => -- answer 431, keep dec'
|||   Left err => -- connection error COMPRESSION_ERROR
||| ```
|||
||| Both states are immutable values.  A connection handles its blocks one
||| after the other anyway, so a mutable table in `IO` would not save copies
||| of anything big: what changes per block is a few list cells of the
||| dynamic table (see `Network.HTTP2.HPACK.Table`), and keeping the state
||| pure makes the codec usable from pure code and trivially safe to retry
||| (a failed decode leaves the previous state untouched).
|||
||| The decoder returns names and values as slices of the input block when
||| they are not Huffman coded (no copy); `Data.ByteString.copy` them if the
||| block buffer should not be kept alive.
|||
||| The primitives (`encodeInteger`, `decodeInteger`, `encodeString`, and
||| the Huffman code in `Network.HTTP2.HPACK.Huffman`) are exported for
||| tests and for other codecs that use the same representations.
module Network.HTTP2.HPACK

import Data.Bits
import Data.ByteString
import Data.ByteString.Builder
import Data.ByteString.Internal
import Data.List
import Network.HTTP2.HPACK.Huffman
import Network.HTTP2.Internal

import public Network.HTTP2.HPACK.Table

%default total

--------------------------------------------------------------------------
-- Header fields and errors
--------------------------------------------------------------------------

||| A header field.  `sensitive` is set on a decoded field that was sent as
||| a never-indexed literal (RFC 7541 section 6.2.3), which an intermediary
||| must forward the same way; on a field to encode it asks for that
||| representation.
public export
record HeaderField where
  constructor MkHeaderField
  name : ByteString
  value : ByteString
  sensitive : Bool

||| Same name, value and flag.
export
Eq HeaderField where
  a == b = a.name == b.name && a.value == b.value && a.sensitive == b.sensitive

||| `name: value`, with ` (sensitive)` after it if the flag is set.
export
Show HeaderField where
  show f = toStringLossy f.name ++ ": " ++ toStringLossy f.value
           ++ (if f.sensitive then " (sensitive)" else "")

||| A field that is not sensitive.
export
field : ByteString -> ByteString -> HeaderField
field n v = MkHeaderField n v False

||| The state of a decoder: its dynamic table, the largest table size the
||| encoder may ask for (our SETTINGS_HEADER_TABLE_SIZE) and the largest
||| header list it accepts (RFC 7541 section 4.1 sizes).
export
record DecoderState where
  constructor MkDecoderState
  table : DynamicTable
  tableLimit : Int
  maxListSize : Int
  -- The limit was lowered below the size of the table: the next block
  -- must start with a size update.
  updateRequired : Bool

||| Why a header block could not be decoded.  All of them but
||| `HeaderListTooLarge` are a connection error of type COMPRESSION_ERROR
||| (RFC 9113 section 4.3): the decoder state is lost.
public export
data HPACKError : Type where
  ||| The block ends inside a representation.
  Truncated : HPACKError
  ||| An integer above 2^31 - 1.
  IntegerOverflow : HPACKError
  ||| Index 0, or an index beyond the static and dynamic tables.
  InvalidIndex : Int -> HPACKError
  ||| A Huffman-coded string with EOS or with invalid padding.
  InvalidHuffman : HPACKError
  ||| A dynamic table size update above the limit.
  TableSizeAboveLimit : Int -> HPACKError
  ||| A dynamic table size update after a field representation.
  LateTableSizeUpdate : HPACKError
  ||| The limit was lowered, and the block does not start with a dynamic
  ||| table size update (RFC 7541 section 4.2).
  MissingTableSizeUpdate : HPACKError
  ||| The decoded header list is larger than the limit.  The whole block
  ||| was processed, so the state given here is consistent with the
  ||| encoder's and the connection can go on (with a 431 response or a
  ||| reset of the stream, RFC 9113 section 10.5.1); the fields are dropped.
  HeaderListTooLarge : DecoderState -> HPACKError

||| A short description of the error.
export
Show HPACKError where
  show Truncated = "Truncated"
  show IntegerOverflow = "IntegerOverflow"
  show (InvalidIndex i) = "InvalidIndex " ++ show i
  show InvalidHuffman = "InvalidHuffman"
  show (TableSizeAboveLimit n) = "TableSizeAboveLimit " ++ show n
  show LateTableSizeUpdate = "LateTableSizeUpdate"
  show MissingTableSizeUpdate = "MissingTableSizeUpdate"
  show (HeaderListTooLarge _) = "HeaderListTooLarge"

--------------------------------------------------------------------------
-- Integers (RFC 7541 section 5.1)
--------------------------------------------------------------------------

-- The decoders below return an `Int` that packs a value (below 2^31) and
-- a position as `value * 2^32 + position`, or a negative number for an
-- error, so that no pair is allocated per integer.

errTruncated, errOverflow : Int
errTruncated = -1
errOverflow = -2

%inline
packed : Int -> Int -> Int
packed v pos = prim__or_Int (prim__shl_Int v 32) pos

%inline
valueOf : Int -> Int
valueOf r = prim__shr_Int r 32

%inline
posOf : Int -> Int
posOf r = prim__and_Int r 0xFFFFFFFF

-- The continuation bytes of an integer.
intMore : ByteString -> (j : Int) -> (end : Int) -> (acc : Int) -> (shift : Int) -> Int
intMore bs j end acc shift =
  if j >= end then errTruncated
  else let b = cast {to = Int} (unsafeIndex bs j)
           acc' = acc + prim__shl_Int (prim__and_Int b 127) shift
       in if prim__and_Int b 128 == 0
             then (if acc' > 0x7FFFFFFF then errOverflow else packed acc' (j + 1))
             else if shift >= 28 then errOverflow
             else intMore bs (assert_smaller j (j + 1)) end acc' (shift + 7)

-- An integer with an N-bit prefix at `i` (mask = 2^N - 1).
decodeInt : ByteString -> (i : Int) -> (end : Int) -> (mask : Int) -> Int
decodeInt bs i end mask =
  if i >= end then errTruncated
  else let v = prim__and_Int (cast (unsafeIndex bs i)) mask in
       if v < mask then packed v (i + 1) else intMore bs (i + 1) end mask 0

||| Decode an integer with an N-bit prefix (1 <= N <= 8) from the start of
||| a byte string: the value and the number of bytes used, or `Nothing` if
||| the input ends first or the value is above 2^31 - 1.  The bits of the
||| first byte above the prefix are ignored.
export
decodeInteger : (prefixBits : Int) -> ByteString -> Maybe (Int, Int)
decodeInteger n bs =
  let r = decodeInt bs 0 (lengthInt bs) (prim__shl_Int 1 n - 1) in
  if r < 0 then Nothing else Just (valueOf r, posOf r)

-- The continuation bytes of an integer, least significant group first.
intTail : Int -> List Bits8
intTail v = if v < 128 then [cast v]
            else cast (prim__or_Int (prim__and_Int v 127) 128)
                 :: intTail (assert_smaller v (prim__shr_Int v 7))

||| Encode a non-negative integer with an N-bit prefix (1 <= N <= 8); the
||| bits of `flags` above the prefix are put in the first byte.
export
encodeInteger : (prefixBits : Int) -> (flags : Bits8) -> Int -> Builder
encodeInteger n flags v =
  let mask = prim__shl_Int 1 n - 1 in
  if v < mask then word8 (flags .|. cast v)
  else bytes ((flags .|. cast mask) :: intTail (v - mask))

--------------------------------------------------------------------------
-- Strings (RFC 7541 section 5.2)
--------------------------------------------------------------------------

||| Encode a string literal: Huffman coded if `huffman` is set and that is
||| not longer (as the examples of RFC 7541 appendix C do), as it is
||| otherwise.
export
encodeString : (huffman : Bool) -> ByteString -> Builder
encodeString huff s =
  let n = lengthInt s in
  if huff && n > 0
     then let h = huffmanLength s in
          if h <= n then encodeInteger 7 0x80 h <+> byteString (huffmanEncode s)
          else encodeInteger 7 0 n <+> byteString s
     else encodeInteger 7 0 n <+> byteString s

-- A decoded string and the position after it, or an error.
data Str = MkStr ByteString Int | StrErr HPACKError

decodeStr : ByteString -> (i : Int) -> (end : Int) -> Str
decodeStr bs i end =
  let r = decodeInt bs i end 127 in
  if r < 0 then StrErr (if r == errOverflow then IntegerOverflow else Truncated)
  else let len = valueOf r
           pos = posOf r
       in if pos + len > end then StrErr Truncated
          else let raw = unsafeSlice pos len bs in
               if prim__and_Bits8 (unsafeIndex bs i) 0x80 == 0 then MkStr raw (pos + len)
               else case huffmanDecode raw of
                      Just s => MkStr s (pos + len)
                      Nothing => StrErr InvalidHuffman

||| Decode a string literal from the start of a byte string: the string and
||| the number of bytes used.
export
decodeString : ByteString -> Either HPACKError (ByteString, Int)
decodeString bs = case decodeStr bs 0 (lengthInt bs) of
  MkStr s pos => Right (s, pos)
  StrErr e => Left e

--------------------------------------------------------------------------
-- Decoder
--------------------------------------------------------------------------

||| A decoder whose dynamic table starts empty with a maximum size (4096
||| at the start of an HTTP/2 connection), which is also the largest size
||| the encoder may ask for, and that accepts header lists up to a size
||| (RFC 7541 section 4.1: the lengths of the names and values plus 32 per
||| field; SETTINGS_MAX_HEADER_LIST_SIZE).
export
newDecoder : (tableSize : Int) -> (maxHeaderListSize : Int) -> DecoderState
newDecoder ts ml = MkDecoderState (emptyTable ts) ts ml False

||| Our SETTINGS_HEADER_TABLE_SIZE changed (once the peer acknowledged it):
||| the encoder may not use a larger table, and if the table is larger now,
||| the next block must start with a size update that makes it fit.
export
setDecoderTableLimit : Int -> DecoderState -> DecoderState
setDecoderTableLimit n st =
  { tableLimit := n,
    updateRequired := st.updateRequired || n < tableMaxSize st.table } st

||| Change the limit on the size of decoded header lists.
export
setDecoderMaxListSize : Int -> DecoderState -> DecoderState
setDecoderMaxListSize n st = { maxListSize := n } st

||| The dynamic table of a decoder.
export
decoderTable : DecoderState -> DynamicTable
decoderTable st = st.table

-- The entry at an index of the static and dynamic tables.
lookupIndex : DynamicTable -> Int -> Maybe Entry
lookupIndex t i =
  if i < 1 then Nothing
  else if i <= staticTableSize then Just (staticEntry i)
  else dynamicEntry (i - staticTableSize) t

-- The result of the loop.
data Step = Done (List HeaderField) DynamicTable Bool | Fail HPACKError

-- One representation decoded: a field (with whether it is to be added to
-- the table and whether it is never indexed) and the position after it, a
-- size update and the position after it, an error, or the end of the
-- block.
data Rep = RField ByteString ByteString Bool Bool Int
         | RUpdate Int Int
         | RFail HPACKError
         | REnd

intError : Int -> HPACKError
intError r = if r == errOverflow then IntegerOverflow else Truncated

-- The value of a literal and the representation, given its name.
withName : ByteString -> Int -> ByteString -> Bool -> Bool -> Int -> Rep
withName bs end n indexing sens pos = case decodeStr bs pos end of
  StrErr e => RFail e
  MkStr v pos' => RField n v indexing sens pos'

-- A literal field representation at `i` with an index of `mask` bits.
literal : DynamicTable -> ByteString -> (end : Int) -> (i : Int) -> (mask : Int) ->
          (indexing : Bool) -> (sens : Bool) -> Rep
literal t bs end i mask indexing sens =
  let r = decodeInt bs i end mask in
  if r < 0 then RFail (intError r) else
  let idx = valueOf r
      pos = posOf r
  in if idx == 0
        then case decodeStr bs pos end of
               StrErr e => RFail e
               MkStr n pos' => withName bs end n indexing sens pos'
        else case lookupIndex t idx of
               Nothing => RFail (InvalidIndex idx)
               Just e => withName bs end e.name indexing sens pos

-- The representation at `i` (RFC 7541 section 6).
representation : DynamicTable -> ByteString -> (end : Int) -> (i : Int) -> Rep
representation t bs end i =
  let b = unsafeIndex bs i in
  if prim__and_Bits8 b 0x80 /= 0 then
    -- Indexed field (section 6.1).
    let r = decodeInt bs i end 127 in
    if r < 0 then RFail (intError r) else
    let idx = valueOf r in
    case lookupIndex t idx of
      Nothing => RFail (InvalidIndex idx)
      Just e => RField e.name e.value False False (posOf r)
  else if prim__and_Bits8 b 0x40 /= 0 then
    -- Literal with incremental indexing (section 6.2.1).
    literal t bs end i 63 True False
  else if prim__and_Bits8 b 0x20 /= 0 then
    -- Dynamic table size update (section 6.3).
    let r = decodeInt bs i end 31 in
    if r < 0 then RFail (intError r) else RUpdate (valueOf r) (posOf r)
  else
    -- Literal without indexing (0000) or never indexed (0001), sections
    -- 6.2.2 and 6.2.3.
    literal t bs end i 15 False (prim__and_Bits8 b 0x10 /= 0)

-- The representation at `i`, or `REnd` at the end of the block.
%inline
next : DynamicTable -> ByteString -> (end : Int) -> (i : Int) -> Rep
next t bs end i = if i >= end then REnd else representation t bs end i

-- Decode the representations, the first of which is given (it is an
-- argument, and not a `case` in the body, so that the recursion is a self
-- tail call, a loop in C).  `start` is true until the first field
-- representation; `listSize` is the size of the list so far; `over`
-- whether it went over the limit (the fields are then no longer kept).
decodeLoop : (limit : Int) -> (maxList : Int) -> ByteString -> (end : Int) ->
             (start : Bool) -> DynamicTable -> (listSize : Int) ->
             (over : Bool) -> List HeaderField -> Rep -> Step
decodeLoop _ _ _ _ _ t _ over acc REnd = Done acc t over
decodeLoop _ _ _ _ _ _ _ _ _ (RFail e) = Fail e
decodeLoop limit maxList bs end start t listSize over acc (RUpdate n pos) =
  if not start then Fail LateTableSizeUpdate
  else if n > limit then Fail (TableSizeAboveLimit n)
  else let t' = setMaxSize n t in
       decodeLoop limit maxList bs end True t' listSize over acc
                  (assert_smaller (RUpdate n pos) (next t' bs end pos))
decodeLoop limit maxList bs end start t listSize over acc (RField n v indexing sens pos) =
  let sz = listSize + entrySize n v
      over' = over || sz > maxList
      t' = if indexing then insert (MkEntry n v) t else t
  in decodeLoop limit maxList bs end False t' sz over'
                (if over' then [] else MkHeaderField n v sens :: acc)
                (assert_smaller (RField n v indexing sens pos) (next t' bs end pos))

||| Decode a complete header block (RFC 7541 section 3): the header list, in
||| order, and the state for the next block.  On `Left` with an error other
||| than `HeaderListTooLarge` the state is unusable and the connection must
||| be closed with COMPRESSION_ERROR.
export
decodeHeaderBlock : DecoderState -> ByteString -> Either HPACKError (List HeaderField, DecoderState)
decodeHeaderBlock st bs =
  let end = lengthInt bs in
  if st.updateRequired && (end == 0 || prim__and_Bits8 (unsafeIndex bs 0) 0xE0 /= 0x20)
     then Left MissingTableSizeUpdate
     else case decodeLoop st.tableLimit st.maxListSize bs end True st.table 0 False []
                          (next st.table bs end 0) of
            Fail e => Left e
            Done fields t over =>
              let st' = the DecoderState ({ table := t, updateRequired := False } st) in
              if over then Left (HeaderListTooLarge st')
              else Right (reverse fields, st')

--------------------------------------------------------------------------
-- Encoder
--------------------------------------------------------------------------

||| How a literal field is represented (RFC 7541 section 6.2).
public export
data Indexing : Type where
  ||| Added to the dynamic table (section 6.2.1).
  IncrementalIndexing : HeaderField -> Indexing
  ||| Not added (section 6.2.2).
  WithoutIndexing : HeaderField -> Indexing
  ||| Not added, and never to be added by an intermediary (section 6.2.3).
  NeverIndexed : HeaderField -> Indexing

||| The state of an encoder: its dynamic table, the largest size it lets
||| the table have, the size updates it has to signal at the start of the
||| next block, and whether it uses Huffman coding.
export
record EncoderState where
  constructor MkEncoderState
  table : DynamicTable
  cap : Int
  -- The smallest size and the last size the table was given since the
  -- last block, when they have to be signalled.
  pending : Maybe (Int, Int)
  huffman : Bool

||| An encoder whose dynamic table starts empty with a maximum size, which
||| the decoder must start with too (4096 at the start of an HTTP/2
||| connection), and which is also the largest size it will use when the
||| peer allows more.  With `huffman`, strings are Huffman coded when that
||| is not longer.
export
newEncoder : (tableSize : Int) -> (huffman : Bool) -> EncoderState
newEncoder ts h = MkEncoderState (emptyTable ts) ts Nothing h

||| The peer's SETTINGS_HEADER_TABLE_SIZE changed: use a table of that size
||| or of the encoder's cap if it is smaller, and signal the change at the
||| start of the next block (RFC 7541 section 4.2).
export
setEncoderTableLimit : Int -> EncoderState -> EncoderState
setEncoderTableLimit n st =
  let m = min n st.cap
      lo = case st.pending of
             Nothing => m
             Just (l, _) => min l m
  in if m == tableMaxSize st.table && isNothing st.pending then st
     else { table $= setMaxSize m, pending := Just (lo, m) } st

||| The dynamic table of an encoder.
export
encoderTable : EncoderState -> DynamicTable
encoderTable st = st.table

-- The index of a field in the tables, and the index of its name, or 0.
lookupField : DynamicTable -> ByteString -> ByteString -> (Int, Int)
lookupField t n v =
  case staticLookup n v of
    (0, sn) => case dynamicLookup n v t of
                 (0, dn) => (0, if sn /= 0 then sn else if dn /= 0 then dn + staticTableSize else 0)
                 (df, _) => (df + staticTableSize, if sn /= 0 then sn else df + staticTableSize)
    found => found

||| Encode one field with the given representation: as an index if the
||| table has the same name and value (unless it is `NeverIndexed`),
||| otherwise as a literal, with the index of the name if a table has it.
export
encodeField : EncoderState -> Indexing -> (Builder, EncoderState)
encodeField st rep =
  let (f, prefixBits, flags, indexing, never) = parts rep
      (full, nameIdx) = lookupField st.table f.name f.value
  in if full /= 0 && not never
        then (encodeInteger 7 0x80 full, st)
        else let nm = if nameIdx /= 0 then encodeInteger prefixBits flags nameIdx
                      else word8 flags <+> encodeString st.huffman f.name
                 b = nm <+> encodeString st.huffman f.value
             in (b, if indexing then { table $= insert (MkEntry f.name f.value) } st else st)
  where
    parts : Indexing -> (HeaderField, Int, Bits8, Bool, Bool)
    parts (IncrementalIndexing f) = (f, 6, 0x40, True, False)
    parts (WithoutIndexing f) = (f, 4, 0x00, False, False)
    parts (NeverIndexed f) = (f, 4, 0x10, False, True)

||| The representation `encodeHeaderBlock` chooses for a field: never
||| indexed if it is marked sensitive, or is an `authorization` or
||| `proxy-authorization` field, or a `cookie` shorter than 20 bytes (which
||| could be guessed, RFC 7541 section 7.1.3); without indexing if it is
||| too big to fit in the table; with incremental indexing otherwise.
export
defaultIndexing : (tableMax : Int) -> HeaderField -> Indexing
defaultIndexing tmax f =
  if f.sensitive || f.name == "authorization" || f.name == "proxy-authorization"
       || (f.name == "cookie" && lengthInt f.value < 20)
     then NeverIndexed f
     else if entrySize f.name f.value > tmax then WithoutIndexing f
     else IncrementalIndexing f

-- The size updates to signal, and the state without them.
sizeUpdates : EncoderState -> (Builder, EncoderState)
sizeUpdates st = case st.pending of
  Nothing => (empty, st)
  Just (lo, final) =>
    ((if lo < final then encodeInteger 5 0x20 lo else empty) <+> encodeInteger 5 0x20 final,
     { pending := Nothing } st)

||| Encode a header block with a choice of representation per field
||| (after the size updates that are due).
export
encodeHeaderBlockWith : (DynamicTable -> HeaderField -> Indexing) ->
                        EncoderState -> List HeaderField -> (Builder, EncoderState)
encodeHeaderBlockWith choose st fs =
  let (pre, st1) = sizeUpdates st in go pre st1 fs
  where
    go : Builder -> EncoderState -> List HeaderField -> (Builder, EncoderState)
    go acc s [] = (acc, s)
    go acc s (f :: rest) =
      let (b, s') = encodeField s (choose s.table f) in go (acc <+> b) s' rest

||| Encode a header block (RFC 7541 section 3) with `defaultIndexing`: the
||| bytes of the block, to be sent in a HEADERS or PUSH_PROMISE frame and
||| CONTINUATION frames, and the state for the next block.  Header names
||| must be in lower case for HTTP/2.
export
encodeHeaderBlock : EncoderState -> List HeaderField -> (Builder, EncoderState)
encodeHeaderBlock = encodeHeaderBlockWith (\t => defaultIndexing (tableMaxSize t))
