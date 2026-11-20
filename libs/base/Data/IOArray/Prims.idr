module Data.IOArray.Prims

import public Data.IOArray.Flat

%default total

export
data ArrayData : Type -> Type where [external]

-- 'unsafe' primitive access, backend dependent
-- get and set assume that the bounds have been checked. Behaviour is undefined
-- otherwise.
export %extern prim__newArray : forall a . Int -> a -> PrimIO (ArrayData a)
export %extern prim__arrayGet : forall a . ArrayData a -> Int -> PrimIO a
export %extern prim__arraySet : forall a . ArrayData a -> Int -> a -> PrimIO ()

||| Copy `len` elements of the first array, from index `srcPos`, to the second
||| one, from index `dstPos`.  The arrays may be the same and the ranges may
||| overlap (the elements are copied as if through a temporary array).
||| This assumes that both ranges are in bounds and that `len` is not
||| negative; behaviour is undefined otherwise.
%foreign "scheme:blodwen-array-copy"
         "RefC:idris2_arrayCopy"
         "javascript:lambda:(_,src,sp,dst,dp,n)=>{sp=Number(sp);dp=Number(dp);n=Number(n);if(src===dst){src.copyWithin(dp,sp,sp+n)}else{for(let i=0;i<n;i++){dst[dp+i]=src[sp+i]}}}"
export
prim__arrayCopy : forall a . ArrayData a -> (srcPos : Int) ->
                  ArrayData a -> (dstPos : Int) -> (len : Int) -> PrimIO ()


-- The arrays of the slots of an `IOArray`, which hold `Maybe a`, by the
-- layout of `a` (see Data.IOArray.Flat): the RefC back end stores the
-- elements inline when the layout is not that of values, with a word that
-- tells whether the slot is empty.  The layout is the one that the caller
-- expects; the array's own one decides, so an array is read and written
-- correctly whatever layout the caller has (the default one, in code that is
-- generic in the type of the elements, say), only slower when they differ.
-- The other back ends ignore the layout: these are `prim__newArray`,
-- `prim__arrayGet` and `prim__arraySet`.
export %extern prim__newSlots : forall a . Layout a -> Int -> Maybe a -> PrimIO (ArrayData (Maybe a))
export %extern prim__slotGet : forall a . Layout a -> ArrayData (Maybe a) -> Int -> PrimIO (Maybe a)
export %extern prim__slotSet : forall a . Layout a -> ArrayData (Maybe a) -> Int -> Maybe a -> PrimIO ()
