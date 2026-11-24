||| The representation of `ByteString` and the small unsafe core that the rest
||| of the `Data.ByteString` modules is written on.
|||
||| Most programs should import `Data.ByteString`, which re-exports the type
||| from `Data.ByteString.Types` and not the functions of this module.  The
||| functions named `unsafe...` below exist so that
||| `Data.ByteString.Builder` and `System.File.ByteString` can construct byte
||| strings; they are safe if used as documented, but the compiler cannot check
||| that.
|||
||| # Why a pure interface over a mutable buffer is sound
|||
||| A `ByteString` is a slice `(buffer, offset, length)` of a `Data.Buffer`,
||| which is a mutable object.  The only operations of this module that create
||| a `ByteString` are `unsafeCreate` and `createIO`, and each of them
|||
|||  1. allocates a fresh buffer that nothing else refers to,
|||  2. runs a function that fills it, during which the buffer is not yet
|||     visible as a `ByteString`, and
|||  3. returns the slice, and never gives the buffer to anyone who could write
|||     to it again: the function of step 2 has returned, and the type of the
|||     `ByteString` has no operation that writes.
|||
||| So from the moment a `ByteString` exists, the bytes that it can see are
||| never written again, and reading them (`unsafeIndex`, `unsafeCopyTo`) is
||| a pure function of the `ByteString`, which is what `unsafePerformIO` must
||| not be used for if it is not.  Creating one is pure in the same way
||| provided that the filling function writes the same bytes each time it is
||| run and does nothing else observable; the compiler may run it once, or
||| more than once, or never (for a result that is not used).
|||
||| The invariant of a slice is `0 <= offset`, `0 <= length` and
||| `offset + length <= size of the buffer`.  Only `unsafeSlice` and the
||| creating functions build one, and the former has it as a precondition.
module Data.ByteString.Internal

import public Data.ByteString.Types
import Data.Buffer

%default total

--------------------------------------------------------------------------
-- Loops in `IO` that do not grow the stack
--------------------------------------------------------------------------
--
-- A loop written as `do act i; go (i + 1)` in `IO` nests a call for every
-- iteration with the JavaScript backends (which do not make that tail call),
-- so a loop over 100,000 bytes overflowed the stack of Node.  These loops pass
-- the `%World` token by hand, so that the recursive call is a saturated tail
-- call of the function itself, which every backend turns into a jump.

||| Run `act i` for `i` in `[from, from + n)`, in order.  Uses no stack space
||| for the iteration.
export
ioForRange : (from : Int) -> (n : Int) -> (Int -> IO ()) -> IO ()
ioForRange from n act = fromPrim (go (cast n) from)
  where
    go : Nat -> Int -> (1 w : %World) -> IORes ()
    go Z _ w = MkIORes () w
    go (S k) i w = case toPrim (act i) w of
                        MkIORes () w' => go k (i + 1) w'

||| Thread a state through the elements of a list: `act s x` does the work for
||| `x` and gives the state for the next element.  Uses no stack space for
||| the iteration.
export
ioForList : List a -> (start : s) -> (s -> a -> IO s) -> IO ()
ioForList xs start act = fromPrim (go xs start)
  where
    go : List a -> s -> (1 w : %World) -> IORes ()
    go [] _ w = MkIORes () w
    go (x :: rest) st w = case toPrim (act st x) w of
                               MkIORes st' w' => go rest st' w'

--------------------------------------------------------------------------
-- The unsafe core.  Everything else is written with these.
--------------------------------------------------------------------------

||| The length in bytes, as an `Int` (never negative).
export %inline
lengthInt : ByteString -> Int
lengthInt (UnsafeBS _ _ n) = n

||| The underlying buffer.  It must be treated as read only, and it is
||| bigger than the byte string if the latter is a slice.
export %inline
unsafeBuffer : ByteString -> Buffer
unsafeBuffer (UnsafeBS b _ _) = b

