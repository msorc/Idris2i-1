||| Incremental UTF-8 validation, for WebSocket text messages (RFC 6455
||| sections 5.6 and 8.1).
|||
||| A text message may be split into frames, and a frame's payload into
||| reads, at any byte, also inside a code point.  A `Utf8State` remembers
||| what the bytes seen so far still need: feed it each piece as it arrives
||| with `feedUtf8`, and when the message is complete check `utf8Complete`.
||| An invalid byte is detected as soon as it is fed (so a connection can
||| fail fast, as section 8.1 asks) and the state stays invalid.
|||
||| The rules are those of RFC 3629: the shortest form only, no surrogates
||| (U+D800..U+DFFF), nothing above U+10FFFF.  Runs of ASCII are checked
||| eight bytes at a time.
module Network.WebSocket.UTF8

import Data.Buffer
import Data.ByteString
import Data.ByteString.Internal

%default total

||| What the bytes so far need to be valid UTF-8.  `0` means "at a code
||| point boundary"; a negative value means "invalid"; a positive value
||| encodes the number of continuation bytes still due and the range the
||| next one must be in.
export
record Utf8State where
  constructor MkUtf8State
  code : Int

||| The state before any byte: at a boundary.
export
utf8Start : Utf8State
utf8Start = MkUtf8State 0

||| Has an invalid byte been seen?
export
utf8Invalid : Utf8State -> Bool
utf8Invalid s = s.code < 0

||| Are the bytes so far valid UTF-8 ending at a code point boundary (so
||| that the message may end here)?
export
utf8Complete : Utf8State -> Bool
utf8Complete s = s.code == 0

-- A state: `need` continuation bytes due, the next in `[lo, hi]`.
pending : Int -> Int -> Int -> Int
pending need lo hi = need * 65536 + lo * 256 + hi

-- The next state after one byte.
stepByte : Int -> Int -> Int
stepByte st b =
  if st == 0
    then if b < 0x80 then 0
         else if b < 0xC2 then -1
         else if b < 0xE0 then pending 1 0x80 0xBF
         else if b == 0xE0 then pending 2 0xA0 0xBF
         else if b == 0xED then pending 2 0x80 0x9F
         else if b < 0xF0 then pending 2 0x80 0xBF
         else if b == 0xF0 then pending 3 0x90 0xBF
         else if b < 0xF4 then pending 3 0x80 0xBF
         else if b == 0xF4 then pending 3 0x80 0x8F
         else -1
    else let need = prim__shr_Int st 16
             lo = prim__and_Int (prim__shr_Int st 8) 0xFF
             hi = prim__and_Int st 0xFF
         in if b < lo || b > hi then -1
            else if need == 1 then 0
            else pending (need - 1) 0x80 0xBF

-- Run over `[i, end)` of the buffer from state `st`.  At a boundary, eight
-- ASCII bytes are skipped at once.
run : Buffer -> Int -> Int -> Int -> Int
run buf i end st =
  if st < 0 || i >= end then st
  else if st == 0 && end - i >= 8 &&
          prim__and_Bits64 (unsafePerformIO (getBits64 buf i)) 0x8080808080808080 == 0
    then run buf (assert_smaller i (i + 8)) end 0
    else run buf (assert_smaller i (i + 1)) end
             (stepByte st (cast (unsafePerformIO (getBits8 buf i))))

||| Feed the next bytes.  Linear in their number; stops at the first invalid
||| byte (and then the state is invalid for good).
export
feedUtf8 : Utf8State -> ByteString -> Utf8State
feedUtf8 (MkUtf8State st) bs =
  let o = unsafeOffset bs in
  MkUtf8State (run (unsafeBuffer bs) o (o + lengthInt bs) st)

||| Is the whole byte string valid UTF-8?
export
validUtf8 : ByteString -> Bool
validUtf8 bs = utf8Complete (feedUtf8 utf8Start bs)
