||| WebSocket frames (RFC 6455 section 5): the frame header, masking and
||| the payload of close frames.
|||
||| A frame on the wire is a header of 2 to 14 bytes followed by the
||| payload.  `decodeHeader` reads a header from the start of whatever bytes
||| have arrived and says how long it was, or how many bytes it needs, or why
||| the frame is invalid; the caller then takes `payloadLength` bytes of
||| payload, which may arrive in pieces, and unmasks each piece with `mask`
||| at the offset of the piece in the payload.  Messages (the reassembly of
||| fragments, the order of control frames between them) are the business
||| of the connection, not of this module; `Network.WebSocket.UTF8` checks
||| the text of a message piece by piece.
|||
||| ```idris
||| case decodeHeader serverSide bytes of
|||   NeedMore n => -- read until there are at least n bytes
|||   Invalid err => -- close the connection with closeCodeFor err
|||   Header h used => -- the payload starts at byte `used`
||| ```
module Network.WebSocket.Frame

import Data.Bits
import Data.Buffer
import Data.ByteString
import Data.ByteString.Builder
import Data.ByteString.Internal
import Network.WebSocket.UTF8

%default total

--------------------------------------------------------------------------
-- Opcodes and headers
--------------------------------------------------------------------------

||| The opcodes of RFC 6455 section 5.2.  The reserved values (3-7 and
||| 11-15) are rejected by `decodeHeader` and cannot be represented.
public export
data Opcode = Continuation | Text | Binary | Close | Ping | Pong

||| The same opcode.
export
Eq Opcode where
  Continuation == Continuation = True
  Text == Text = True
  Binary == Binary = True
  Close == Close = True
  Ping == Ping = True
  Pong == Pong = True
  _ == _ = False

||| The name of the opcode.
export
Show Opcode where
  show Continuation = "Continuation"
  show Text = "Text"
  show Binary = "Binary"
  show Close = "Close"
  show Ping = "Ping"
  show Pong = "Pong"

||| The 4-bit value of an opcode on the wire.
export
opcodeValue : Opcode -> Bits8
opcodeValue Continuation = 0
opcodeValue Text = 1
opcodeValue Binary = 2
opcodeValue Close = 8
opcodeValue Ping = 9
opcodeValue Pong = 10

||| The opcode of a 4-bit value, or `Nothing` for a reserved one.
export
opcodeFromValue : Bits8 -> Maybe Opcode
opcodeFromValue 0 = Just Continuation
opcodeFromValue 1 = Just Text
opcodeFromValue 2 = Just Binary
opcodeFromValue 8 = Just Close
opcodeFromValue 9 = Just Ping
opcodeFromValue 10 = Just Pong
opcodeFromValue _ = Nothing

||| Close, Ping and Pong: the frames that may not be fragmented and have at
||| most 125 bytes of payload (section 5.5).
export
isControl : Opcode -> Bool
isControl Close = True
isControl Ping = True
isControl Pong = True
isControl _ = False

||| A frame header.
|||
||| The masking key is the four bytes of the key as a big-endian number:
||| the bytes `37 fa 21 3d` on the wire are `0x37fa213d`.
public export
record FrameHeader where
  constructor MkFrameHeader
  ||| The final fragment of a message.
  fin : Bool
  ||| The reserved bits, for extensions (permessage-deflate uses `rsv1`).
  rsv1 : Bool
  ||| The second reserved bit.
  rsv2 : Bool
  ||| The third reserved bit.
  rsv3 : Bool
  ||| What the frame carries.
  opcode : Opcode
  ||| The masking key, present on every frame from a client.
  maskKey : Maybe Bits32
  ||| The number of bytes of payload (0 .. 2^63 - 1).
  payloadLength : Int

||| Field by field.
export
Eq FrameHeader where
  x == y = x.fin == y.fin && x.rsv1 == y.rsv1 && x.rsv2 == y.rsv2 &&
           x.rsv3 == y.rsv3 && x.opcode == y.opcode && x.maskKey == y.maskKey &&
           x.payloadLength == y.payloadLength

||| For tests and logs.
export
Show FrameHeader where
  show h = "MkFrameHeader " ++ show h.fin ++ " " ++ show h.rsv1 ++ " " ++
           show h.rsv2 ++ " " ++ show h.rsv3 ++ " " ++ show h.opcode ++ " " ++
           showPrec App h.maskKey ++ " " ++ show h.payloadLength

