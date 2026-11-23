||| HTTP/2 frames (RFC 9113 sections 4 and 6): the connection preface, the
||| 9-byte frame header, the ten frame types with their flags, settings and
||| error codes.
|||
||| # Overview
|||
||| `decodeFrame` takes the bytes received so far on a connection and
||| returns `NeedMore n` (read at least `n` more bytes and call it again with
||| all of them), `Decoded frame rest`, or `Failed err rest`.  It checks the
||| rules that are properties of a single frame (its size, its stream
||| identifier, its flags and fields) and reports a violation with the
||| error code and the scope (stream or connection) that RFC 9113 gives it;
||| the rules that need the state of the connection or of a stream (stream
||| states, CONTINUATION sequences, flow control windows) are for the
||| connection layer.  Payloads are slices of the input (no copy).
|||
||| `encodeFrame` turns a frame into a `Builder`.  It does not check the
||| frame: the sender is responsible for sizes and stream identifiers.
|||
||| ```idris
||| case decodeFrame defaultSettings.maxFrameSize input of
|||   NeedMore n => -- read more
|||   Decoded (Ping False opaque) rest => send (encodeFrame (Ping True opaque))
|||   Failed (ConnectionError code msg) _ => send (encodeFrame (GoAway lastId code "")) ...
||| ```
module Network.HTTP2.Frame

import Data.Bits
import Data.ByteString
import Data.ByteString.Builder
import Data.ByteString.Internal
import Data.List
import Network.HTTP2.Internal

%default total

--------------------------------------------------------------------------
-- Error codes (section 7)
--------------------------------------------------------------------------

||| The error codes of RST_STREAM and GOAWAY frames.
public export
data ErrorCode : Type where
  NoError : ErrorCode
  ProtocolError : ErrorCode
  InternalError : ErrorCode
  FlowControlError : ErrorCode
  SettingsTimeout : ErrorCode
  StreamClosed : ErrorCode
  FrameSizeError : ErrorCode
  RefusedStream : ErrorCode
  Cancel : ErrorCode
  CompressionError : ErrorCode
  ConnectError : ErrorCode
  EnhanceYourCalm : ErrorCode
  InadequateSecurity : ErrorCode
  HTTP11Required : ErrorCode
  ||| A code this module does not know (to be treated as INTERNAL_ERROR,
  ||| section 7).
  UnknownErrorCode : Bits32 -> ErrorCode

||| The number of an error code.
export
errorCodeToBits : ErrorCode -> Bits32
errorCodeToBits NoError = 0x0
errorCodeToBits ProtocolError = 0x1
errorCodeToBits InternalError = 0x2
errorCodeToBits FlowControlError = 0x3
errorCodeToBits SettingsTimeout = 0x4
errorCodeToBits StreamClosed = 0x5
errorCodeToBits FrameSizeError = 0x6
errorCodeToBits RefusedStream = 0x7
errorCodeToBits Cancel = 0x8
errorCodeToBits CompressionError = 0x9
errorCodeToBits ConnectError = 0xa
errorCodeToBits EnhanceYourCalm = 0xb
errorCodeToBits InadequateSecurity = 0xc
errorCodeToBits HTTP11Required = 0xd
errorCodeToBits (UnknownErrorCode c) = c

||| The error code of a number.
export
errorCodeFromBits : Bits32 -> ErrorCode
errorCodeFromBits 0x0 = NoError
errorCodeFromBits 0x1 = ProtocolError
errorCodeFromBits 0x2 = InternalError
errorCodeFromBits 0x3 = FlowControlError
errorCodeFromBits 0x4 = SettingsTimeout
errorCodeFromBits 0x5 = StreamClosed
errorCodeFromBits 0x6 = FrameSizeError
errorCodeFromBits 0x7 = RefusedStream
errorCodeFromBits 0x8 = Cancel
errorCodeFromBits 0x9 = CompressionError
errorCodeFromBits 0xa = ConnectError
errorCodeFromBits 0xb = EnhanceYourCalm
errorCodeFromBits 0xc = InadequateSecurity
errorCodeFromBits 0xd = HTTP11Required
errorCodeFromBits c = UnknownErrorCode c

