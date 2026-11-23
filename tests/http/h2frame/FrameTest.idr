-- HTTP/2 frames (RFC 9113): round trips of every frame type, known
-- encodings, the validity rules of single frames, partial input, the
-- connection preface.
import Data.ByteString as BS
import Data.ByteString.Builder
import Data.List
import Data.String
import Network.HTTP2.Frame

%default total

-- The bytes of hexadecimal digits (spaces are ignored).
hex : String -> ByteString
hex s = BS.pack (go (filter (/= ' ') (unpack s)))
  where
    digit : Char -> Bits8
    digit c = if c >= 'a' then cast (ord c - 87) else cast (ord c - 48)
    go : List Char -> List Bits8
    go (a :: b :: rest) = (digit a * 16 + digit b) :: go rest
    go _ = []

check : String -> Bool -> String -> IO ()
check name ok detail = putStrLn (name ++ ": " ++ (if ok then "ok" else "FAIL " ++ detail))

showResult : FrameResult -> String
showResult (NeedMore n) = "need " ++ show n
showResult (Decoded f rest) = "frame " ++ show f ++ " rest " ++ toHex rest
showResult (Failed e rest) = show e ++ " rest " ++ toHex rest

-- Encode, compare with the expected bytes, decode again (with a byte
-- after the frame, which must be left), and decode every proper prefix.
roundTrip : String -> Frame -> String -> IO ()
roundTrip name f bytes = do
  let enc = toByteString (encodeFrame f)
  check (name ++ " encode") (enc == hex bytes) (toHex enc)
  case decodeFrame 16384 (enc <+> BS.singleton 0xAB) of
    Decoded f' rest => check (name ++ " decode") (f' == f && toHex rest == "ab") (show f')
    r => check (name ++ " decode") False (showResult r)
  let n = cast {to = Int} (BS.length enc)
      prefixesOk = all (\k => case decodeFrame 16384 (BS.take (cast k) enc) of
                             NeedMore m => m == (if k < 9 then 9 - k else n - k)
                             _ => False) [0 .. n - 1]
  check (name ++ " prefixes need more") prefixesOk ""

-- Decode raw bytes and compare the printed result.
expect : String -> String -> String -> IO ()
expect name bytes want =
  let got = showResult (decodeFrame 16384 (hex bytes)) in
  check name (got == want) got

showSettings : Settings -> String
showSettings s =
  unwords [show s.headerTableSize, show s.enablePush, show s.maxConcurrentStreams,
           show s.initialWindowSize, show s.maxFrameSize, show s.maxHeaderListSize]

main : IO ()
main = do
  putStrLn "-- header"
  let h = MkFrameHeader 0x123456 0x07 0xA5 0x7FFFFFFF
  check "header encode" (toHex (toByteString (encodeFrameHeader h)) == "12345607a57fffffff") ""
  check "header decode" (decodeFrameHeader (hex "12345607a57fffffff") == Just h) ""
  check "reserved bit ignored" (map (.streamId) (decodeFrameHeader (hex "000000000080000001")) == Just 1) ""
  check "header needs 9 bytes" (decodeFrameHeader (hex "0000000000000000") == Nothing) ""
  putStrLn "-- round trips"
  roundTrip "DATA" (DataFrame 1 True Nothing "hello") "000005 00 01 00000001 68656c6c6f"
  roundTrip "DATA padded" (DataFrame 3 False (Just 2) "hi") "000005 00 08 00000003 02 6869 0000"
  roundTrip "DATA empty pad" (DataFrame 3 False (Just 0) "") "000001 00 08 00000003 00"
  roundTrip "HEADERS" (Headers 1 False True Nothing Nothing (hex "8286")) "000002 01 04 00000001 8286"
  roundTrip "HEADERS priority padded"
    (Headers 5 True False (Just (MkPriority True 3 15)) (Just 1) (hex "82"))
    "000008 01 29 00000005 01 80000003 0f 82 00"
  roundTrip "PRIORITY" (PriorityFrame 7 (MkPriority False 1 255)) "000005 02 00 00000007 00000001 ff"
  roundTrip "RST_STREAM" (RstStream 1 Cancel) "000004 03 00 00000001 00000008"
  roundTrip "RST_STREAM unknown code" (RstStream 1 (UnknownErrorCode 0x77)) "000004 03 00 00000001 00000077"
  roundTrip "SETTINGS"
    (SettingsFrame False [(HeaderTableSize, 8192), (EnablePush, 0), (MaxConcurrentStreams, 100),
                          (InitialWindowSize, 1048576), (MaxFrameSize, 16777215),
                          (MaxHeaderListSize, 65536), (UnknownSetting 0x99, 5)])
    "00002a 04 00 00000000 0001 00002000 0002 00000000 0003 00000064 0004 00100000 0005 00ffffff 0006 00010000 0099 00000005"
  roundTrip "SETTINGS ACK" (SettingsFrame True []) "000000 04 01 00000000"
  roundTrip "PUSH_PROMISE" (PushPromise 1 True Nothing 2 (hex "8287")) "000006 05 04 00000001 00000002 8287"
  roundTrip "PUSH_PROMISE padded" (PushPromise 1 False (Just 3) 4 (hex "82"))
    "000009 05 08 00000001 03 00000004 82 000000"
  roundTrip "PING" (Ping False (hex "0102030405060708")) "000008 06 00 00000000 0102030405060708"
  roundTrip "PING ACK" (Ping True (hex "0102030405060708")) "000008 06 01 00000000 0102030405060708"
  roundTrip "GOAWAY" (GoAway 5 ProtocolError "bye") "00000b 07 00 00000000 00000005 00000001 627965"
  roundTrip "WINDOW_UPDATE" (WindowUpdate 0 0x7FFFFFFF) "000004 08 00 00000000 7fffffff"
  roundTrip "WINDOW_UPDATE stream" (WindowUpdate 3 4096) "000004 08 00 00000003 00001000"
  roundTrip "CONTINUATION" (Continuation 1 True (hex "8384")) "000002 09 04 00000001 8384"
  roundTrip "unknown type" (UnknownFrame 0xEE 0x3 9 "xy") "000002 ee 03 00000009 7879"
  putStrLn "-- flags that do not belong to the type are ignored"
  expect "DATA with ACK-like and unknown flags" "000001 00 f6 00000001 61"
    "frame DATA 1 False Nothing 61 rest "
  putStrLn "-- validity of single frames"
  expect "DATA on stream 0" "000001 00 00 00000000 61" "connection error PROTOCOL_ERROR: DATA on stream 0 rest "
  expect "DATA padding as long as the payload" "000003 00 08 00000001 03 6161"
    "connection error PROTOCOL_ERROR: padding as long as the payload rest "
  expect "DATA padding of all but the pad length" "000003 00 08 00000001 02 6161"
    "frame DATA 1 False Just 2  rest "
  expect "DATA padded without pad length" "000000 00 08 00000001"
    "connection error FRAME_SIZE_ERROR: no pad length rest "
  expect "HEADERS on stream 0" "000001 01 04 00000000 82" "connection error PROTOCOL_ERROR: HEADERS on stream 0 rest "
  expect "HEADERS priority too short" "000003 01 24 00000001 000000"
    "connection error FRAME_SIZE_ERROR: HEADERS too short for priority rest "
  expect "HEADERS padding covering the priority" "000006 01 2c 00000001 01 00000000 10"
    "connection error PROTOCOL_ERROR: padding as long as the payload rest "
  expect "HEADERS depending on itself" "000006 01 24 00000003 00000003 0f 82"
    "stream error on 3 PROTOCOL_ERROR: stream depends on itself rest "
  expect "PRIORITY on stream 0" "000005 02 00 00000000 0000000100" "connection error PROTOCOL_ERROR: PRIORITY on stream 0 rest "
  expect "PRIORITY length 4" "000004 02 00 00000001 00000000 82"
    "stream error on 1 FRAME_SIZE_ERROR: PRIORITY length not 5 rest 82"
  expect "PRIORITY depending on itself" "000005 02 00 00000001 0000000100"
    "stream error on 1 PROTOCOL_ERROR: stream depends on itself rest "
  expect "RST_STREAM on stream 0" "000004 03 00 00000000 00000000" "connection error PROTOCOL_ERROR: RST_STREAM on stream 0 rest "
  expect "RST_STREAM length 5" "000005 03 00 00000001 0000000000" "connection error FRAME_SIZE_ERROR: RST_STREAM length not 4 rest "
  expect "SETTINGS on a stream" "000000 04 00 00000001" "connection error PROTOCOL_ERROR: SETTINGS on a stream rest "
  expect "SETTINGS ACK with payload" "000006 04 01 00000000 000100001000"
    "connection error FRAME_SIZE_ERROR: SETTINGS ACK with a payload rest "
  expect "SETTINGS length 5" "000005 04 00 00000000 0001000010"
    "connection error FRAME_SIZE_ERROR: SETTINGS length not a multiple of 6 rest "
  expect "SETTINGS_ENABLE_PUSH 2" "000006 04 00 00000000 000200000002"
    "connection error PROTOCOL_ERROR: SETTINGS_ENABLE_PUSH not 0 or 1 rest "
  expect "SETTINGS_INITIAL_WINDOW_SIZE 2^31" "000006 04 00 00000000 000480000000"
    "connection error FLOW_CONTROL_ERROR: SETTINGS_INITIAL_WINDOW_SIZE above 2^31-1 rest "
  expect "SETTINGS_INITIAL_WINDOW_SIZE 2^31-1" "000006 04 00 00000000 00047fffffff"
    "frame SETTINGS False [(SETTINGS_INITIAL_WINDOW_SIZE, 2147483647)] rest "
  expect "SETTINGS_MAX_FRAME_SIZE 16383" "000006 04 00 00000000 000500003fff"
    "connection error PROTOCOL_ERROR: SETTINGS_MAX_FRAME_SIZE out of range rest "
  expect "SETTINGS_MAX_FRAME_SIZE 2^24" "000006 04 00 00000000 000501000000"
    "connection error PROTOCOL_ERROR: SETTINGS_MAX_FRAME_SIZE out of range rest "
  expect "PUSH_PROMISE on stream 0" "000004 05 04 00000000 00000002"
    "connection error PROTOCOL_ERROR: PUSH_PROMISE on stream 0 rest "
  expect "PUSH_PROMISE too short" "000003 05 04 00000001 000000"
    "connection error FRAME_SIZE_ERROR: PUSH_PROMISE too short rest "
  expect "PING on a stream" "000008 06 00 00000001 0000000000000000" "connection error PROTOCOL_ERROR: PING on a stream rest "
  expect "PING length 7" "000007 06 00 00000000 00000000000000" "connection error FRAME_SIZE_ERROR: PING length not 8 rest "
  expect "GOAWAY on a stream" "000008 07 00 00000001 0000000000000000" "connection error PROTOCOL_ERROR: GOAWAY on a stream rest "
  expect "GOAWAY length 7" "000007 07 00 00000000 00000000000000" "connection error FRAME_SIZE_ERROR: GOAWAY shorter than 8 rest "
  expect "WINDOW_UPDATE length 3" "000003 08 00 00000000 000001" "connection error FRAME_SIZE_ERROR: WINDOW_UPDATE length not 4 rest "
  expect "WINDOW_UPDATE of 0 on the connection" "000004 08 00 00000000 00000000"
    "connection error PROTOCOL_ERROR: WINDOW_UPDATE of 0 rest "
  expect "WINDOW_UPDATE of 0 on a stream" "000004 08 00 00000001 80000000"
    "stream error on 1 PROTOCOL_ERROR: WINDOW_UPDATE of 0 rest "
  expect "CONTINUATION on stream 0" "000001 09 04 00000000 82" "connection error PROTOCOL_ERROR: CONTINUATION on stream 0 rest "
  expect "frame above the maximum size" "004001 00 00 00000001 61"
    "connection error FRAME_SIZE_ERROR: frame larger than SETTINGS_MAX_FRAME_SIZE rest 61"
  check "frame of exactly the maximum size"
        (case decodeFrame 16384 (hex "004000 00 00 00000001" <+> BS.replicate 16384 0x61) of
           Decoded (DataFrame 1 False Nothing d) _ => BS.length d == 16384
           _ => False) ""
  check "a larger limit"
        (case decodeFrame 20000 (hex "004001 00 00 00000001" <+> BS.replicate 16385 0x61) of
           Decoded (DataFrame 1 False Nothing d) _ => BS.length d == 16385
           _ => False) ""
  putStrLn "-- several frames in one buffer"
  let two = toByteString (encodeFrame (SettingsFrame True []) <+> encodeFrame (Ping False (hex "0000000000000001")))
  case decodeFrame 16384 two of
    Decoded f1 rest => do
      putStrLn ("first: " ++ show f1)
      putStrLn ("second: " ++ showResult (decodeFrame 16384 rest))
    r => putStrLn (showResult r)
  putStrLn "-- settings"
  let s = applySettings [(HeaderTableSize, 0), (EnablePush, 0), (MaxConcurrentStreams, 10),
                         (InitialWindowSize, 1), (MaxFrameSize, 32768), (MaxHeaderListSize, 99),
                         (UnknownSetting 7, 1), (InitialWindowSize, 2)] defaultSettings
  putStrLn ("defaults: " ++ showSettings defaultSettings)
  putStrLn ("applied: " ++ showSettings s)
  check "error codes" (map (errorCodeToBits . errorCodeFromBits) [0 .. 14] == [0 .. 14]
                       && map (show . errorCodeFromBits) [0, 6, 13] == ["NO_ERROR", "FRAME_SIZE_ERROR", "HTTP_1_1_REQUIRED"]) ""
  check "setting ids" (map (settingIdToBits . settingIdFromBits) [0 .. 7] == [0 .. 7]) ""
  putStrLn "-- preface"
  check "preface bytes" (toHex connectionPreface == "505249202a20485454502f322e300d0a0d0a534d0d0a0d0a") ""
  let showP : PrefaceResult -> String
      showP (PrefaceNeedMore n) = "need " ++ show n
      showP (PrefaceOk rest) = "ok, rest " ++ toHex rest
      showP PrefaceBad = "bad"
  putStrLn ("empty: " ++ showP (checkPreface BS.empty))
  putStrLn ("prefix: " ++ showP (checkPreface "PRI * HTTP/2"))
  putStrLn ("whole and more: " ++ showP (checkPreface (connectionPreface <+> hex "000000040100000000")))
  putStrLn ("HTTP/1.1: " ++ showP (checkPreface "GET / HTTP/1.1\r\n"))
  putStrLn ("wrong prefix: " ++ showP (checkPreface "PRX"))