||| An unfragmented frame without reserved bits or mask.
export
simpleHeader : Opcode -> (payloadLength : Int) -> FrameHeader
simpleHeader op n = MkFrameHeader True False False False op Nothing n

--------------------------------------------------------------------------
-- Decoding
--------------------------------------------------------------------------

||| What the decoding side expects of the frames it receives.
public export
record DecodeOptions where
  constructor MkDecodeOptions
  ||| `True` on a server: every frame from a client must be masked.
  ||| `False` on a client: frames from a server must not be (section 5.1).
  expectMasked : Bool
  ||| The reserved bits that a negotiated extension gives a meaning, as the
  ||| bits of the first byte: `0x40` for RSV1, `0x20` for RSV2, `0x10` for
  ||| RSV3.  The others must be zero.
  allowedRsv : Bits8
  ||| The largest payload accepted (a frame above it is `PayloadTooLarge`).
  maxPayload : Int

||| A server without extensions, accepting payloads up to 16 MiB.
export
serverOptions : DecodeOptions
serverOptions = MkDecodeOptions True 0 0x1000000

||| A client without extensions, accepting payloads up to 16 MiB.
export
clientOptions : DecodeOptions
clientOptions = MkDecodeOptions False 0 0x1000000

||| Why a frame header is invalid.
public export
data FrameError
  = ||| A reserved bit is set that no extension negotiated.
    ReservedBitSet
  | ||| A reserved opcode (the value is given).
    ReservedOpcode Bits8
  | ||| A control frame without FIN.
    FragmentedControl
  | ||| A control frame with more than 125 bytes of payload.
    ControlTooLong
  | ||| A frame from a client without a mask.
    MaskMissing
  | ||| A frame from a server with a mask.
    MaskUnexpected
  | ||| A length in the 16- or 64-bit form that fits a shorter form.
    NonMinimalLength
  | ||| A 64-bit length with the most significant bit set.
    LengthOverflow
  | ||| A payload above `maxPayload`.
    PayloadTooLarge

||| The same error.
export
Eq FrameError where
  ReservedBitSet == ReservedBitSet = True
  ReservedOpcode x == ReservedOpcode y = x == y
  FragmentedControl == FragmentedControl = True
  ControlTooLong == ControlTooLong = True
  MaskMissing == MaskMissing = True
  MaskUnexpected == MaskUnexpected = True
  NonMinimalLength == NonMinimalLength = True
  LengthOverflow == LengthOverflow = True
  PayloadTooLarge == PayloadTooLarge = True
  _ == _ = False

||| The constructor name.
export
Show FrameError where
  showPrec _ ReservedBitSet = "ReservedBitSet"
  showPrec d (ReservedOpcode v) = showCon d "ReservedOpcode" (showArg v)
  showPrec _ FragmentedControl = "FragmentedControl"
  showPrec _ ControlTooLong = "ControlTooLong"
  showPrec _ MaskMissing = "MaskMissing"
  showPrec _ MaskUnexpected = "MaskUnexpected"
  showPrec _ NonMinimalLength = "NonMinimalLength"
  showPrec _ LengthOverflow = "LengthOverflow"
  showPrec _ PayloadTooLarge = "PayloadTooLarge"

||| The status code to close the connection with (section 7.4.1): 1009
||| "message too big" for `PayloadTooLarge`, 1002 "protocol error" for the
||| others.
export
closeCodeFor : FrameError -> Bits16
closeCodeFor PayloadTooLarge = 1009
closeCodeFor _ = 1002

||| The result of reading a header from the start of the bytes received.
public export
data HeaderResult
  = ||| Not enough bytes: the header needs at least this many in all
    ||| (2 before the length is known, then its exact size).
    NeedMore Int
  | ||| A valid header, and the number of bytes it took (2 to 14).
    Header FrameHeader Int
  | ||| The frame is invalid; the connection must be failed.
    Invalid FrameError

||| Show, for tests.
export
Show HeaderResult where
  showPrec d (NeedMore n) = showCon d "NeedMore" (showArg n)
  showPrec d (Header h n) = showCon d "Header" (" (" ++ show h ++ ")" ++ showArg n)
  showPrec d (Invalid e) = showCon d "Invalid" (showArg e)

