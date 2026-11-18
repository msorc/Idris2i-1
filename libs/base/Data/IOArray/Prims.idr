module Data.IOArray.Prims

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
