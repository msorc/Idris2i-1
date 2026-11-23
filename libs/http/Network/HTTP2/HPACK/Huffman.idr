||| The Huffman code of HPACK (RFC 7541 section 5.2 and appendix B).
|||
||| The code is canonical: the codes of one length are consecutive numbers
||| in the order of the symbols, and each length starts where the previous
||| one ended, shifted left by one bit.  So the table of appendix B is fully
||| described by the bit length of each of the 257 symbols (the 256 byte
||| values and EOS), which is all this module writes down; the codes are
||| computed from it once, and so is the decoding table.
|||
||| Decoding is table driven: the state is an internal node of the code
||| tree (256 of them), and for each state and each 4-bit nibble of input a
||| 32-bit entry of a precomputed table gives the next state, the symbol
||| emitted (at most one, since the shortest code has 5 bits), whether the
||| nibble ran into EOS (an error), and whether the input may end in that
||| state (the bits since the last symbol are a prefix of EOS, that is all
||| ones, and fewer than 8).
module Network.HTTP2.HPACK.Huffman

import Data.Bits
import Data.Buffer
import Data.ByteString
import Data.ByteString.Internal
import Data.IORef
import Network.HTTP2.Internal

%default total

--------------------------------------------------------------------------
-- The code
--------------------------------------------------------------------------

-- The bit length of the code of each symbol 0..256 (256 is EOS), from the
-- table of RFC 7541 appendix B.
codeLengthList : List Bits8
codeLengthList =
  [ 13, 23, 28, 28, 28, 28, 28, 28, 28, 24, 30, 28, 28, 30, 28, 28   --   0
  , 28, 28, 28, 28, 28, 28, 30, 28, 28, 28, 28, 28, 28, 28, 28, 28   --  16
  ,  6, 10, 10, 12, 13,  6,  8, 11, 10, 10,  8, 11,  8,  6,  6,  6   --  32
  ,  5,  5,  5,  6,  6,  6,  6,  6,  6,  6,  7,  8, 15,  6, 12, 10   --  48
  , 13,  6,  7,  7,  7,  7,  7,  7,  7,  7,  7,  7,  7,  7,  7,  7   --  64
  ,  7,  7,  7,  7,  7,  7,  7,  7,  8,  7,  8, 13, 19, 13, 14,  6   --  80
  , 15,  5,  6,  5,  6,  5,  6,  6,  6,  5,  7,  7,  6,  6,  6,  5   --  96
  ,  6,  7,  6,  5,  5,  6,  7,  7,  7,  7,  7, 15, 11, 14, 13, 28   -- 112
  , 20, 22, 20, 20, 22, 22, 22, 23, 22, 23, 23, 23, 23, 23, 24, 23   -- 128
  , 24, 24, 22, 23, 24, 23, 23, 23, 23, 21, 22, 23, 22, 23, 23, 24   -- 144
  , 22, 21, 20, 22, 22, 23, 23, 21, 23, 22, 22, 24, 21, 22, 23, 23   -- 160
  , 21, 21, 22, 21, 23, 22, 23, 23, 20, 22, 22, 22, 23, 22, 22, 23   -- 176
  , 26, 26, 20, 19, 22, 23, 22, 25, 26, 26, 26, 27, 27, 26, 24, 25   -- 192
  , 19, 21, 26, 27, 27, 26, 27, 24, 21, 21, 26, 26, 28, 27, 27, 27   -- 208
  , 20, 24, 20, 21, 22, 21, 21, 23, 22, 22, 25, 25, 24, 24, 26, 23   -- 224
  , 26, 27, 26, 26, 27, 27, 27, 27, 27, 28, 27, 27, 27, 27, 27, 26   -- 240
  , 30                                                               -- 256
  ]

-- The lengths as a constant table of 257 bytes.
codeLengths : ByteString
codeLengths = pack codeLengthList

-- The canonical codes, as 257 little-endian 32-bit words.
codes : ByteString
codes = unsafeCreate (257 * 4) $ \buf => do
  next <- newIORef (the Bits32 0)
  ioForRange 1 30 $ \len => do
    ioForRange 0 257 $ \sym =>
      when (cast (unsafeIndex codeLengths sym) == len) $ do
        c <- readIORef next
        setBits32 buf (sym * 4) c
        writeIORef next (c + 1)
    modifyIORef next (\c => prim__shl_Bits32 c 1)

||| The bit length of the code of a symbol (0..255, or 256 for EOS).
||| Precondition: the symbol is in range.
export %inline
codeLength : Int -> Int
codeLength sym = cast (unsafeIndex codeLengths sym)