-- The big-endian number of `n` bytes from `i` (n <= 8), as an Int that
-- may be negative when the top bit of 8 bytes is set.
beInt : ByteString -> Int -> Int -> Int -> Int
beInt bs i n acc =
  if n <= 0 then acc
  else beInt bs (i + 1) (assert_smaller n (n - 1))
             (prim__or_Int (prim__shl_Int acc 8) (cast (unsafeIndex bs i)))

-- The header after the length is known: `lenEnd` is where the length
-- field ends.
finishHeader : DecodeOptions -> ByteString -> Bits8 -> Opcode -> Bool -> Int -> Int ->
               HeaderResult
finishHeader opts bs b0 op masked lenEnd len =
  let size = lenEnd + (if masked then 4 else 0) in
  if lengthInt bs < size then NeedMore size
  else if len > opts.maxPayload then Invalid PayloadTooLarge
  else let key = if masked then Just (cast (beInt bs lenEnd 4 0)) else Nothing in
       Header (MkFrameHeader (prim__and_Bits8 b0 0x80 /= 0) (prim__and_Bits8 b0 0x40 /= 0)
                             (prim__and_Bits8 b0 0x20 /= 0) (prim__and_Bits8 b0 0x10 /= 0)
                             op key len)
              size

-- The checks that need only the first two bytes.
checkStart : DecodeOptions -> Bits8 -> Bits8 -> Either FrameError Opcode
checkStart opts b0 b1 =
  if prim__and_Bits8 (prim__and_Bits8 b0 0x70) (prim__xor_Bits8 opts.allowedRsv 0xFF) /= 0
    then Left ReservedBitSet
  else case opcodeFromValue (prim__and_Bits8 b0 0x0F) of
    Nothing => Left (ReservedOpcode (prim__and_Bits8 b0 0x0F))
    Just op =>
      let masked = prim__and_Bits8 b1 0x80 /= 0
          len7 = prim__and_Bits8 b1 0x7F
      in if isControl op && prim__and_Bits8 b0 0x80 == 0 then Left FragmentedControl
         else if isControl op && len7 > 125 then Left ControlTooLong
         else if opts.expectMasked && not masked then Left MaskMissing
         else if not opts.expectMasked && masked then Left MaskUnexpected
         else Right op

||| Read a frame header from the start of the bytes received so far.
|||
||| Checks every rule that is a property of one header: reserved bits and
||| opcodes, FIN and the 125-byte limit of control frames, the masking
||| rule of `DecodeOptions`, the minimal encoding of the length and the
||| clear top bit of a 64-bit length, and `maxPayload`.  The checks on the
||| first two bytes are made as soon as they are there, so an invalid frame
||| is reported before its extended length arrives.  Does not allocate
||| beyond the result.
export
decodeHeader : DecodeOptions -> ByteString -> HeaderResult
decodeHeader opts bs =
  if lengthInt bs < 2 then NeedMore 2
  else
    let b0 = unsafeIndex bs 0
        b1 = unsafeIndex bs 1
    in case checkStart opts b0 b1 of
         Left err => Invalid err
         Right op =>
           let masked = prim__and_Bits8 b1 0x80 /= 0
               len7 = prim__and_Bits8 b1 0x7F
           in if len7 < 126 then finishHeader opts bs b0 op masked 2 (cast len7)
              else if len7 == 126
                then if lengthInt bs < 4 then NeedMore (if masked then 8 else 4)
                     else let len = beInt bs 2 2 0 in
                          if len < 126 then Invalid NonMinimalLength
                          else finishHeader opts bs b0 op masked 4 len
                else if lengthInt bs < 10 then NeedMore (if masked then 14 else 10)
                     else let len = beInt bs 2 8 0 in
                          if len < 0 then Invalid LengthOverflow
                          else if len < 65536 then Invalid NonMinimalLength
                          else finishHeader opts bs b0 op masked 10 len

--------------------------------------------------------------------------
-- Encoding
--------------------------------------------------------------------------

-- The size of the encoded header.
headerSize : FrameHeader -> Int
headerSize h =
  (if h.payloadLength < 126 then 2 else if h.payloadLength < 65536 then 4 else 10) +
  (case h.maskKey of Nothing => 0; Just _ => 4)

-- Write the `n` low bytes of a number big-endian at `o`.
putBE : Buffer -> Int -> Int -> Int -> IO ()
putBE buf o n v =
  if n <= 0 then pure ()
  else do setBits8 buf (o + n - 1) (cast (prim__and_Int v 0xFF))
          putBE buf o (assert_smaller n (n - 1)) (prim__shr_Int v 8)

