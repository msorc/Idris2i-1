||| A stand-in for Data.Linear.Array under the stage B design: the methods
||| that make, read and write an array take the descriptor of the element
||| layout as an auto implicit.
module FlatArr

import public Data.Linear

export
data Layout : Type -> Type where
  LBoxed : Layout a
  LRec : String -> Layout a

||| The descriptor as an interface, so that --spec-interfaces specialises
||| the functions that take it where it is known.
public export
interface FlatI t where
  constructor MkFlatI
  lay : Layout t

%defaulthint
export
boxedLayout : FlatI a
boxedLayout = MkFlatI LBoxed

export
recordFlat : String -> FlatI a
recordFlat s = MkFlatI (LRec s)

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
  newA : FlatI t => Int -> (1 _ : (1 _ : arr t) -> a) -> a
  mread : FlatI t => (1 _ : arr t) -> Int -> Res (Maybe t) (const (arr t))
  write : FlatI t => (1 _ : arr t) -> Int -> t -> Res Bool (const (arr t))

export
data LinA : Type -> Type where
  MkLinA : Int -> ArrayData t -> LinA t

%inline
newLin : FlatI t => Int -> (1 _ : (1 _ : LinA t) -> a) -> a
newLin n k = k (MkLinA n (unsafePerformIO (fromPrim (prim__flatNew lay n))))

%inline
mreadLin : FlatI t => (1 _ : LinA t) -> Int -> Res (Maybe t) (const (LinA t))
mreadLin (MkLinA n a) i
    = if i >= 0 && i < n
         then unsafePerformIO (fromPrim (prim__flatGet lay a i)) # MkLinA n a
         else Nothing # MkLinA n a

%inline
writeLin : FlatI t => (1 _ : LinA t) -> Int -> t -> Res Bool (const (LinA t))
writeLin (MkLinA n a) i x
    = if i >= 0 && i < n
         then unsafePerformIO (fromPrim (prim__flatSet lay a i x) >> pure True) # MkLinA n a
         else False # MkLinA n a

export
MArr LinA where
  newA = newLin
  mread = mreadLin
  write = writeLin

export
done : (1 _ : LinA t) -> IO ()
done (MkLinA _ _) = pure ()