||| Where the bytes start in `unsafeBuffer`.
export %inline
unsafeOffset : ByteString -> Int
unsafeOffset (UnsafeBS _ o _) = o

-- The reads of `Data.Buffer`, as pure functions: the buffers of byte
-- strings are not written after they have been filled (see the module
-- header), so reading them is pure, and a pure foreign call is a plain
-- function call (through `unsafePerformIO`, every read made a closure).
%foreign "scheme:blodwen-buffer-getbyte"
         "RefC:getBufferUInt8"
         "node:lambda:(buf,offset)=>buf.readUInt8(offset)"
prim__byteAt : Buffer -> Int -> Bits8

%foreign "scheme:blodwen-buffer-getbits32"
         "RefC:getBufferUInt32LE"
         "node:lambda:(buf,offset)=>buf.readUInt32LE(offset)"
prim__word32At : Buffer -> Int -> Bits32

%foreign "scheme:blodwen-buffer-getstring"
         "RefC:getBufferString"
         "node:lambda:(buf,offset,len)=>buf.slice(offset, offset+len).toString('utf-8')"
prim__stringAt : Buffer -> Int -> Int -> String

-- Operations on ranges of bytes, which replace loops that read one byte at
-- a time: one call of `memcmp`, `memchr` or a C loop with RefC, a Node
-- `Buffer` method with Node, and a loop over the bytes with the Scheme
-- backends (`blodwen-buffer-getbyte` is defined by all of them).
%foreign "scheme:(lambda (a ao b bo n) (let loop ((i 0)) (if (= i n) 0 (let ((x (blodwen-buffer-getbyte a (+ ao i))) (y (blodwen-buffer-getbyte b (+ bo i)))) (cond ((< x y) -1) ((> x y) 1) (else (loop (+ i 1))))))))"
         "RefC:idris2i_1_bufferCompare"
         "node:lambda:(a,ao,b,bo,n)=>a.compare(b,bo,bo+n,ao,ao+n)"
prim__compareRange : Buffer -> Int -> Buffer -> Int -> Int -> Int

%foreign "scheme:(lambda (b o n w) (let loop ((i 0)) (cond ((= i n) -1) ((= (blodwen-buffer-getbyte b (+ o i)) w) i) (else (loop (+ i 1))))))"
         "RefC:idris2i_1_bufferFindByte"
         "node:lambda:(b,o,n,w)=>b.subarray(o,o+n).indexOf(w)"
prim__findByte : Buffer -> Int -> Int -> Bits8 -> Int

-- (with Node, `Int` is a 32-bit number, and `Math.imul` has the low 32 bits
-- of the product, as the `Int` multiplication of Node has)
%foreign "scheme:(lambda (h b o n) (let loop ((i 0) (h h)) (if (= i n) h (loop (+ i 1) (bitwise-and (* (bitwise-xor h (blodwen-buffer-getbyte b (+ o i))) 16777619) 2147483647)))))"
         "RefC:idris2i_1_bufferHashFNV31"
         "node:lambda:(h,b,o,n)=>{for(let i=o;i<o+n;i++){h=Math.imul(h^b[i],16777619)&2147483647;}return h;}"
prim__hashRange : Int -> Buffer -> Int -> Int -> Int

||| The byte at an offset of the buffer of a byte string (an offset in the
||| buffer, not in the slice: see `unsafeBuffer` and `unsafeOffset`).
||| Precondition: the offset is within the buffer (RefC aborts if it is not).
||| For loops that read the buffer directly; `unsafeIndex` is the same for
||| an index in the byte string.
export %inline
unsafeBufferByte : Buffer -> Int -> Bits8
unsafeBufferByte = prim__byteAt

||| The four bytes at an offset of the buffer of a byte string, the first
||| one the least significant (see `unsafeBufferByte`).  Precondition: they
||| are within the buffer.  Reading four bytes at a time lets a loop over
||| bytes take a quarter of the calls (the result is not boxed with RefC).
export %inline
unsafeBufferWord32LE : Buffer -> Int -> Bits32
unsafeBufferWord32LE = prim__word32At