||| The code of a symbol (0..255, or 256 for EOS), in the low `codeLength`
||| bits.  Precondition: the symbol is in range.
export %inline
code : Int -> Bits32
code sym = unsafeIndexWord32LE codes (sym * 4)

||| The sum of 2^-length over the codes, times 2^30.  It is exactly 2^30
||| for a complete prefix code (a check of the table of lengths).
export
kraftSum : Integer
kraftSum = go 0 0
  where
    go : Int -> Integer -> Integer
    go sym acc = if sym > 256 then acc
                 else go (assert_smaller sym (sym + 1))
                         (acc + cast (prim__shl_Int 1 (30 - codeLength sym)))

--------------------------------------------------------------------------
-- Decoding table
--------------------------------------------------------------------------

-- Children of the internal nodes while the tree is built: 2 words per node,
-- a node number (< 256), 0xFFFF for none, or 0x10000 + symbol for a leaf.
-- `ones` is the depth of a node whose path from the root is all ones, or
-- 255.
buildTable : Buffer -> IO ()
buildTable out = do
  Just kids <- newBuffer (256 * 2 * 4)
    | Nothing => pure ()
  Just ones <- newBuffer 256
    | Nothing => pure ()
  ioForRange 0 512 $ \i => setBits32 kids (i * 4) 0xFFFF
  ioForRange 0 256 $ \i => setBits8 ones i 255
  setBits8 ones 0 0
  count <- newIORef (the Int 1)
  -- Insert every code.
  ioForRange 0 257 $ \sym => do
    let len = codeLength sym
        c = code sym
    node <- newIORef (the Int 0)
    ioForRange 1 (len - 1) $ \k => do
      -- bit `len - k` of the code, from the most significant one
      let bit = cast {to = Int} (prim__and_Bits32 (prim__shr_Bits32 c (cast (len - k))) 1)
      n <- readIORef node
      child <- getBits32 kids ((n * 2 + bit) * 4)
      if child == 0xFFFF
         then do m <- readIORef count
                 writeIORef count (m + 1)
                 setBits32 kids ((n * 2 + bit) * 4) (cast m)
                 d <- getBits8 ones n
                 setBits8 ones m (if bit == 1 && d /= 255 then d + 1 else 255)
                 writeIORef node m
         else writeIORef node (cast child)
    n <- readIORef node
    let lastBit = cast {to = Int} (prim__and_Bits32 c 1)
    setBits32 kids ((n * 2 + lastBit) * 4) (0x10000 + cast sym)
  -- The transitions.
  ioForRange 0 256 $ \state =>
    ioForRange 0 16 $ \nibble => do
      node <- newIORef state
      sym <- newIORef (the Int (-1))
      failed <- newIORef False
      ioForRange 0 4 $ \k => do
        let bit = prim__and_Int (prim__shr_Int nibble (3 - k)) 1
        n <- readIORef node
        child <- getBits32 kids ((n * 2 + bit) * 4)
        if child >= 0x10000
           then do let s = cast {to = Int} child - 0x10000
                   if s == 256 then writeIORef failed True else writeIORef sym s
                   writeIORef node 0
           else writeIORef node (cast child)
      n <- readIORef node
      s <- readIORef sym
      f <- readIORef failed
      d <- getBits8 ones n
      let accept = n == 0 || d <= 7
          entry = cast {to = Bits32} n
                  .|. (if s >= 0 then prim__shl_Bits32 (cast s) 8 .|. 0x10000 else 0)
                  .|. (if f then 0x20000 else 0)
                  .|. (if accept then 0x40000 else 0)
      setBits32 out ((state * 16 + nibble) * 4) entry

-- 256 states x 16 nibbles of 32-bit entries: bits 0..7 the next state,
-- 8..15 the symbol, 16 a symbol is emitted, 17 EOS was decoded (an error),
-- 18 the input may end in the next state.
decodeTable : ByteString
decodeTable = unsafeCreate (256 * 16 * 4) buildTable

--------------------------------------------------------------------------
-- Decoding
--------------------------------------------------------------------------

-- The entry for a state and a nibble, from the buffer of `decodeTable`.
%inline
entry : Buffer -> Bits32 -> Bits8 -> Bits32
entry tbl state nibble =
  unsafeBufferWord32LE tbl (cast (prim__or_Bits32 (prim__shl_Bits32 state 4) (cast nibble)) * 4)

-- 1 if a table entry emits a symbol, else 0.
%inline
emits : Bits32 -> Int
emits e = cast (prim__and_Bits32 (prim__shr_Bits32 e 16) 1)