||| Equal codes have equal numbers.
export
Eq ErrorCode where
  a == b = errorCodeToBits a == errorCodeToBits b

||| The name RFC 9113 gives the code, like `PROTOCOL_ERROR`.
export
Show ErrorCode where
  show NoError = "NO_ERROR"
  show ProtocolError = "PROTOCOL_ERROR"
  show InternalError = "INTERNAL_ERROR"
  show FlowControlError = "FLOW_CONTROL_ERROR"
  show SettingsTimeout = "SETTINGS_TIMEOUT"
  show StreamClosed = "STREAM_CLOSED"
  show FrameSizeError = "FRAME_SIZE_ERROR"
  show RefusedStream = "REFUSED_STREAM"
  show Cancel = "CANCEL"
  show CompressionError = "COMPRESSION_ERROR"
  show ConnectError = "CONNECT_ERROR"
  show EnhanceYourCalm = "ENHANCE_YOUR_CALM"
  show InadequateSecurity = "INADEQUATE_SECURITY"
  show HTTP11Required = "HTTP_1_1_REQUIRED"
  show (UnknownErrorCode c) = "UNKNOWN_ERROR_" ++ show c

--------------------------------------------------------------------------
-- Settings (section 6.5.2)
--------------------------------------------------------------------------

||| The identifiers of settings.
public export
data SettingId : Type where
  HeaderTableSize : SettingId
  EnablePush : SettingId
  MaxConcurrentStreams : SettingId
  InitialWindowSize : SettingId
  MaxFrameSize : SettingId
  MaxHeaderListSize : SettingId
  ||| A setting this module does not know, which must be ignored.
  UnknownSetting : Bits16 -> SettingId

||| The number of a setting.
export
settingIdToBits : SettingId -> Bits16
settingIdToBits HeaderTableSize = 0x1
settingIdToBits EnablePush = 0x2
settingIdToBits MaxConcurrentStreams = 0x3
settingIdToBits InitialWindowSize = 0x4
settingIdToBits MaxFrameSize = 0x5
settingIdToBits MaxHeaderListSize = 0x6
settingIdToBits (UnknownSetting n) = n

||| The setting of a number.
export
settingIdFromBits : Bits16 -> SettingId
settingIdFromBits 0x1 = HeaderTableSize
settingIdFromBits 0x2 = EnablePush
settingIdFromBits 0x3 = MaxConcurrentStreams
settingIdFromBits 0x4 = InitialWindowSize
settingIdFromBits 0x5 = MaxFrameSize
settingIdFromBits 0x6 = MaxHeaderListSize
settingIdFromBits n = UnknownSetting n

||| Equal settings have equal numbers.
export
Eq SettingId where
  a == b = settingIdToBits a == settingIdToBits b

||| The name RFC 9113 gives the setting, like `SETTINGS_MAX_FRAME_SIZE`.
export
Show SettingId where
  show HeaderTableSize = "SETTINGS_HEADER_TABLE_SIZE"
  show EnablePush = "SETTINGS_ENABLE_PUSH"
  show MaxConcurrentStreams = "SETTINGS_MAX_CONCURRENT_STREAMS"
  show InitialWindowSize = "SETTINGS_INITIAL_WINDOW_SIZE"
  show MaxFrameSize = "SETTINGS_MAX_FRAME_SIZE"
  show MaxHeaderListSize = "SETTINGS_MAX_HEADER_LIST_SIZE"
  show (UnknownSetting n) = "SETTINGS_UNKNOWN_" ++ show n

||| The values of the settings of one endpoint.  `Nothing` is "no limit",
||| the initial value of the two settings that have no default.
public export
record Settings where
  constructor MkSettings
  headerTableSize : Int
  enablePush : Bool
  maxConcurrentStreams : Maybe Int
  initialWindowSize : Int
  maxFrameSize : Int
  maxHeaderListSize : Maybe Int

