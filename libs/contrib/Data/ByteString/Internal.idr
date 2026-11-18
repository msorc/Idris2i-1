||| The representation of `ByteString` and the small unsafe core that the rest
||| of the `Data.ByteString` modules is written on.
|||
||| Most programs should import `Data.ByteString`, which re-exports the type
||| from here.  The functions named `unsafe...` below exist so that
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

import Data.Buffer

%default total

||| An immutable sequence of bytes: a slice of a buffer that is never written
||| after it has been filled.  Slicing (`take`, `drop`, `splitAt`...) takes
||| constant time and shares the buffer; `Data.ByteString.copy` makes a
||| slice that owns its bytes.
export
data ByteString : Type where
  BS : (buf : Buffer) -> (off : Int) -> (len : Int) -> ByteString

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
lengthInt (BS _ _ n) = n

||| The underlying buffer.  It must be treated as read only, and it is
||| bigger than the byte string if the latter is a slice.
export %inline
unsafeBuffer : ByteString -> Buffer
unsafeBuffer (BS b _ _) = b

||| Where the bytes start in `unsafeBuffer`.
export %inline
unsafeOffset : ByteString -> Int
unsafeOffset (BS _ o _) = o

||| The byte at an index.  Precondition: `0 <= i < lengthInt bs`; the index
||| is not checked (RefC aborts and the other backends read what is there or
||| raise an error if it is not met).
|||
||| Safe to use in a pure function because the bytes are never written
||| after creation (see the module header).
export
unsafeIndex : ByteString -> Int -> Bits8
unsafeIndex (BS b o _) i = unsafePerformIO (getBits8 b (o + i))

||| The slice `[start, start + n)` of a byte string, sharing its buffer.
||| Precondition: `0 <= start`, `0 <= n` and `start + n <= lengthInt bs`.
export
unsafeSlice : (start : Int) -> (n : Int) -> ByteString -> ByteString
unsafeSlice start n (BS b o _) = BS b (o + start) n

||| Copy the bytes of a byte string into a buffer at an offset.
||| Precondition: the destination has room for them.  The destination must
||| be a buffer that is being filled by `unsafeCreate` or `createIO` (it is
||| the only kind that anyone may write).
export
unsafeCopyTo : ByteString -> (dst : Buffer) -> (dstOffset : Int) -> IO ()
unsafeCopyTo (BS b o n) dst at = copyData b o n dst at

||| Make a byte string of `n` bytes by running a function that fills a fresh
||| zeroed buffer of that size.  A size of 0 or less gives the empty byte
||| string without running the function.
|||
||| The function must write the buffer only within `[0, n)`, must not keep
||| a reference to it (a later write would change the byte string) and must
||| write the same bytes whenever it is run.
export
unsafeCreate : (n : Int) -> (fill : Buffer -> IO ()) -> ByteString
unsafeCreate n fill =
  if n <= 0
     then unsafePerformIO (do b <- emptyBuffer; pure (BS b 0 0))
     else unsafePerformIO $ do
            b <- fresh n
            fill b
            pure (BS b 0 n)
  where
    -- `newBuffer` only fails for a negative size, which `n > 0` excludes.
    fresh : Int -> IO Buffer
    fresh k = do Just b <- newBuffer k
                   | Nothing => emptyBuffer
                 pure b

||| Like `unsafeCreate`, for an action in any `HasIO` monad that tells how
||| many of the `n` bytes it wrote (from the start), or fails with an error:
||| the byte string is just those bytes.  The same rules apply: the action
||| must not keep the buffer.  If it reports more than `n` or less than 0,
||| the result is clamped to that range.  Used to read from files.
export
createIO : HasIO io => (n : Int) -> (fill : Buffer -> io (Either e Int)) ->
           io (Either e ByteString)
createIO n fill =
  if n <= 0
     then do b <- emptyBuffer
             pure (Right (BS b 0 0))
     else do Just b <- newBuffer n
               | Nothing => do e <- emptyBuffer
                               pure (Right (BS e 0 0))
             Right used <- fill b
               | Left err => pure (Left err)
             pure (Right (BS b 0 (if used < 0 then 0 else if used > n then n else used)))
