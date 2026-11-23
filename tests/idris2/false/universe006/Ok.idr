||| Matching on types which does not lower a universe is accepted
module Ok

%default total

data Bool = False | True

data Seq : Type -> Type where
  Nil : Seq a
  Cons : a -> Seq a -> Seq a

isSeq : Type -> Bool
isSeq (Seq _) = True
isSeq _ = False

elemOf : Type -> Type
elemOf (Seq a) = a
elemOf t = t

elemSeq : elemOf (Seq Bool)
elemSeq = True
