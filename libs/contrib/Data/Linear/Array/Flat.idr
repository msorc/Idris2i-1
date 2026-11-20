||| Linear arrays whose elements are laid out by their `Flat` (see
||| Data.IOArray.Flat): with the RefC back end and `--directive
||| refc-flat-arrays`, the primitive numbers and the records of one
||| constructor whose fields are all stored raw are inline in the array.
|||
||| The functions are those of Data.Linear.Array, on `FlatArray` and
||| `FlatIArray` instead of `LinArray` and `IArray`, with the same names (but
||| `newFlatArray`, which makes one) and a `Flat` of the elements: a program
||| that uses `LinArray` uses these by importing this module, writing
||| `FlatArray` and `FlatIArray` for `LinArray` and `IArray`, and making its
||| arrays with `newFlatArray` (and `thawFlat`).  Data.Linear.Array and its
||| interfaces are unchanged.
module Data.Linear.Array.Flat

import Data.IOArray
import public Data.IOArray.Flat

%default total

||| A mutable array that only its holder can use (see Data.Linear.Array).
export
data FlatArray : Type -> Type where
     MkFlatArray : IOArray t -> FlatArray t

||| An immutable array.
export
data FlatIArray : Type -> Type where
     MkFlatIArray : IOArray t -> FlatIArray t

-- (see `perform` in Data.Linear.Array: safe, as an operation acts on an
-- array that only the caller holds, or that nobody writes)
%inline
perform : IO a -> a
perform io = case toPrim io %MkWorld of
                  MkIORes res _ => res

||| A new array of the given size, empty, given to the continuation.
-- (not inlined, see `newLinArray`)
%noinline
export
newFlatArray : Flat t => (size : Int) -> (1 _ : (1 _ : FlatArray t) -> a) -> a
newFlatArray size k = k (MkFlatArray (perform (newFlatIO size)))

||| The element at an index, if the slot is in bounds and not empty.
export
mread : Flat t => (1 _ : FlatArray t) -> Int -> Res (Maybe t) (const (FlatArray t))
mread (MkFlatArray a) i = perform (readFlatIO a i) # MkFlatArray a

||| Write an element at an index; the array is unchanged if the index is out
||| of bounds (the result is whether it was in bounds).
export
write : Flat t => (1 _ : FlatArray t) -> Int -> t -> Res Bool (const (FlatArray t))
write (MkFlatArray a) i el
    = perform (writeFlatIO a i el) # MkFlatArray a

||| The number of slots.
export
msize : (1 _ : FlatArray t) -> Res Int (const (FlatArray t))
msize (MkFlatArray a) = max a # MkFlatArray a

||| Copy `len` elements of the first array, from `srcPos`, to the second
||| one, from `dstPos` (see `mcopy` of Data.Linear.Array).
export
mcopy : (1 _ : FlatArray t) -> (srcPos : Int) -> (1 _ : FlatArray t) -> (dstPos : Int) ->
        (len : Int) -> Res Bool (const (LPair (FlatArray t) (FlatArray t)))
mcopy (MkFlatArray src) srcPos (MkFlatArray dst) dstPos len
    = perform (do ok <- copyArrayRange src srcPos dst dstPos len
                  pure (ok # (MkFlatArray src # MkFlatArray dst)))

||| The array, from now on immutable, given to the continuation.
export
toIArray : (1 _ : FlatArray t) -> (FlatIArray t -> a) -> a
toIArray (MkFlatArray arr) k = k (MkFlatIArray arr)

||| The element at an index of an immutable array.
export
read : Flat t => FlatIArray t -> Int -> Maybe t
read (MkFlatIArray a) i = perform (readFlatIO a i)

||| The number of slots of an immutable array.
export
size : FlatIArray t -> Int
size (MkFlatIArray a) = max a

||| A new array of the given size with the first elements of an immutable
||| array (as many as fit), given to the continuation.
export
thawFlat : Flat t => FlatIArray t -> (newsize : Int) -> (1 _ : (1 _ : FlatArray t) -> a) -> a
thawFlat (MkFlatIArray src) newsize k
    = Flat.newFlatArray newsize $ \(MkFlatArray a) =>
        let len = if newsize < max src then (if newsize < 0 then 0 else newsize) else max src
            -- (the copy is made before the array is given on: its result is
            -- matched, as in Data.Linear.Array)
            (_ # a') = perform (do ok <- copyArrayRange src 0 a 0 len
                                   pure (ok # MkFlatArray a)) in
            k a'
