||| Mutable arrays in IO.
|||
||| An `IOArray elem` has a fixed number of slots, each empty or holding an
||| element.  Reading and writing check the index, and are cheap: at `IO` (and
||| at any known implementation of `HasIO`) they compile to the primitive
||| array operations, with no closure or dictionary in between.  Copying a
||| range of elements (`copyArrayRange`, `newArrayCopy`) is done by the back
||| end, in a few instructions per element.
module Data.IOArray

import Data.IOArray.Prims
import public Data.IOArray.Flat

%default total

export
record IOArray elem where
  constructor MkIOArray
  maxSize : Int
  content : ArrayData (Maybe elem)

||| The number of slots of the array.
export %inline
max : IOArray elem -> Int
max = maxSize

-- The actions at `IO`.  The `HasIO` functions below lift them, with `%spec`
-- so that a call at a known implementation gets a copy that calls them
-- directly, and `%inline` so that they are inlined there.  (A copy is
-- elaborated in the calling module, which does not see Data.IOArray.Prims:
-- this is why the primitives are called only here.)

%inline
inBounds : IOArray elem -> Int -> Bool
inBounds arr pos = pos >= 0 && pos < maxSize arr

-- The slots of an array are laid out by a `Flat` of the elements (see
-- Data.IOArray.Flat): that of values, unless the array is made by
-- `newFlatArray`.  Every function reads and writes an array with any
-- layout (the array has it), with the inline accesses where it gives the
-- array's layout (`readFlatArray`, `writeFlatArray` with the elements'
-- `Flat`).

%inline
values : Layout elem
values = flatLayout @{boxedFlat}

