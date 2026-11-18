||| Efficient construction of a `ByteString` from many small pieces.
|||
||| A `Builder` knows how many bytes it will produce, so `toByteString`
||| allocates the result once and writes each piece in place: the cost is
||| linear in the size of the result plus the number of pieces, however the
||| `<+>` are nested.  (Appending byte strings with `Data.ByteString.append`
||| in a loop copies the accumulated bytes every time and is quadratic.)
|||
||| ```idris
||| import Data.ByteString
||| import Data.ByteString.Builder as B
|||
||| record : ByteString
||| record = toByteString (word16BE 0xCAFE <+> word32LE 7 <+> utf8String "ok")
||| ```
module Data.ByteString.Builder

import Data.Bits
import Data.Buffer
import Data.ByteString
import Data.ByteString.Internal
import Data.String

%default total

||| A recipe for a byte string.  `Builder` is a `Monoid`: `<+>` puts the
||| output of one piece after that of another, in constant time.
export
data Builder : Type where
  -- Nothing.
  Done : Builder
  -- `Piece n write`: `n` bytes, which `write buffer offset` writes at the
  -- offset (and only there).
  Piece : (size : Int) -> (write : Buffer -> Int -> IO ()) -> Builder
  -- `Join size nodes a b`: `a` then `b`, with the total size and the number
  -- of nodes (including this one), which bounds the work of writing it.
  Join : (size : Int) -> (nodes : Nat) -> Builder -> Builder -> Builder

sizeOf : Builder -> Int
sizeOf Done = 0
sizeOf (Piece n _) = n
sizeOf (Join n _ _ _) = n

nodesOf : Builder -> Nat
nodesOf Done = 1
nodesOf (Piece _ _) = 1
nodesOf (Join _ k _ _) = k

||| The number of bytes that the builder produces.  Constant time.
export
length : Builder -> Nat
length b = cast (sizeOf b)

||| The builder that produces nothing.
export
empty : Builder
empty = Done

-- Concatenation.  Joins are kept as a tree, which `toByteString` walks with
-- an explicit work list, so that a left-nested or right-nested chain of
-- millions of pieces does not use the stack.
append : Builder -> Builder -> Builder
append Done y = y
append x Done = x
append x y = Join (sizeOf x + sizeOf y) (S (nodesOf x + nodesOf y)) x y

||| `<+>` puts the output of the second after that of the first.  Constant
||| time.
export
Semigroup Builder where
  (<+>) = append

||| `neutral` is `empty`.
export
Monoid Builder where
  neutral = Done

-- Write the pieces of a work list, in order, from an offset.  The fuel is
-- the number of nodes: every step takes one off the list, and puts back the
-- two parts of a `Join`, so there are no more steps than nodes.  The world
-- token is passed by hand so that the recursive calls are tail calls on every
-- backend (see `ioForRange` in `Data.ByteString.Internal`).
run : Nat -> Buffer -> Int -> List Builder -> (1 w : %World) -> IORes ()
run Z _ _ _ w = MkIORes () w
run (S k) _ _ [] w = MkIORes () w
run (S k) buf at (Done :: rest) w = run k buf at rest w
run (S k) buf at (Piece n write :: rest) w =
  case toPrim (write buf at) w of
       MkIORes () w' => run k buf (at + n) rest w'
run (S k) buf at (Join _ _ a b :: rest) w = run k buf at (a :: b :: rest) w

||| Build the byte string.  Linear in its size and the number of pieces; the
||| result is allocated once.
export
toByteString : Builder -> ByteString
toByteString b = unsafeCreate (sizeOf b) (\buf => fromPrim (run (nodesOf b) buf 0 [b]))

------------------------------------------------------------------------
-- Pieces
------------------------------------------------------------------------

||| One byte.
export
word8 : Bits8 -> Builder
word8 w = Piece 1 (\buf, at => setBits8 buf at w)

-- A signed value as the 64 bits whose low bytes are its two's complement.
-- (through `Integer`: the `Int` of the JavaScript backends has fewer than 64 bits.)
signed : Integer -> Bits64
signed i = cast i