||| The initial values of section 6.5.2: a header table of 4096 bytes,
||| push enabled, no stream limit, windows of 65535 bytes, frames of up to
||| 16384 bytes, no header list limit.
export
defaultSettings : Settings
defaultSettings = MkSettings 4096 True Nothing 65535 16384 Nothing

||| Apply the parameters of a SETTINGS frame, in order (section 6.5.3).
||| The values must have been validated (`decodeFrame` does).  Unknown
||| settings are ignored.
export
applySettings : List (SettingId, Bits32) -> Settings -> Settings
applySettings [] s = s
applySettings ((k, v) :: rest) s = applySettings rest (set k (cast v) s)
  where
    set : SettingId -> Int -> Settings -> Settings
    set HeaderTableSize n = { headerTableSize := n }
    set EnablePush n = { enablePush := n == 1 }
    set MaxConcurrentStreams n = { maxConcurrentStreams := Just n }
    set InitialWindowSize n = { initialWindowSize := n }
    set MaxFrameSize n = { maxFrameSize := n }
    set MaxHeaderListSize n = { maxHeaderListSize := Just n }
    set (UnknownSetting _) _ = id

--------------------------------------------------------------------------
-- Frame types, flags, header (section 4.1)
--------------------------------------------------------------------------

||| The connection preface of the client (section 3.4):
||| `PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n`, 24 bytes, followed by a SETTINGS frame.
export
connectionPreface : ByteString
connectionPreface = "PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n"

||| The result of looking for the preface at the start of the input.
public export
data PrefaceResult : Type where
  ||| The input is a proper prefix of the preface.
  PrefaceNeedMore : (needed : Int) -> PrefaceResult
  ||| The preface, and the bytes after it.
  PrefaceOk : (rest : ByteString) -> PrefaceResult
  ||| The input does not start with the preface (a PROTOCOL_ERROR; the
  ||| peer may be speaking HTTP/1.1).
  PrefaceBad : PrefaceResult

||| Check that the input starts with the connection preface, so far as it
||| goes.
export
checkPreface : ByteString -> PrefaceResult
checkPreface bs =
  let n = lengthInt bs
      m = lengthInt connectionPreface
      k = min n m
  in if unsafeSlice 0 k bs /= unsafeSlice 0 k connectionPreface then PrefaceBad
     else if n < m then PrefaceNeedMore (m - n)
     else PrefaceOk (unsafeSlice m (n - m) bs)

||| The 9-byte header of a frame: the length of the payload (24 bits), the
||| type, the flags and the stream identifier (31 bits; the reserved bit is
||| ignored when decoding and sent as 0).
public export
record FrameHeader where
  constructor MkFrameHeader
  length : Int
  type : Bits8
  flags : Bits8
  streamId : Int

||| All fields equal.
export
Eq FrameHeader where
  a == b = a.length == b.length && a.type == b.type && a.flags == b.flags
           && a.streamId == b.streamId

||| The fields, for debugging.
export
Show FrameHeader where
  show h = "FrameHeader length=" ++ show h.length ++ " type=" ++ show h.type
           ++ " flags=" ++ show h.flags ++ " stream=" ++ show h.streamId

||| The size of a frame header.
export
frameHeaderSize : Int
frameHeaderSize = 9

||| The smallest and the largest value of SETTINGS_MAX_FRAME_SIZE.
export
minMaxFrameSize, maxMaxFrameSize : Int
minMaxFrameSize = 16384
maxMaxFrameSize = 16777215

||| The largest window size and window increment, 2^31 - 1.
export
maxWindowSize : Int
maxWindowSize = 0x7FFFFFFF

||| The frame type numbers.
export
typeData, typeHeaders, typePriority, typeRstStream, typeSettings,
  typePushPromise, typePing, typeGoAway, typeWindowUpdate, typeContinuation : Bits8
