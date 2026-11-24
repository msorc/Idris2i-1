import Data.Vect

%default total

-- Taking a type out of a type is fine.
elemTy : Type -> Type
elemTy (List a) = a
elemTy (Vect n a) = a
elemTy (a, b) = b
elemTy t = t

-- So is taking out a value of a small type.
len : Type -> Nat
len (Vect n a) = n
len _ = 0

dom : Type -> Type
dom (a -> b) = a
dom t = t

-- A family over a small type embeds no function over types.
data Tab : (Nat -> Type) -> Type where

fam : Type -> Nat -> Type
fam (Tab f) = f
fam _ = \_ => Unit

row : Type -> Type
row (Nat -> b) = b 3
row t = t

-- Binding a function over types without using it is harmless.
data Fun : (Type -> Type) -> Type where

isFun : Type -> Bool
isFun (Fun f) = True
isFun _ = False

-- A forced type is not matched on.
data Code : Type -> Type where
  CFun : (f : Type -> Type) -> Code (Fun f)

decode : Code t -> Type -> Type
decode (CFun f) = f
