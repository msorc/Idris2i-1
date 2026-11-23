||| Matching on a type takes out a type of the universe of the type matched,
||| not of the universe of the pattern's own copy of the type constructor:
||| otherwise `T` below would be a `Type` in its own universe.
module ElemOf

%default total

data Unit = MkUnit

data Seq : Type -> Type where
  Nil : Seq a
  Cons : a -> Seq a -> Seq a

elemOf : Type -> Type
elemOf (Seq a) = a
elemOf _ = Unit

T : Type
T = elemOf (Seq Type)

selfT : T
selfT = T