typeData = 0x0
typeHeaders = 0x1
typePriority = 0x2
typeRstStream = 0x3
typeSettings = 0x4
typePushPromise = 0x5
typePing = 0x6
typeGoAway = 0x7
typeWindowUpdate = 0x8
typeContinuation = 0x9

||| The flags.  ACK (0x1) is for SETTINGS and PING, END_STREAM (0x1) for
||| DATA and HEADERS.
export
flagEndStream, flagAck, flagEndHeaders, flagPadded, flagPriority : Bits8
flagEndStream = 0x1
flagAck = 0x1
flagEndHeaders = 0x4
flagPadded = 0x8
flagPriority = 0x20

%inline
has : Bits8 -> Bits8 -> Bool
has flags f = prim__and_Bits8 flags f /= 0

%inline
be32 : ByteString -> Int -> Int
be32 bs i =
  prim__or_Int (prim__shl_Int (cast (unsafeIndex bs i)) 24)
    (prim__or_Int (prim__shl_Int (cast (unsafeIndex bs (i + 1))) 16)
      (prim__or_Int (prim__shl_Int (cast (unsafeIndex bs (i + 2))) 8) (cast (unsafeIndex bs (i + 3)))))

%inline
be31 : ByteString -> Int -> Int
be31 bs i = prim__and_Int (be32 bs i) 0x7FFFFFFF

||| Decode a frame header from the first 9 bytes, or `Nothing` if there
||| are fewer.
export
decodeFrameHeader : ByteString -> Maybe FrameHeader
decodeFrameHeader bs =
  if lengthInt bs < 9 then Nothing
  else Just (MkFrameHeader
               (prim__or_Int (prim__shl_Int (cast (unsafeIndex bs 0)) 16)
                  (prim__or_Int (prim__shl_Int (cast (unsafeIndex bs 1)) 8) (cast (unsafeIndex bs 2))))
               (unsafeIndex bs 3) (unsafeIndex bs 4) (be31 bs 5))

||| Encode a frame header (the length must be below 2^24, the stream
||| identifier below 2^31).
export
encodeFrameHeader : FrameHeader -> Builder
encodeFrameHeader h =
  word8 (cast (prim__shr_Int h.length 16)) <+> word16BE (cast h.length)
  <+> word8 h.type <+> word8 h.flags
  <+> word32BE (cast (prim__and_Int h.streamId 0x7FFFFFFF))

--------------------------------------------------------------------------
-- Frames (section 6)
--------------------------------------------------------------------------

||| The priority fields of HEADERS and PRIORITY frames (section 5.3.1 of
||| RFC 7540; deprecated by RFC 9113 but still parsed).  `weight` is the
||| byte sent, the weight minus 1.
public export
record Priority where
  constructor MkPriority
  exclusive : Bool
  dependency : Int
  weight : Bits8

||| All fields equal.
export
Eq Priority where
  a == b = a.exclusive == b.exclusive && a.dependency == b.dependency && a.weight == b.weight

||| The fields, for debugging.
export
Show Priority where
  show p = "Priority " ++ show p.exclusive ++ " " ++ show p.dependency ++ " " ++ show p.weight

||| A frame.  `padding` is the number of padding bytes (`Nothing` when the
||| PADDED flag is not set, `Just 0` for a pad length byte of 0); when a
||| frame is decoded it does not count in the payload, but it counts
||| towards flow control for DATA (section 6.1), as does the pad length
||| byte: the length of the frame is in its header.
public export
data Frame : Type where
  DataFrame : (stream : Int) -> (endStream : Bool) -> (padding : Maybe Int) ->
              (payload : ByteString) -> Frame
  Headers : (stream : Int) -> (endStream : Bool) -> (endHeaders : Bool) ->
            (priority : Maybe Priority) -> (padding : Maybe Int) ->
            (fieldBlock : ByteString) -> Frame
  PriorityFrame : (stream : Int) -> Priority -> Frame
  RstStream : (stream : Int) -> ErrorCode -> Frame
  ||| An acknowledgement has no parameters.
  SettingsFrame : (ack : Bool) -> List (SettingId, Bits32) -> Frame
  PushPromise : (stream : Int) -> (endHeaders : Bool) -> (padding : Maybe Int) ->
                (promised : Int) -> (fieldBlock : ByteString) -> Frame
  ||| The opaque data is 8 bytes.
  Ping : (ack : Bool) -> (opaque : ByteString) -> Frame
  GoAway : (lastStream : Int) -> ErrorCode -> (debug : ByteString) -> Frame
  WindowUpdate : (stream : Int) -> (increment : Int) -> Frame
  Continuation : (stream : Int) -> (endHeaders : Bool) -> (fieldBlock : ByteString) -> Frame
  ||| A frame of an unknown type, which must be ignored (section 4.1;
  ||| except inside a field block, which the connection layer checks).
  UnknownFrame : (type : Bits8) -> (flags : Bits8) -> (stream : Int) ->
                 (payload : ByteString) -> Frame