||| The string whose UTF-8 encoding is the `n` bytes of the buffer of a byte
||| string from an offset (see `unsafeBufferByte`).  Precondition: the bytes
||| are within the buffer and are valid UTF-8 (the backends differ in what
||| they do with bytes that are not, see `Data.ByteString.toString`).
||| Linear in `n` (a copy).
export %inline
unsafeBufferString : Buffer -> (offset : Int) -> (n : Int) -> String
unsafeBufferString = prim__stringAt

||| The order of the `n` bytes from `aoff` in the buffer `a` and the `n`
||| bytes from `boff` in `b`, as unsigned bytes: `-1`, `0` or `1`.
||| Precondition: `0 <= n` and both ranges are within their buffers (RefC
||| stops the program if they are not; Chez and Node raise an error).  One
||| `memcmp` with RefC.
export %inline
unsafeCompareRange : (a : Buffer) -> (aoff : Int) -> (b : Buffer) -> (boff : Int) -> (n : Int) -> Int
unsafeCompareRange = prim__compareRange

||| The index, counted from `off`, of the first byte `w` among the `n` bytes
||| from `off` of a buffer, or `-1` if there is none.  Precondition: `0 <= n`
||| and the range is within the buffer (as for `unsafeCompareRange`).  One
||| `memchr` with RefC.
export %inline
unsafeFindByte : (w : Bits8) -> Buffer -> (off : Int) -> (n : Int) -> Int
unsafeFindByte w b off n = prim__findByte b off n w

||| FNV-1a on 31 bits over the `n` bytes from `off` of a buffer, from the
||| state `h`: for each byte, `h` becomes
||| `((h xor byte) * 16777619) mod 2^31`, as `Data.Hashable.fnvStep` does.
||| Precondition: `0 <= n` and the range is within the buffer.
export %inline
unsafeHashRange : (h : Int) -> Buffer -> (off : Int) -> (n : Int) -> Int
unsafeHashRange = prim__hashRange

||| The byte at an index.  Precondition: `0 <= i < lengthInt bs`; the index
||| is not checked (RefC aborts and the other backends read what is there or
||| raise an error if it is not met).
|||
||| Safe to use in a pure function because the bytes are never written
||| after creation (see the module header).
export %inline
unsafeIndex : ByteString -> Int -> Bits8
unsafeIndex (UnsafeBS b o _) i = prim__byteAt b (o + i)

||| The four bytes at an index of a byte string, the first one the least
||| significant.  Precondition: `0 <= i` and `i + 4 <= lengthInt bs` (not
||| checked, as for `unsafeIndex`).
export %inline
unsafeIndexWord32LE : ByteString -> Int -> Bits32
unsafeIndexWord32LE (UnsafeBS b o _) i = prim__word32At b (o + i)

||| The index of the first occurrence of a byte at or after the index
||| `from`, or `-1`.  Any `from` is allowed: a negative one counts as 0.
export
findByteFrom : Bits8 -> (from : Int) -> ByteString -> Int
findByteFrom w from (UnsafeBS b o n) =
  let s = if from < 0 then 0 else from in
  if s >= n then -1
  else let r = prim__findByte b (o + s) (n - s) w in
       if r < 0 then -1 else r + s

||| The order of two byte strings: lexicographic, the bytes as unsigned
||| numbers, a proper prefix before the longer one.
export
compareBytes : ByteString -> ByteString -> Ordering
compareBytes (UnsafeBS a ao an) (UnsafeBS b bo bn) =
  let c = prim__compareRange a ao b bo (if an < bn then an else bn) in
  if c < 0 then LT else if c > 0 then GT else compare an bn

||| Do two byte strings have the same bytes?
export
sameBytes : ByteString -> ByteString -> Bool
sameBytes (UnsafeBS a ao an) (UnsafeBS b bo bn) =
  an == bn && prim__compareRange a ao b bo an == 0

