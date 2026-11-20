||| A stand-in for Data.Linear.Array under the stage B design: the methods
||| that make, read and write an array take the descriptor of the element
||| layout as an auto implicit.
module FlatArr

import public Data.Linear

export
data Layout : Type -> Type where
  LBoxed : Layout a
  LRec : String -> Layout a

%defaulthint
export
boxedLayout : Layout a
boxedLayout = LBoxed

||| Stands for the hint the compiler would generate for a flat record.
export
recordLayout : String -> Layout a
recordLayout = LRec

export
data ArrayData : Type -> Type where [external]

%extern prim__flatNew : Layout t -> Int -> PrimIO (ArrayData t)
%extern prim__flatGet : Layout t -> ArrayData t -> Int -> PrimIO (Maybe t)
%extern prim__flatSet : Layout t -> ArrayData t -> Int -> t -> PrimIO ()

public export
interface MArr (arr : Type -> Type) where
  newA : {auto l : Layout t} -> Int -> (1 _ : (1 _ : arr t) -> a) -> a
  mread : {auto l : Layout t} -> (1 _ : arr t) -> Int -> Res (Maybe t) (const (arr t))
  write : {auto l : Layout t} -> (1 _ : arr t) -> Int -> t -> Res Bool (const (arr t))

export
data LinA : Type -> Type where
  MkLinA : Int -> ArrayData t -> LinA t

%inline
newLin : {auto l : Layout t} -> Int -> (1 _ : (1 _ : LinA t) -> a) -> a
newLin n k = k (MkLinA n (unsafePerformIO (fromPrim (prim__flatNew l n))))

%inline
mreadLin : {auto l : Layout t} -> (1 _ : LinA t) -> Int -> Res (Maybe t) (const (LinA t))
mreadLin (MkLinA n a) i
    = if i >= 0 && i < n
         then unsafePerformIO (fromPrim (prim__flatGet l a i)) # MkLinA n a
         else Nothing # MkLinA n a

%inline
writeLin : {auto l : Layout t} -> (1 _ : LinA t) -> Int -> t -> Res Bool (const (LinA t))
writeLin (MkLinA n a) i x
    = if i >= 0 && i < n
         then unsafePerformIO (fromPrim (prim__flatSet l a i x) >> pure True) # MkLinA n a
         else False # MkLinA n a

export
MArr LinA where
  newA = newLin
  mread = mreadLin
  write = writeLin

export
done : (1 _ : LinA t) -> IO ()
done (MkLinA _ _) = pure ()
