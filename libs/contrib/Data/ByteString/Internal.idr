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

||| The byte at an index.  Precondition: `0 <= i < lengthInt bs`; the index
||| is not checked (RefC aborts and the other backends read what is there or
||| raise an error if it is not met).
|||
||| Safe to use in a pure function because the bytes are never written
||| after creation (see the module header).
export
unsafeIndex : ByteString -> Int -> Bits8
unsafeIndex (UnsafeBS b o _) i = unsafePerformIO (getBits8 b (o + i))

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
||| A pure function has no way to report that the memory is not there, so
||| when the buffer cannot be allocated the program stops with the message
||| "out of memory" rather than build a byte string that claims bytes it does
||| not have.  (With every back end an allocation that fails stops the program
||| already, in its own way: `newBuffer` returns `Nothing` only for a negative
||| size, which `n > 0` excludes, so the check below is for the invariant and
||| is not expected to run.)
export
unsafeCreate : (n : Int) -> (fill : Buffer -> IO ()) -> ByteString
unsafeCreate n fill =
  if n <= 0
     then unsafePerformIO (do b <- emptyBuffer; pure (UnsafeBS b 0 0))
     else unsafePerformIO $ do
            Just b <- newBuffer n
              | Nothing => outOfMemory n
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