||| Are the `lengthInt pat` bytes of `pat` those of `bs` from the index
||| `at`?  Precondition: `0 <= at` and `at + lengthInt pat <= lengthInt bs`.
export
unsafeMatchesAt : (pat : ByteString) -> (bs : ByteString) -> (at : Int) -> Bool
unsafeMatchesAt (UnsafeBS a ao an) (UnsafeBS b bo _) at =
  prim__compareRange a ao b (bo + at) an == 0

||| The slice `[start, start + n)` of a byte string, sharing its buffer.
||| Precondition: `0 <= start`, `0 <= n` and `start + n <= lengthInt bs`.
export
unsafeSlice : (start : Int) -> (n : Int) -> ByteString -> ByteString
unsafeSlice start n (UnsafeBS b o _) = UnsafeBS b (o + start) n

||| Copy the bytes of a byte string into a buffer at an offset.
||| Precondition: the destination has room for them.  The destination must
||| be a buffer that is being filled by `unsafeCreate` or `createIO` (it is
||| the only kind that anyone may write).
export
unsafeCopyTo : ByteString -> (dst : Buffer) -> (dstOffset : Int) -> IO ()
unsafeCopyTo (UnsafeBS b o n) dst at = copyData b o n dst at

-- A new zeroed buffer, in IO (`Data.Buffer.newBuffer` is polymorphic in
-- `HasIO`, and on RefC a call through the dictionary of `HasIO IO` makes a
-- closure for the action).
%foreign "scheme:blodwen-new-buffer"
         "RefC:newBuffer"
         "node:lambda:s=>Buffer.alloc(s)"
prim__newBufferIO : Int -> PrimIO Buffer

-- Stop the program: a buffer that was asked for could not be allocated.  It
-- has any result type, so that it can be used where a value is expected.
outOfMemory : Int -> a
outOfMemory n = assert_total $ idris_crash
  ("Data.ByteString: out of memory (could not allocate a buffer of " ++ show n ++ " bytes)")

||| Make a byte string of `n` bytes by running a function that fills a fresh
||| zeroed buffer of that size.  A size of 0 or less gives the empty byte
||| string without running the function.
|||
||| The function must write the buffer only within `[0, n)`, must not keep
||| a reference to it (a later write would change the byte string) and must
||| write the same bytes whenever it is run.
|||
||| A pure function has no way to report that the memory is not there: with
||| every back end an allocation that fails stops the program, in its own
||| way, rather than give a byte string that claims bytes it does not have.
export
unsafeCreate : (n : Int) -> (fill : Buffer -> IO ()) -> ByteString
unsafeCreate n fill =
  if n <= 0
     then unsafePerformIO (do b <- emptyBuffer; pure (UnsafeBS b 0 0))
     else unsafePerformIO $ do
            b <- fromPrim (prim__newBufferIO n)
            fill b
            pure (UnsafeBS b 0 n)

||| Like `unsafeCreate`, for an action in any `HasIO` monad that tells how
||| many of the `n` bytes it wrote (from the start), or fails with an error:
||| the byte string is just those bytes.  The same rules apply: the action
||| must not keep the buffer.  If it reports more than `n` or less than 0,
||| the result is clamped to that range.  Used to read from files.
|||
||| The error type `e` is the caller's, so it cannot say that the buffer
||| could not be allocated; the program stops with the message
||| "out of memory" in that case, as `unsafeCreate` does (see there for why it
||| is not expected to happen).
export
createIO : HasIO io => (n : Int) -> (fill : Buffer -> io (Either e Int)) ->
           io (Either e ByteString)
createIO n fill =
  if n <= 0
     then do b <- emptyBuffer
             pure (Right (UnsafeBS b 0 0))
     else do Just b <- newBuffer n
               | Nothing => outOfMemory n
             Right used <- fill b
               | Left err => pure (Left err)
             pure (Right (UnsafeBS b 0 (if used < 0 then 0 else if used > n then n else used)))