||| All fields equal.
export
Eq Frame where
  DataFrame a b c d == DataFrame a' b' c' d' = a == a' && b == b' && c == c' && d == d'
  Headers a b c d e g == Headers a' b' c' d' e' g' =
    a == a' && b == b' && c == c' && d == d' && e == e' && g == g'
  PriorityFrame a b == PriorityFrame a' b' = a == a' && b == b'
  RstStream a b == RstStream a' b' = a == a' && b == b'
  SettingsFrame a b == SettingsFrame a' b' = a == a' && b == b'
  PushPromise a b c d e == PushPromise a' b' c' d' e' =
    a == a' && b == b' && c == c' && d == d' && e == e'
  Ping a b == Ping a' b' = a == a' && b == b'
  GoAway a b c == GoAway a' b' c' = a == a' && b == b' && c == c'
  WindowUpdate a b == WindowUpdate a' b' = a == a' && b == b'
  Continuation a b c == Continuation a' b' c' = a == a' && b == b' && c == c'
  UnknownFrame a b c d == UnknownFrame a' b' c' d' = a == a' && b == b' && c == c' && d == d'
  _ == _ = False

||| The frame, with byte strings in hexadecimal, for debugging.
export
Show Frame where
  show (DataFrame s e p d) = "DATA " ++ show s ++ " " ++ show e ++ " " ++ show p ++ " " ++ toHex d
  show (Headers s e h pr p b) =
    "HEADERS " ++ show s ++ " " ++ show e ++ " " ++ show h ++ " " ++ show pr ++ " "
    ++ show p ++ " " ++ toHex b
  show (PriorityFrame s p) = "PRIORITY " ++ show s ++ " " ++ show p
  show (RstStream s c) = "RST_STREAM " ++ show s ++ " " ++ show c
  show (SettingsFrame a ps) = "SETTINGS " ++ show a ++ " " ++ show ps
  show (PushPromise s h p pr b) =
    "PUSH_PROMISE " ++ show s ++ " " ++ show h ++ " " ++ show p ++ " " ++ show pr ++ " " ++ toHex b
  show (Ping a d) = "PING " ++ show a ++ " " ++ toHex d
  show (GoAway l c d) = "GOAWAY " ++ show l ++ " " ++ show c ++ " " ++ toHex d
  show (WindowUpdate s i) = "WINDOW_UPDATE " ++ show s ++ " " ++ show i
  show (Continuation s h b) = "CONTINUATION " ++ show s ++ " " ++ show h ++ " " ++ toHex b
  show (UnknownFrame t f s d) =
    "UNKNOWN " ++ show t ++ " " ++ show f ++ " " ++ show s ++ " " ++ toHex d

--------------------------------------------------------------------------
-- Encoding
--------------------------------------------------------------------------

-- The pad length byte and the padding of a padded frame.
padParts : Maybe Int -> (Builder, Builder, Int, Bits8)
padParts Nothing = (empty, empty, 0, 0)
padParts (Just n) = (word8 (cast n), replicate (cast n) 0, n + 1, flagPadded)