||| The bytes of a header, with the length in its shortest form.  The
||| header is written as it is; it is the caller's business that it is
||| valid (a control frame has FIN and at most 125 bytes, a client masks).
||| A negative length is written as 0.
export
encodeHeader : FrameHeader -> ByteString
encodeHeader h =
  let n : Int = if h.payloadLength < 0 then 0 else h.payloadLength
      b0 = prim__or_Bits8
             (prim__or_Bits8 (if h.fin then 0x80 else 0) (if h.rsv1 then 0x40 else 0))
             (prim__or_Bits8 (prim__or_Bits8 (if h.rsv2 then 0x20 else 0) (if h.rsv3 then 0x10 else 0))
                             (opcodeValue h.opcode))
      m = case h.maskKey of Nothing => the Bits8 0; Just _ => 0x80
  in unsafeCreate (headerSize ({ payloadLength := n } h)) $ \buf => do
       setBits8 buf 0 b0
       lenEnd <- the (IO Int) $ if n < 126 then do setBits8 buf 1 (prim__or_Bits8 m (cast n)); pure 2
                 else if n < 65536 then do setBits8 buf 1 (prim__or_Bits8 m 126)
                                           putBE buf 2 2 n
                                           pure 4
                 else do setBits8 buf 1 (prim__or_Bits8 m 127)
                         putBE buf 2 8 n
                         pure 10
       case h.maskKey of
         Nothing => pure ()
         Just k => putBE buf lenEnd 4 (cast k)

--------------------------------------------------------------------------
-- Masking (section 5.3)
--------------------------------------------------------------------------

-- The key byte `j` (0..3) of a key: the most significant first.
keyByte : Bits32 -> Int -> Bits8
keyByte k j = cast (prim__shr_Bits32 k (cast (24 - 8 * prim__and_Int j 3)))

-- The key starting at cycle position `r`, repeated over eight bytes, as
-- the little-endian `Bits64` that `getBits64` reads: byte `j` of memory is
-- key byte `(r + j) mod 4`.
key64 : Bits32 -> Int -> Bits64
key64 k r =
  let b0 = the Bits64 (cast (keyByte k r))
      b1 = the Bits64 (cast (keyByte k (r + 1)))
      b2 = the Bits64 (cast (keyByte k (r + 2)))
      b3 = the Bits64 (cast (keyByte k (r + 3)))
      w = prim__or_Bits64 (prim__or_Bits64 b0 (prim__shl_Bits64 b1 8))
                          (prim__or_Bits64 (prim__shl_Bits64 b2 16) (prim__shl_Bits64 b3 24))
  in prim__or_Bits64 w (prim__shl_Bits64 w 32)

%inline
step : IO a -> (1 w : %World) -> IORes a
step act w = toPrim act w

-- Eight bytes at a time: `n` bytes from `src` at `i` to `dst` at `o`.
maskWords : Bits64 -> Buffer -> Int -> Buffer -> Int -> Int -> (1 w : %World) -> IORes ()
maskWords k64 src i dst o n w =
  if n < 8 then MkIORes () w
  else case step (getBits64 src i) w of
         MkIORes v w1 => case step (setBits64 dst o (prim__xor_Bits64 v k64)) w1 of
           MkIORes () w2 => maskWords k64 src (i + 8) dst (o + 8) (assert_smaller n (n - 8)) w2

-- The last bytes, one at a time, `r` being the cycle position of the first.
maskBytes : Bits32 -> Int -> Buffer -> Int -> Buffer -> Int -> Int -> (1 w : %World) -> IORes ()
maskBytes k r src i dst o n w =
  if n <= 0 then MkIORes () w
  else case step (getBits8 src i) w of
         MkIORes v w1 => case step (setBits8 dst o (prim__xor_Bits8 v (keyByte k r))) w1 of
           MkIORes () w2 => maskBytes k (r + 1) src (i + 1) dst (o + 1) (assert_smaller n (n - 1)) w2