||| A signed byte (in two's complement).
export
int8 : Int8 -> Builder
int8 v = word8 (cast (signed (cast v)))

-- The `w` low bytes of a value, the least significant first.
putLE : Nat -> Bits64 -> Buffer -> Int -> IO ()
putLE Z _ _ _ = pure ()
putLE (S k) v buf at = do setBits8 buf at (cast v)
                          putLE k (shiftR v 8) buf (at + 1)

-- The `w` low bytes of a value, the most significant first: the least
-- significant is written last, at the highest offset.
putBE : Nat -> Bits64 -> Buffer -> Int -> IO ()
putBE w v buf at = go w v (at + cast w - 1)
  where
    go : Nat -> Bits64 -> Int -> IO ()
    go Z _ _ = pure ()
    go (S k) x pos = do setBits8 buf pos (cast x)
                        go k (shiftR x 8) (pos - 1)

||| Two bytes, the least significant first.
export
word16LE : Bits16 -> Builder
word16LE v = Piece 2 (putLE 2 (cast v))

||| Two bytes, the most significant first.
export
word16BE : Bits16 -> Builder
word16BE v = Piece 2 (putBE 2 (cast v))

||| Four bytes, the least significant first.
export
word32LE : Bits32 -> Builder
word32LE v = Piece 4 (putLE 4 (cast v))

||| Four bytes, the most significant first.
export
word32BE : Bits32 -> Builder
word32BE v = Piece 4 (putBE 4 (cast v))

||| Eight bytes, the least significant first.
export
word64LE : Bits64 -> Builder
word64LE v = Piece 8 (putLE 8 v)

||| Eight bytes, the most significant first.
export
word64BE : Bits64 -> Builder
word64BE v = Piece 8 (putBE 8 v)

||| Two bytes of a signed number (two's complement), the least significant
||| first.
export
int16LE : Int16 -> Builder
int16LE v = Piece 2 (putLE 2 (signed (cast v)))

||| Two bytes of a signed number (two's complement), the most significant
||| first.
export
int16BE : Int16 -> Builder
int16BE v = Piece 2 (putBE 2 (signed (cast v)))

||| Four bytes of a signed number (two's complement), the least significant
||| first.
export
int32LE : Int32 -> Builder
int32LE v = Piece 4 (putLE 4 (signed (cast v)))

||| Four bytes of a signed number (two's complement), the most significant
||| first.
export
int32BE : Int32 -> Builder
int32BE v = Piece 4 (putBE 4 (signed (cast v)))

||| Eight bytes of a signed number (two's complement), the least significant
||| first.
export
int64LE : Int64 -> Builder
int64LE v = Piece 8 (putLE 8 (signed (cast v)))

||| Eight bytes of a signed number (two's complement), the most significant
||| first.
export
int64BE : Int64 -> Builder
int64BE v = Piece 8 (putBE 8 (signed (cast v)))

||| The bytes of a byte string, which are copied when the result is built
||| (not when the builder is made).
export
byteString : ByteString -> Builder
byteString bs = if Data.ByteString.null bs then Done
                else Piece (lengthInt bs) (\buf, at => unsafeCopyTo bs buf at)

||| The bytes of a list.  Linear in the length of the list.
export
bytes : List Bits8 -> Builder
bytes = byteString . Data.ByteString.pack

||| `n` copies of a byte.
export
replicate : Nat -> Bits8 -> Builder
replicate n w = byteString (Data.ByteString.replicate n w)

||| The UTF-8 encoding of a string (see `Data.ByteString.fromString`).
export
utf8String : String -> Builder
utf8String s = byteString (Data.ByteString.fromString s)

||| The UTF-8 encoding of a character.
export
utf8Char : Char -> Builder
utf8Char c = utf8String (Data.String.singleton c)

||| Literals of type `Builder` are the UTF-8 encoding of the literal.
export
FromString Builder where
  fromString = utf8String