priorityBytes : Priority -> Builder
priorityBytes p =
  word32BE (cast (prim__or_Int (prim__and_Int p.dependency 0x7FFFFFFF)
                               (if p.exclusive then 0x80000000 else 0)))
  <+> word8 p.weight

-- A frame of a header and a payload builder of a known length.
frame : Bits8 -> Bits8 -> Int -> Int -> Builder -> Builder
frame type flags stream len payload =
  encodeFrameHeader (MkFrameHeader len type flags stream) <+> payload

%inline
flagIf : Bool -> Bits8 -> Bits8
flagIf b f = if b then f else 0

||| The bytes of a frame: its header and its payload.  The frame is not
||| checked (see `decodeFrame` for the rules).
export
encodeFrame : Frame -> Builder
encodeFrame (DataFrame s e p d) =
  let (pl, pad, extra, pf) = padParts p in
  frame typeData (flagIf e flagEndStream .|. pf) s (lengthInt d + extra) (pl <+> byteString d <+> pad)
encodeFrame (Headers s e h pr p b) =
  let (pl, pad, extra, pf) = padParts p
      (prb, prn, prf) = the (Builder, Int, Bits8) $ case pr of
                          Nothing => (empty, 0, 0)
                          Just x => (priorityBytes x, 5, flagPriority)
  in frame typeHeaders (flagIf e flagEndStream .|. flagIf h flagEndHeaders .|. pf .|. prf) s
           (lengthInt b + extra + prn) (pl <+> prb <+> byteString b <+> pad)
encodeFrame (PriorityFrame s p) = frame typePriority 0 s 5 (priorityBytes p)
encodeFrame (RstStream s c) = frame typeRstStream 0 s 4 (word32BE (errorCodeToBits c))
encodeFrame (SettingsFrame a ps) =
  frame typeSettings (flagIf a flagAck) 0 (6 * cast (length ps))
        (concatMap (\(k, v) => word16BE (settingIdToBits k) <+> word32BE v) ps)
encodeFrame (PushPromise s h p pr b) =
  let (pl, pad, extra, pf) = padParts p in
  frame typePushPromise (flagIf h flagEndHeaders .|. pf) s (lengthInt b + extra + 4)
        (pl <+> word32BE (cast (prim__and_Int pr 0x7FFFFFFF)) <+> byteString b <+> pad)
encodeFrame (Ping a d) = frame typePing (flagIf a flagAck) 0 (lengthInt d) (byteString d)
encodeFrame (GoAway l c d) =
  frame typeGoAway 0 0 (8 + lengthInt d)
        (word32BE (cast (prim__and_Int l 0x7FFFFFFF)) <+> word32BE (errorCodeToBits c) <+> byteString d)
encodeFrame (WindowUpdate s i) =
  frame typeWindowUpdate 0 s 4 (word32BE (cast (prim__and_Int i 0x7FFFFFFF)))
encodeFrame (Continuation s h b) =
  frame typeContinuation (flagIf h flagEndHeaders) s (lengthInt b) (byteString b)
encodeFrame (UnknownFrame t f s d) = frame t f s (lengthInt d) (byteString d)

--------------------------------------------------------------------------
-- Decoding
--------------------------------------------------------------------------

||| A violation of the protocol found in a frame, with the error code to
||| send and a short explanation: an error of the whole connection (send
||| GOAWAY and close, section 5.4.1), or of one stream (send RST_STREAM on
||| it, section 5.4.2).
public export
data FrameError : Type where
  ConnectionError : ErrorCode -> String -> FrameError
  StreamError : (stream : Int) -> ErrorCode -> String -> FrameError

||| Same scope, stream and code (the explanation is not compared).
export
Eq FrameError where
  ConnectionError c _ == ConnectionError c' _ = c == c'
  StreamError s c _ == StreamError s' c' _ = s == s' && c == c'
  _ == _ = False

||| The scope, code and explanation.
export
Show FrameError where
  show (ConnectionError c m) = "connection error " ++ show c ++ ": " ++ m
  show (StreamError s c m) = "stream error on " ++ show s ++ " " ++ show c ++ ": " ++ m