||| Mask (or unmask: it is the same) the bytes of a byte string into a
||| buffer at an offset, `offset` being the position of the first byte in
||| the payload of the frame (only `offset mod 4` matters), so that a
||| payload that arrives in pieces can be unmasked piece by piece.  Eight
||| bytes at a time.  The destination must have room and must be a buffer
||| that is being filled (see `Data.ByteString.Internal`).
export
maskInto : (key : Bits32) -> (offset : Int) -> ByteString -> Buffer -> Int -> IO ()
maskInto k off bs dst at = do
  let r = prim__and_Int off 3
      n = lengthInt bs
      words = n - prim__and_Int n 7
  fromPrim (maskWords (key64 k r) (unsafeBuffer bs) (unsafeOffset bs) dst at n)
  fromPrim (maskBytes k r (unsafeBuffer bs) (unsafeOffset bs + words) dst (at + words) (n - words))

||| Mask (or unmask) a byte string into a fresh one: byte `i` is XORed with
||| key byte `(offset + i) mod 4`.  `mask k off (a ++ b)` is
||| `mask k off a ++ mask k (off + length a) b`.
export
mask : (key : Bits32) -> (offset : Int) -> ByteString -> ByteString
mask k off bs = unsafeCreate (lengthInt bs) (\buf => maskInto k off bs buf 0)

||| A whole frame: the header (with the length of the payload) and the
||| payload, masked with the header's key if it has one.
export
encodeFrame : FrameHeader -> ByteString -> Builder
encodeFrame h payload =
  let h' = { payloadLength := lengthInt payload } h in
  byteString (encodeHeader h') <+>
  byteString (case h.maskKey of
                Nothing => payload
                Just k => mask k 0 payload)

--------------------------------------------------------------------------
-- Close frames (sections 5.5.1 and 7.4)
--------------------------------------------------------------------------

||| May this status code be sent in a close frame?  1000-1003 and 1007-1014
||| (those of RFC 6455 and the three that IANA registered later), and the
||| ranges 3000-3999 (registered) and 4000-4999 (private).  Not 1004
||| (reserved), 1005 and 1006 (meaning "no code" and "abnormal closure",
||| never on the wire), 1015 (TLS failure, never on the wire), the other
||| values below 3000 or anything from 5000.
export
validCloseCode : Bits16 -> Bool
validCloseCode c =
  (c >= 1000 && c <= 1003) || (c >= 1007 && c <= 1014) || (c >= 3000 && c <= 4999)

||| Why the payload of a close frame is invalid.
public export
data CloseError
  = ||| One byte: a code needs two.
    CloseTruncated
  | ||| A code that may not be sent (see `validCloseCode`).
    InvalidCloseCode Bits16
  | ||| The reason is not UTF-8.
    InvalidReason

||| The same error.
export
Eq CloseError where
  CloseTruncated == CloseTruncated = True
  InvalidCloseCode x == InvalidCloseCode y = x == y
  InvalidReason == InvalidReason = True
  _ == _ = False

||| The constructor name.
export
Show CloseError where
  showPrec _ CloseTruncated = "CloseTruncated"
  showPrec d (InvalidCloseCode c) = showCon d "InvalidCloseCode" (showArg c)
  showPrec _ InvalidReason = "InvalidReason"

||| The status code to fail the connection with when a close payload is
||| invalid: 1007 for a reason that is not UTF-8, 1002 otherwise.
export
closeErrorCode : CloseError -> Bits16
closeErrorCode InvalidReason = 1007
closeErrorCode _ = 1002

||| The (unmasked) payload of a close frame: `Nothing` if it is empty (no
||| code), else the code and the reason.
export
parseClose : ByteString -> Either CloseError (Maybe (Bits16, ByteString))
parseClose bs =
  let n = lengthInt bs in
  if n == 0 then Right Nothing
  else if n == 1 then Left CloseTruncated
  else let code = prim__or_Bits16 (prim__shl_Bits16 (cast (unsafeIndex bs 0)) 8)
                                  (cast (unsafeIndex bs 1))
           reason = unsafeSlice 2 (n - 2) bs
       in if not (validCloseCode code) then Left (InvalidCloseCode code)
          else if not (validUtf8 reason) then Left InvalidReason
          else Right (Just (code, reason))

||| The payload of a close frame with a code and a reason (which should be
||| UTF-8 of at most 123 bytes, to fit a control frame).
export
closePayload : Bits16 -> ByteString -> ByteString
closePayload code reason =
  unsafeCreate (2 + lengthInt reason) $ \buf => do
    setBits8 buf 0 (cast (prim__shr_Bits16 code 8))
    setBits8 buf 1 (cast code)
    unsafeCopyTo reason buf 2
