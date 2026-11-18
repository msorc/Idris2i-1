module Data.Linear.Array

import Data.IOArray

-- Linear arrays. General idea: mutable arrays are constructed linearly,
-- using newArray. Once everything is set up, they can be converted to
-- read only arrays with constant time, pure, access, using toIArray.

-- Immutable arrays which can be read in constant time, but not updated
public export
interface Array arr where
  read : (1 _ : arr t) -> Int -> Maybe t
  size : (1 _ : arr t) -> Int

-- Mutable arrays which can be used linearly
public export
interface Array arr => MArray arr where
  newArray : (size : Int) -> (1 _ : (1 _ : arr t) -> a) -> a
  -- Array is unchanged if the index is out of bounds
  write : (1 _ : arr t) -> Int -> t -> Res Bool (const (arr t))

  mread : (1 _ : arr t) -> Int -> Res (Maybe t) (const (arr t))
  msize : (1 _ : arr t) -> Res Int (const (arr t))

  ||| Copy `len` elements of the first array, from index `srcPos`, to the
  ||| second one, from index `dstPos` (empty slots are copied as empty).
  ||| Returns whether both ranges were in bounds and `len` not negative; if
  ||| not, nothing is copied.  The default copies the elements one by one; an
  ||| implementation can do better (`LinArray` copies them in bulk).
  mcopy : (1 _ : arr t) -> (srcPos : Int) -> (1 _ : arr t) -> (dstPos : Int) ->
          (len : Int) -> Res Bool (const (LPair (arr t) (arr t)))
  mcopy src srcPos dst dstPos len
      = let ssize # src = msize src
            dsize # dst = msize dst in
            if srcPos >= 0 && dstPos >= 0 && len >= 0
                 && len <= ssize - srcPos && len <= dsize - dstPos
               then True # copyElems (len - 1) src dst
               else False # (src # dst)
    where
      copyElems : Int -> (1 _ : arr t) -> (1 _ : arr t) -> LPair (arr t) (arr t)
      copyElems i src dst
          = if i < 0
               then src # dst
               else let val # src = mread src (srcPos + i)
                        1 dst = case val of
                                     Nothing => dst
                                     Just v => let (_ # dst) = write dst (dstPos + i) v in
                                               dst in
                        copyElems (assert_smaller i (i - 1)) src dst

export
data IArray : Type -> Type where
     MkIArray : IOArray t -> IArray t

export
data LinArray : Type -> Type where
     MkLinArray : IOArray t -> LinArray t

-- Run the IO action of an array operation.  This is `unsafePerformIO`,
-- inlined: `unsafePerformIO` itself is not, and its call would cost a
-- closure for the action.  It is safe here because every action operates on
-- one array that only the caller holds (a `LinArray`) or that nobody writes
-- (an `IArray`).
%inline
perform : IO a -> a
perform io = case toPrim io %MkWorld of
                  MkIORes res _ => res

-- (Not inlined: inlined in a caller, the allocation of an array of a
-- constant size would be a closed term, which the common subexpression
-- elimination could share between several arrays.)
%noinline
newLinArray : (size : Int) -> (1 _ : (1 _ : LinArray t) -> a) -> a
newLinArray size k = k (MkLinArray (perform (newArray size)))

-- Convert a mutable array to an immutable array
export
toIArray : (1 _ : LinArray t) -> (IArray t -> a) -> a
toIArray (MkLinArray arr) k = k (MkIArray arr)

export
Array LinArray where
  read (MkLinArray a) i = perform (readArray a i)
  size (MkLinArray a) = max a

export
MArray LinArray where
  newArray = newLinArray

  write (MkLinArray a) i el
      = perform (do ok <- writeArray a i el
                    pure (ok # MkLinArray a))
  msize (MkLinArray a) = max a # MkLinArray a
  mread (MkLinArray a) i
      = perform (readArray a i) # MkLinArray a
  mcopy (MkLinArray src) srcPos (MkLinArray dst) dstPos len
      = perform (do ok <- copyArrayRange src srcPos dst dstPos len
                    pure (ok # (MkLinArray src # MkLinArray dst)))

export
Array IArray where
  read (MkIArray a) i = perform (readArray a i)
  size (MkIArray a) = max a

-- The number of elements copied to a new array of the given size
copied : (newsize : Int) -> (size : Int) -> Int
copied newsize size = if newsize < size then (if newsize < 0 then 0 else newsize) else size

||| Copy an array into a new one of the given size: the result is the array
||| and its copy, which has the first `newsize` elements of the array (or all
||| of them, if it is larger).
export
copyArray : MArray arr => (newsize : Int) -> (1 _ : arr t) ->
            LPair (arr t) (arr t)
copyArray newsize a
    = let size # a = msize a in
          Linear.Array.newArray newsize $ \a' =>
            let (_ # (a # a')) = mcopy a 0 a' 0 (copied newsize size) in
                a # a'

||| Copy `len` elements of an immutable array, from index `srcPos`, to a
||| linear array, from index `dstPos` (empty slots are copied as empty).
||| Returns whether both ranges were in bounds and `len` not negative; if not,
||| nothing is copied.  The elements are copied in bulk, in a few
||| instructions each.
export
copyInto : IArray t -> (srcPos : Int) -> (1 _ : LinArray t) ->
           (dstPos : Int) -> (len : Int) -> Res Bool (const (LinArray t))
copyInto (MkIArray src) srcPos (MkLinArray dst) dstPos len
    = perform (do ok <- copyArrayRange src srcPos dst dstPos len
                  pure (ok # MkLinArray dst))

||| A linear array of the given size whose first elements are those of an
||| immutable array (as many as fit), given to the continuation.  With
||| `copyInto`, `write` and `toIArray`, this makes an updated copy of an
||| immutable array, such as the same array with one element changed.
export
thaw : IArray t -> (newsize : Int) -> (1 _ : (1 _ : LinArray t) -> a) -> a
thaw src newsize k
    = newLinArray newsize $ \a =>
        let (_ # a) = copyInto src 0 a 0 (copied newsize (size src)) in
            k a