||| The result of `decodeFrame`.
public export
data FrameResult : Type where
  ||| At least this many more bytes are needed.
  NeedMore : (needed : Int) -> FrameResult
  ||| A frame, and the bytes after it.
  Decoded : Frame -> (rest : ByteString) -> FrameResult
  ||| The frame breaks a rule.  `rest` is the input after the frame (with a
  ||| stream error the connection goes on there); after a frame that is
  ||| larger than the limit, which is not read, it is the input after the
  ||| header.
  Failed : FrameError -> (rest : ByteString) -> FrameResult

connErr : ErrorCode -> String -> Either FrameError a
connErr c m = Left (ConnectionError c m)

-- The padding of a padded frame: the pad length and the payload without
-- it and the pad length byte, given the bytes after any fixed fields
-- before the data (`skip` of them follow the pad length byte).
unpad : Bits8 -> ByteString -> (skip : Int) ->
        Either FrameError (Maybe Int, ByteString)
unpad flags p skip =
  if not (has flags flagPadded) then Right (Nothing, p)
  else if lengthInt p < 1 then connErr FrameSizeError "no pad length"
  else let padLen = cast {to = Int} (unsafeIndex p 0)
           rest = lengthInt p - 1
       in if padLen > rest - skip
             then connErr ProtocolError "padding as long as the payload"
             else Right (Just padLen, unsafeSlice 1 (rest - padLen) p)

-- Settings parameters, validated (section 6.5.2).
settingsList : ByteString -> Int -> Int -> List (SettingId, Bits32) ->
               Either FrameError (List (SettingId, Bits32))
settingsList p i n acc =
  if i >= n then Right (reverse acc)
  else let k = settingIdFromBits (cast (prim__or_Int (prim__shl_Int (cast (unsafeIndex p i)) 8)
                                                    (cast (unsafeIndex p (i + 1)))))
           v = be32 p (i + 2)
           next = settingsList p (assert_smaller i (i + 6)) n ((k, cast v) :: acc)
       in case k of
            EnablePush => if v > 1 then connErr ProtocolError "SETTINGS_ENABLE_PUSH not 0 or 1" else next
            InitialWindowSize =>
              if v > maxWindowSize then connErr FlowControlError "SETTINGS_INITIAL_WINDOW_SIZE above 2^31-1"
              else next
            MaxFrameSize =>
              if v < minMaxFrameSize || v > maxMaxFrameSize
                 then connErr ProtocolError "SETTINGS_MAX_FRAME_SIZE out of range" else next
            _ => next

