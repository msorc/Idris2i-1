||| SHA-1 (RFC 3174, FIPS 180-4) over `ByteString`.
|||
||| This module exists for one purpose: the opening handshake of the
||| WebSocket protocol (RFC 6455 section 4.2.2), which computes
||| `Sec-WebSocket-Accept` as the SHA-1 digest of the client's key and a
||| fixed GUID.  SHA-1 is broken as a cryptographic hash (collisions can be
||| computed), so do not use it for signatures, passwords, integrity checks
||| against an adversary, or anything else where security depends on it.
|||
||| ```idris
||| import Network.HTTP.SHA1
||| import Data.ByteString
|||
||| digest : ByteString
||| digest = sha1 (fromString "abc")   -- 20 bytes, a9993e36...
||| ```
|||
||| The implementation pads the message into one fresh buffer and runs the
||| 80 rounds over each 64-byte block with the five working variables as
||| unboxed `Bits32` arguments of a tail-recursive loop; the message schedule
||| lives in a 320-byte scratch buffer.
module Network.HTTP.SHA1

import Data.Buffer
import Data.ByteString
import Data.ByteString.Internal

%default total

--------------------------------------------------------------------------
-- Word helpers
--------------------------------------------------------------------------

-- Rotate left by `n` (1 <= n <= 31).
rotl : Bits32 -> Bits32 -> Bits32
rotl x n = prim__or_Bits32 (prim__shl_Bits32 x n) (prim__shr_Bits32 x (32 - n))

-- One step of an action in IO with the world passed by hand, so that the
-- loops below are saturated self tail calls on every back end.
%inline
step : IO a -> (1 w : %World) -> IORes a
step act w = toPrim act w

-- The big-endian 32-bit word at an offset of a buffer.
readBE32 : Buffer -> Int -> (1 w : %World) -> IORes Bits32
readBE32 b o w =
  case step (getBits8 b o) w of
    MkIORes b0 w1 => case step (getBits8 b (o + 1)) w1 of
      MkIORes b1 w2 => case step (getBits8 b (o + 2)) w2 of
        MkIORes b2 w3 => case step (getBits8 b (o + 3)) w3 of
          MkIORes b3 w4 =>
            MkIORes (prim__or_Bits32
                       (prim__or_Bits32 (prim__shl_Bits32 (cast b0) 24)
                                        (prim__shl_Bits32 (cast b1) 16))
                       (prim__or_Bits32 (prim__shl_Bits32 (cast b2) 8) (cast b3))) w4

-- Write a 32-bit word big-endian at an offset of a buffer.
writeBE32 : Buffer -> Int -> Bits32 -> (1 w : %World) -> IORes ()
writeBE32 b o v w =
  case step (setBits8 b o (cast (prim__shr_Bits32 v 24))) w of
    MkIORes () w1 => case step (setBits8 b (o + 1) (cast (prim__shr_Bits32 v 16))) w1 of
      MkIORes () w2 => case step (setBits8 b (o + 2) (cast (prim__shr_Bits32 v 8))) w2 of
        MkIORes () w3 => step (setBits8 b (o + 3) (cast v)) w3

--------------------------------------------------------------------------
-- The compression function
--------------------------------------------------------------------------

-- Load the 16 words of the block at `off` of `msg` into the schedule
-- buffer (native order) and extend them to 80.
schedule : Buffer -> Int -> Buffer -> Int -> (1 w : %World) -> IORes ()
schedule msg off ws t w =
  if t >= 80 then MkIORes () w
  else if t < 16
    then case readBE32 msg (off + 4 * t) w of
           MkIORes v w1 => case step (setBits32 ws (4 * t) v) w1 of
             MkIORes () w2 => schedule msg off ws (assert_smaller t (t + 1)) w2
    else case step (getBits32 ws (4 * (t - 3))) w of
      MkIORes a w1 => case step (getBits32 ws (4 * (t - 8))) w1 of
        MkIORes b w2 => case step (getBits32 ws (4 * (t - 14))) w2 of
          MkIORes c w3 => case step (getBits32 ws (4 * (t - 16))) w3 of
            MkIORes d w4 =>
              let v = rotl (prim__xor_Bits32 (prim__xor_Bits32 a b) (prim__xor_Bits32 c d)) 1 in
              case step (setBits32 ws (4 * t) v) w4 of
                MkIORes () w5 => schedule msg off ws (assert_smaller t (t + 1)) w5

-- The round function and constant of round `t`, applied.
roundF : Int -> Bits32 -> Bits32 -> Bits32 -> Bits32
roundF t b c d =
  if t < 20 then prim__add_Bits32
                   (prim__or_Bits32 (prim__and_Bits32 b c)
                                    (prim__and_Bits32 (prim__xor_Bits32 b 0xFFFFFFFF) d))
                   0x5A827999
  else if t < 40 then prim__add_Bits32 (prim__xor_Bits32 b (prim__xor_Bits32 c d)) 0x6ED9EBA1
  else if t < 60 then prim__add_Bits32
                        (prim__or_Bits32 (prim__or_Bits32 (prim__and_Bits32 b c)
                                                          (prim__and_Bits32 b d))
                                         (prim__and_Bits32 c d))
                        0x8F1BBCDC
  else prim__add_Bits32 (prim__xor_Bits32 b (prim__xor_Bits32 c d)) 0xCA62C1D6