-- Decode the bytes [i, end) of the buffer `inp` from `state`, writing at
-- `at`; the result is the number of bytes written or -1.  `tbl` is the
-- buffer of `decodeTable` (whose offset is 0).  The byte of each nibble
-- is written whether or not the nibble ends a symbol (the position only
-- moves on when it does), which keeps the loop free of branches on it: a
-- position is at most the number of symbols so far, which is below the
-- size of the output buffer.
decodeLoop : (tbl : Buffer) -> (inp : Buffer) -> (out : Buffer) -> (i : Int) -> (end : Int) ->
             (state : Bits32) -> (accept : Bool) -> (at : Int) -> (1 w : %World) -> IORes Int
decodeLoop tbl inp out i end state accept at w =
  if i >= end
     then MkIORes (if accept then at else -1) w
     else
       let b = unsafeBufferByte inp i
           e1 = entry tbl state (prim__shr_Bits8 b 4)
       in if prim__and_Bits32 e1 0x20000 /= 0 then MkIORes (-1) w else
          case wset8 out at (cast (prim__shr_Bits32 e1 8)) w of
            MkIORes () w1 =>
              let at1 = at + emits e1
                  e2 = entry tbl (prim__and_Bits32 e1 0xFF) (prim__and_Bits8 b 15)
              in if prim__and_Bits32 e2 0x20000 /= 0 then MkIORes (-1) w1 else
                 case wset8 out at1 (cast (prim__shr_Bits32 e2 8)) w1 of
                   MkIORes () w2 =>
                     decodeLoop tbl inp out (assert_smaller i (i + 1)) end
                                (prim__and_Bits32 e2 0xFF)
                                (prim__and_Bits32 e2 0x40000 /= 0) (at1 + emits e2) w2

||| Decode a Huffman-coded string.  `Nothing` if it contains EOS, or ends
||| with padding that is longer than 7 bits or is not all ones (RFC 7541
||| section 5.2).  Linear in the length, with one allocation.
export
huffmanDecode : ByteString -> Maybe ByteString
huffmanDecode bs =
  let n = lengthInt bs in
  if n == 0 then Just bs
  else let o = unsafeOffset bs in
       createUpTo (assert_total (prim__div_Int (n * 8) 5) + 1)
                  (\buf => decodeLoop (unsafeBuffer decodeTable) (unsafeBuffer bs) buf o (o + n) 0 True 0)

--------------------------------------------------------------------------
-- Encoding
--------------------------------------------------------------------------

||| The number of bytes of the Huffman coding of a string (with padding).
export
huffmanLength : ByteString -> Int
huffmanLength bs = go 0 0
  where
    go : Int -> Int -> Int
    go i bits = if i >= lengthInt bs then prim__shr_Int (bits + 7) 3
                else go (assert_smaller i (i + 1))
                        (bits + codeLength (cast (unsafeIndex bs i)))

-- Write the codes of bs[i..] with `pending` bits (fewer than 8, in the low
-- bits of `acc`) not yet written, at `at`.
encodeLoop : ByteString -> Buffer -> (i : Int) -> (acc : Bits64) -> (pending : Int) ->
             (at : Int) -> (1 w : %World) -> IORes ()
encodeLoop bs out i acc pending at w =
  if i >= lengthInt bs
     then if pending > 0
             then -- pad with the most significant bits of EOS (all ones)
                  wset8 out at (cast (prim__or_Bits64 (prim__shl_Bits64 acc (cast (8 - pending)))
                                                       (prim__shr_Bits64 0xFF (cast pending)))) w
             else MkIORes () w
     else
       let sym = cast {to = Int} (unsafeIndex bs i)
           len = codeLength sym
           acc' = prim__or_Bits64 (prim__shl_Bits64 acc (cast len)) (cast (code sym))
       in flush acc' (pending + len) at w
  where
    flush : Bits64 -> Int -> Int -> (1 w : %World) -> IORes ()
    flush a p pos w0 =
      if p >= 8
         then case wset8 out pos (cast (prim__shr_Bits64 a (cast (p - 8)))) w0 of
                MkIORes () w1 => flush a (assert_smaller p (p - 8)) (pos + 1) w1
         else encodeLoop bs out (assert_smaller i (i + 1))
                         (prim__and_Bits64 a (prim__shl_Bits64 1 (cast p) - 1)) p pos w0

||| The Huffman coding of a string (RFC 7541 section 5.2), padded with the
||| most significant bits of EOS.
export
huffmanEncode : ByteString -> ByteString
huffmanEncode bs =
  unsafeCreate (huffmanLength bs) (\buf => fromPrim (encodeLoop bs buf 0 0 0 0))