-- The frame of a header and its payload.
payloadFrame : FrameHeader -> ByteString -> Either FrameError Frame
payloadFrame h p =
  let s = h.streamId
      len = h.length
      f = h.flags
  in case h.type of
    0x0 => -- DATA
      if s == 0 then connErr ProtocolError "DATA on stream 0" else do
        (pad, d) <- unpad f p 0
        Right (DataFrame s (has f flagEndStream) pad d)
    0x1 => -- HEADERS
      if s == 0 then connErr ProtocolError "HEADERS on stream 0" else do
        let prn = the Int (if has f flagPriority then 5 else 0)
        (pad, d) <- unpad f p prn
        if lengthInt d < prn then connErr FrameSizeError "HEADERS too short for priority" else do
          let pr = if has f flagPriority
                      then Just (MkPriority (unsafeIndex d 0 >= 0x80) (be31 d 0) (unsafeIndex d 4))
                      else Nothing
          case pr of
            Just x => if x.dependency == s
                         then Left (StreamError s ProtocolError "stream depends on itself")
                         else Right ()
            Nothing => Right ()
          Right (Headers s (has f flagEndStream) (has f flagEndHeaders) pr pad
                         (unsafeSlice prn (lengthInt d - prn) d))
    0x2 => -- PRIORITY
      if s == 0 then connErr ProtocolError "PRIORITY on stream 0"
      else if len /= 5 then Left (StreamError s FrameSizeError "PRIORITY length not 5")
      else let x = MkPriority (unsafeIndex p 0 >= 0x80) (be31 p 0) (unsafeIndex p 4) in
           if x.dependency == s then Left (StreamError s ProtocolError "stream depends on itself")
           else Right (PriorityFrame s x)
    0x3 => -- RST_STREAM
      if s == 0 then connErr ProtocolError "RST_STREAM on stream 0"
      else if len /= 4 then connErr FrameSizeError "RST_STREAM length not 4"
      else Right (RstStream s (errorCodeFromBits (cast (be32 p 0))))
    0x4 => -- SETTINGS
      if s /= 0 then connErr ProtocolError "SETTINGS on a stream"
      else if has f flagAck
        then (if len /= 0 then connErr FrameSizeError "SETTINGS ACK with a payload"
              else Right (SettingsFrame True []))
      else if assert_total (prim__mod_Int len 6) /= 0 then connErr FrameSizeError "SETTINGS length not a multiple of 6"
      else map (SettingsFrame False) (settingsList p 0 len [])
    0x5 => -- PUSH_PROMISE
      if s == 0 then connErr ProtocolError "PUSH_PROMISE on stream 0" else do
        (pad, d) <- unpad f p 4
        if lengthInt d < 4 then connErr FrameSizeError "PUSH_PROMISE too short" else
          Right (PushPromise s (has f flagEndHeaders) pad (be31 d 0) (unsafeSlice 4 (lengthInt d - 4) d))
    0x6 => -- PING
      if s /= 0 then connErr ProtocolError "PING on a stream"
      else if len /= 8 then connErr FrameSizeError "PING length not 8"
      else Right (Ping (has f flagAck) p)
    0x7 => -- GOAWAY
      if s /= 0 then connErr ProtocolError "GOAWAY on a stream"
      else if len < 8 then connErr FrameSizeError "GOAWAY shorter than 8"
      else Right (GoAway (be31 p 0) (errorCodeFromBits (cast (be32 p 4))) (unsafeSlice 8 (len - 8) p))
    0x8 => -- WINDOW_UPDATE
      if len /= 4 then connErr FrameSizeError "WINDOW_UPDATE length not 4"
      else let inc = be31 p 0 in
           if inc == 0
              then (if s == 0 then connErr ProtocolError "WINDOW_UPDATE of 0"
                    else Left (StreamError s ProtocolError "WINDOW_UPDATE of 0"))
              else Right (WindowUpdate s inc)
    0x9 => -- CONTINUATION
      if s == 0 then connErr ProtocolError "CONTINUATION on stream 0"
      else Right (Continuation s (has f flagEndHeaders) p)
    t => Right (UnknownFrame t f s p)

||| Decode the frame at the start of the input, with our
||| SETTINGS_MAX_FRAME_SIZE as the limit on its length (a larger frame is
||| a FRAME_SIZE_ERROR of the connection, section 4.2).
export
decodeFrame : (maxFrameSize : Int) -> ByteString -> FrameResult
decodeFrame maxSize bs =
  case decodeFrameHeader bs of
    Nothing => NeedMore (9 - lengthInt bs)
    Just hdr => withHeader hdr
  where
    withHeader : FrameHeader -> FrameResult
    withHeader hdr =
      let avail = lengthInt bs
          frameEnd = 9 + hdr.length
      in if hdr.length > maxSize
            then Failed (ConnectionError FrameSizeError "frame larger than SETTINGS_MAX_FRAME_SIZE")
                        (unsafeSlice 9 (avail - 9) bs)
         else if avail < frameEnd then NeedMore (frameEnd - avail)
         else case payloadFrame hdr (unsafeSlice 9 hdr.length bs) of
                Right fr => Decoded fr (unsafeSlice frameEnd (avail - frameEnd) bs)
                Left e => Failed e (unsafeSlice frameEnd (avail - frameEnd) bs)