-- The 80 rounds over the schedule, then add the working variables to the
-- state in `h` (five native-order words).
rounds : Buffer -> Buffer -> Int ->
         Bits32 -> Bits32 -> Bits32 -> Bits32 -> Bits32 ->
         (1 w : %World) -> IORes ()
rounds ws h t a b c d e w =
  if t >= 80
    then case step (getBits32 h 0) w of
      MkIORes h0 w1 => case step (setBits32 h 0 (h0 + a)) w1 of
       MkIORes () w2 => case step (getBits32 h 4) w2 of
        MkIORes h1 w3 => case step (setBits32 h 4 (h1 + b)) w3 of
         MkIORes () w4 => case step (getBits32 h 8) w4 of
          MkIORes h2 w5 => case step (setBits32 h 8 (h2 + c)) w5 of
           MkIORes () w6 => case step (getBits32 h 12) w6 of
            MkIORes h3 w7 => case step (setBits32 h 12 (h3 + d)) w7 of
             MkIORes () w8 => case step (getBits32 h 16) w8 of
              MkIORes h4 w9 => step (setBits32 h 16 (h4 + e)) w9
    else case step (getBits32 ws (4 * t)) w of
      MkIORes wt w1 =>
        let tmp = rotl a 5 + roundF t b c d + e + wt in
        rounds ws h (assert_smaller t (t + 1)) tmp a (rotl b 30) c d w1

-- Process the blocks at offsets `off`, `off + 64`, ... below `end`.
blocks : Buffer -> Buffer -> Buffer -> Int -> Int -> (1 w : %World) -> IORes ()
blocks msg ws h off end w =
  if off >= end then MkIORes () w
  else case schedule msg off ws 0 w of
    MkIORes () w1 => case step (getBits32 h 0) w1 of
     MkIORes a w2 => case step (getBits32 h 4) w2 of
      MkIORes b w3 => case step (getBits32 h 8) w3 of
       MkIORes c w4 => case step (getBits32 h 12) w4 of
        MkIORes d w5 => case step (getBits32 h 16) w5 of
         MkIORes e w6 => case rounds ws h 0 a b c d e w6 of
          MkIORes () w7 => blocks msg ws h (assert_smaller off (off + 64)) end w7

-- Fill `n` bytes from `from` with zero.
zeros : Buffer -> Int -> Int -> (1 w : %World) -> IORes ()
zeros b from n w =
  if n <= 0 then MkIORes () w
  else case step (setBits8 b from 0) w of
         MkIORes () w1 => zeros b (from + 1) (assert_smaller n (n - 1)) w1

-- Allocate a buffer or stop: a pure function cannot report it.
alloc : Int -> IO Buffer
alloc n = do
  Just b <- newBuffer n
    | Nothing => assert_total (idris_crash "Network.HTTP.SHA1: out of memory")
  pure b

--------------------------------------------------------------------------
-- The digest
--------------------------------------------------------------------------

||| The SHA-1 digest of a byte string: 20 bytes.  Linear in the length.
|||
||| Not for security use (see the module header): it is here for the
||| WebSocket handshake only.
export
sha1 : ByteString -> ByteString
sha1 bs = unsafePerformIO $ do
  let n = lengthInt bs
      -- The message, a 0x80 byte, zeros, and the 64-bit length in bits,
      -- rounded up to a multiple of 64 bytes.
      total_ = (assert_total (prim__div_Int (n + 8) 64) + 1) * 64
  msg <- alloc total_
  unsafeCopyTo bs msg 0
  setBits8 msg n 0x80
  fromPrim (zeros msg (n + 1) (total_ - n - 9))
  let bits = n * 8
  fromPrim (writeBE32 msg (total_ - 8) (cast (prim__shr_Int bits 32)))
  fromPrim (writeBE32 msg (total_ - 4) (cast (prim__and_Int bits 0xFFFFFFFF)))
  ws <- alloc 320
  h <- alloc 20
  setBits32 h 0 0x67452301
  setBits32 h 4 0xEFCDAB89
  setBits32 h 8 0x98BADCFE
  setBits32 h 12 0x10325476
  setBits32 h 16 0xC3D2E1F0
  fromPrim (blocks msg ws h 0 total_)
  pure $ unsafeCreate 20 $ \out => do
    h0 <- getBits32 h 0
    h1 <- getBits32 h 4
    h2 <- getBits32 h 8
    h3 <- getBits32 h 12
    h4 <- getBits32 h 16
    fromPrim (writeBE32 out 0 h0)
    fromPrim (writeBE32 out 4 h1)
    fromPrim (writeBE32 out 8 h2)
    fromPrim (writeBE32 out 12 h3)
    fromPrim (writeBE32 out 16 h4)