%inline
newIO : Flat elem => Int -> IO (IOArray elem)
newIO size
    = do let size' = if size < 0 then 0 else size
         c <- fromPrim (prim__newSlots flatLayout size' Nothing)
         pure (MkIOArray size' c)

%inline
writeIO : Flat elem => IOArray elem -> Int -> elem -> IO Bool
writeIO arr pos el
    = if inBounds arr pos
         then do fromPrim (prim__slotSet flatLayout (content arr) pos (Just el))
                 pure True
         else pure False

%inline
readIO : Flat elem => IOArray elem -> Int -> IO (Maybe elem)
readIO arr pos
    = if inBounds arr pos
         then fromPrim (prim__slotGet flatLayout (content arr) pos)
         else pure Nothing

-- Is [pos, pos + len) a range of the array?  (Without overflow: `len` is at
-- most the size, which is at most the largest Int.)
%inline
rangeIn : IOArray elem -> Int -> Int -> Bool
rangeIn arr pos len = pos >= 0 && len >= 0 && len <= maxSize arr - pos

%inline
copyRangeIO : IOArray elem -> Int -> IOArray elem -> Int -> Int -> IO Bool
copyRangeIO src srcPos dst dstPos len
    = if rangeIn src srcPos len && rangeIn dst dstPos len
         then do fromPrim (prim__arrayCopy (content src) srcPos
                                           (content dst) dstPos len)
                 pure True
         else pure False

newCopyIO : Int -> IOArray elem -> IO (IOArray elem)
newCopyIO newsize arr
    = do let newsize' = if newsize < max arr then max arr else newsize
         arr' <- newIO @{boxedFlat} newsize'
         fromPrim (prim__arrayCopy (content arr) 0 (content arr') 0 (max arr))
         pure arr'

||| A new array with the given number of slots, all empty (none if the number
||| is negative).
%spec hio
%inline
export
newArray : {auto hio : HasIO io} -> Int -> io (IOArray elem)
newArray size = liftIO (newIO @{boxedFlat} size)

||| Write an element at an index.  Returns whether the index was in bounds;
||| if it was not, the array is unchanged.
%spec hio
%inline
export
writeArray : {auto hio : HasIO io} -> IOArray elem -> Int -> elem -> io Bool
writeArray arr pos el = liftIO (writeIO @{boxedFlat} arr pos el)

||| The element at an index, `Nothing` if the slot is empty or the index is
||| out of bounds.
%spec hio
%inline
export
readArray : {auto hio : HasIO io} -> IOArray elem -> Int -> io (Maybe elem)
readArray arr pos = liftIO (readIO @{boxedFlat} arr pos)

||| A new array like `newArray`, whose elements are laid out by their `Flat`
||| (see Data.IOArray.Flat): inline, with the RefC back end, for the
||| primitive numbers and the records of raw fields.  Any function of this
||| module reads and writes it; `readFlatArray` and `writeFlatArray` with the
||| same `Flat` do it inline.
%spec hio
%inline
export
newFlatArray : {auto hio : HasIO io} -> Flat elem => Int -> io (IOArray elem)
newFlatArray size = liftIO (newIO size)

||| `writeArray`, inline when the array was made with this `Flat`.
%spec hio
%inline
export
writeFlatArray : {auto hio : HasIO io} -> Flat elem => IOArray elem -> Int -> elem -> io Bool
writeFlatArray arr pos el = liftIO (writeIO arr pos el)

||| `readArray`, inline when the array was made with this `Flat`.
%spec hio
%inline
export
readFlatArray : {auto hio : HasIO io} -> Flat elem => IOArray elem -> Int -> io (Maybe elem)
readFlatArray arr pos = liftIO (readIO arr pos)

||| Copy `len` slots of `src`, from index `srcPos`, to `dst`, from index
||| `dstPos`, as `memmove` does: the two arrays may be the same and the ranges
||| may overlap.  Empty slots are copied as empty.  Returns whether both ranges
||| were in bounds (and `len` not negative); if not, nothing is copied.
%spec hio
%inline
export
copyArrayRange : {auto hio : HasIO io} ->
                 (src : IOArray elem) -> (srcPos : Int) ->
                 (dst : IOArray elem) -> (dstPos : Int) ->
                 (len : Int) -> io Bool
copyArrayRange src srcPos dst dstPos len
    = liftIO (copyRangeIO src srcPos dst dstPos len)

||| Make a new array of the given size with the elements copied from the
||| other array.  The new array is at least as large as the other one; the
||| slots past its end are empty.
%spec hio
%inline
export
newArrayCopy : {auto hio : HasIO io} ->
               (newsize : Int) -> IOArray elem -> io (IOArray elem)
newArrayCopy newsize arr = liftIO (newCopyIO newsize arr)

toListIO : IOArray elem -> IO (List (Maybe elem))
toListIO arr = iter (max arr - 1) []
  where
    iter : Int -> List (Maybe elem) -> IO (List (Maybe elem))
    iter pos acc
         = if pos < 0
              then pure acc
              else do el <- fromPrim (prim__slotGet values (content arr) pos)
                      iter (assert_smaller pos (pos - 1)) (el :: acc)

||| The slots of the array, in order.
%spec hio
%inline
export
toList : {auto hio : HasIO io} -> IOArray elem -> io (List (Maybe elem))
toList arr = liftIO (toListIO arr)

fromListIO : List (Maybe elem) -> IO (IOArray elem)
fromListIO ns
    = do arr <- newIO @{boxedFlat} (cast (length ns))
         addToArray 0 ns arr
         pure arr
  where
    addToArray : Int -> List (Maybe elem) -> IOArray elem -> IO ()
    addToArray loc [] arr = pure ()
    addToArray loc (Nothing :: ns) arr = addToArray (loc + 1) ns arr
    addToArray loc (Just el :: ns) arr
        = do fromPrim $ prim__slotSet values (content arr) loc (Just el)
             addToArray (loc + 1) ns arr

||| An array with the given slots.
%spec hio
%inline
export
fromList : {auto hio : HasIO io} -> List (Maybe elem) -> io (IOArray elem)
fromList ns = liftIO (fromListIO ns)
