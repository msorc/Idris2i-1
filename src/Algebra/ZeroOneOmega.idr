module Algebra.ZeroOneOmega

import Algebra.Semiring
import Algebra.Preorder



%default total

||| A rigid quantity variable (experimental, see
||| docs/source/implementation/quantity-variables.rst).  It ranges over 1 and
||| omega, never 0.  It belongs to the definition whose type signature binds
||| it (`owner`, its full name, or "" while it is only parsed), so that the
||| variables of two definitions are never the same.
public export
record QuantityVar where
  constructor MkQuantityVar
  qvOwner : String
  qvName : String

export
Eq QuantityVar where
  MkQuantityVar o n == MkQuantityVar o' n' = n == n' && o == o'

export
Ord QuantityVar where
  compare (MkQuantityVar o n) (MkQuantityVar o' n') = compare (n, o) (n', o')

export
Show QuantityVar where
  show v = "%" ++ qvName v

||| 0, 1, omega, or the product of a non-empty set of quantity variables,
||| kept sorted and without duplicates (so that equal products are equal
||| lists).  A product is 1 if all of its variables are 1, and omega
||| otherwise.  Every operation below is exact: a judgement about these
||| values holds if and only if it holds for every choice of 1 or omega for
||| the variables.
export
data ZeroOneOmega = Rig0 | Rig1 | RigW | RigV (List QuantityVar)

%name ZeroOneOmega rig

-- The varUnion of two sorted lists without duplicates
varUnion : List QuantityVar -> List QuantityVar -> List QuantityVar
varUnion [] ys = ys
varUnion xs [] = xs
varUnion (x :: xs) (y :: ys)
    = case compare x y of
           LT => x :: varUnion xs (y :: ys)
           EQ => x :: varUnion xs ys
           GT => y :: varUnion (x :: xs) ys

-- The intersection of two sorted lists without duplicates
varIntersect : List QuantityVar -> List QuantityVar -> List QuantityVar
varIntersect [] ys = []
varIntersect xs [] = []
varIntersect (x :: xs) (y :: ys)
    = case compare x y of
           LT => varIntersect xs (y :: ys)
           EQ => x :: varIntersect xs ys
           GT => varIntersect (x :: xs) ys

-- Is the first sorted list included in the second?
varSubset : List QuantityVar -> List QuantityVar -> Bool
varSubset [] ys = True
varSubset (x :: xs) [] = False
varSubset (x :: xs) (y :: ys)
    = case compare x y of
           LT => False
           EQ => varSubset xs ys
           GT => varSubset (x :: xs) ys

-- 1 for no variable
product : List QuantityVar -> ZeroOneOmega
product [] = Rig1
product vs = RigV vs

||| The order: 0 <= x, x <= omega, 1 <= product, and a product is below
||| another if its variables are among the other's (a product is omega if
||| any of its variables is).  This is the pointwise order over all
||| choices of 1 or omega for the variables, so it is partial: 1 and a
||| product are not above each other, nor two products of different
||| variables.
|||
||| The proofs of reflexivity and transitivity are by evaluation for 0, 1
||| and omega.  For products they are postulated: they need the
||| reflexivity and transitivity of `compare` on `String`, a primitive,
||| which can't be proved here.
export
Preorder ZeroOneOmega where
  Rig0 <= _ = True
  _ <= RigW = True
  Rig1 <= Rig1 = True
  Rig1 <= RigV _ = True
  RigV xs <= RigV ys = varSubset xs ys
  _ <= _ = False
  preorderRefl {x = Rig0} = Refl
  preorderRefl {x = Rig1} = Refl
  preorderRefl {x = RigW} = Refl
  preorderRefl {x = RigV xs} = believe_me (Refl {x = True})
  preorderTrans {x = Rig0} _ _ = Refl
  preorderTrans {x = Rig1} {y = Rig0} _ _ impossible
  preorderTrans {x = Rig1} {y = Rig1} _ yz = yz
  preorderTrans {x = Rig1} {y = RigW} {z = Rig0} _ _ impossible
  preorderTrans {x = Rig1} {y = RigW} {z = Rig1} _ _ impossible
  preorderTrans {x = Rig1} {y = RigW} {z = RigW} _ _ = Refl
  preorderTrans {x = Rig1} {y = RigW} {z = RigV _} _ _ impossible
  preorderTrans {x = Rig1} {y = RigV _} {z = Rig0} _ _ impossible
  preorderTrans {x = Rig1} {y = RigV _} {z = Rig1} _ _ impossible
  preorderTrans {x = Rig1} {y = RigV _} {z = RigW} _ _ = Refl
  preorderTrans {x = Rig1} {y = RigV _} {z = RigV _} _ _ = Refl
  preorderTrans {x = RigW} {y = Rig0} _ _ impossible
  preorderTrans {x = RigW} {y = Rig1} _ _ impossible
  preorderTrans {x = RigW} {y = RigW} _ yz = yz
  preorderTrans {x = RigW} {y = RigV _} _ _ impossible
  preorderTrans {x = RigV xs} {y = Rig0} _ _ impossible
  preorderTrans {x = RigV xs} {y = Rig1} _ _ impossible
  preorderTrans {x = RigV xs} {y = RigW} {z = Rig0} _ _ impossible
  preorderTrans {x = RigV xs} {y = RigW} {z = Rig1} _ _ impossible
  preorderTrans {x = RigV xs} {y = RigW} {z = RigW} _ _ = Refl
  preorderTrans {x = RigV xs} {y = RigW} {z = RigV _} _ _ impossible
  preorderTrans {x = RigV xs} {y = RigV ys} {z = Rig0} _ _ impossible
  preorderTrans {x = RigV xs} {y = RigV ys} {z = Rig1} _ _ impossible
  preorderTrans {x = RigV xs} {y = RigV ys} {z = RigW} _ _ = Refl
  preorderTrans {x = RigV xs} {y = RigV ys} {z = RigV zs} xy yz
      = believe_me (Refl {x = True})

public export
Eq ZeroOneOmega where
  (==) Rig0 Rig0 = True
  (==) Rig1 Rig1 = True
  (==) RigW RigW = True
  (==) (RigV xs) (RigV ys) = xs == ys
  (==) _ _ = False

export
Show ZeroOneOmega where
  show Rig0 = "Rig0"
  show Rig1 = "Rig1"
  show RigW = "RigW"
  show (RigV vs) = "RigV " ++ show vs

export
rigPlus : ZeroOneOmega -> ZeroOneOmega -> ZeroOneOmega
rigPlus Rig0 a = a
rigPlus a Rig0 = a
rigPlus _ _ = RigW

export
rigMult : ZeroOneOmega -> ZeroOneOmega -> ZeroOneOmega
rigMult Rig0 _ = Rig0
rigMult _ Rig0 = Rig0
rigMult Rig1 a = a
rigMult a Rig1 = a
rigMult (RigV xs) (RigV ys) = RigV (varUnion xs ys)
rigMult _ _ = RigW


public export
Semiring ZeroOneOmega where
  (|+|) = rigPlus
  (|*|) = rigMult
  plusNeutral = Rig0
  timesNeutral = Rig1

||| The top value of a lattice
export
Top ZeroOneOmega where
  top = RigW
  topAbs {x = Rig0} = Refl
  topAbs {x = Rig1} = Refl
  topAbs {x = RigW} = Refl
  topAbs {x = RigV _} = Refl

||| The greatest lower bound in the order above (`glb` of `Preorder` is
||| wrong for values that are not ordered)
export
rigMeet : ZeroOneOmega -> ZeroOneOmega -> ZeroOneOmega
rigMeet Rig0 _ = Rig0
rigMeet _ Rig0 = Rig0
rigMeet RigW y = y
rigMeet x RigW = x
rigMeet Rig1 _ = Rig1
rigMeet _ Rig1 = Rig1
rigMeet (RigV xs) (RigV ys) = product (varIntersect xs ys)

||| The least upper bound in the order above (`lub` of `Preorder` is wrong
||| for values that are not ordered)
export
rigJoin : ZeroOneOmega -> ZeroOneOmega -> ZeroOneOmega
rigJoin Rig0 y = y
rigJoin x Rig0 = x
rigJoin RigW _ = RigW
rigJoin _ RigW = RigW
rigJoin Rig1 y = y
rigJoin x Rig1 = x
rigJoin (RigV xs) (RigV ys) = RigV (varUnion xs ys)

||| A quantity variable as a quantity
export
rigVar : QuantityVar -> ZeroOneOmega
rigVar v = RigV [v]

||| The variables of a quantity (none for 0, 1 and omega)
export
rigVars : ZeroOneOmega -> List QuantityVar
rigVars (RigV vs) = vs
rigVars _ = []

||| Is it a product of variables?
export
isRigVar : ZeroOneOmega -> Bool
isRigVar (RigV _) = True
isRigVar _ = False

||| A variable that must be used exactly once: bound at 1, or at a product
||| of variables (each of which may be 1).  Not the same as `isOne`: a
||| variable bound at a product of variables is counted like a linear one,
||| but it is not linear, and linearity can't be given to it.
export
isCounted : ZeroOneOmega -> Bool
isCounted Rig1 = True
isCounted (RigV _) = True
isCounted _ = False

||| Replace the variables that the function knows (the product of what they
||| become; the others stay)
export
substRig : (QuantityVar -> Maybe ZeroOneOmega) -> ZeroOneOmega -> ZeroOneOmega
substRig f (RigV vs) = foldl (\acc, v => rigMult acc (maybe (rigVar v) id (f v))) Rig1 vs
substRig f r = r

||| For serialisation: 0, 1, omega, or the variables
public export
data RigView = ViewZero | ViewOne | ViewOmega | ViewVars (List QuantityVar)

export
rigView : ZeroOneOmega -> RigView
rigView Rig0 = ViewZero
rigView Rig1 = ViewOne
rigView RigW = ViewOmega
rigView (RigV vs) = ViewVars vs

||| The product of the given variables (sorted here), 1 for none
export
rigVarsProduct : List QuantityVar -> ZeroOneOmega
rigVarsProduct vs = product (foldl (\acc, v => varUnion acc [v]) [] vs)

----------------------------------------
-- The laws of addition hold for all values.  Those of multiplication are
-- proved for 0, 1 and omega only: for products they need the laws of
-- `varUnion`, which need those of `compare` on `String`.

rigPlusAssociative : (x, y, z : ZeroOneOmega) ->
  rigPlus x (rigPlus y z) = rigPlus (rigPlus x y) z
rigPlusAssociative Rig0 Rig0 Rig0 = Refl
rigPlusAssociative Rig0 Rig0 Rig1 = Refl
rigPlusAssociative Rig0 Rig0 RigW = Refl
rigPlusAssociative Rig0 Rig0 (RigV zs) = Refl
rigPlusAssociative Rig0 Rig1 Rig0 = Refl
rigPlusAssociative Rig0 Rig1 Rig1 = Refl
rigPlusAssociative Rig0 Rig1 RigW = Refl
rigPlusAssociative Rig0 Rig1 (RigV zs) = Refl
rigPlusAssociative Rig0 RigW Rig0 = Refl
rigPlusAssociative Rig0 RigW Rig1 = Refl
rigPlusAssociative Rig0 RigW RigW = Refl
rigPlusAssociative Rig0 RigW (RigV zs) = Refl
rigPlusAssociative Rig0 (RigV ys) Rig0 = Refl
rigPlusAssociative Rig0 (RigV ys) Rig1 = Refl
rigPlusAssociative Rig0 (RigV ys) RigW = Refl
rigPlusAssociative Rig0 (RigV ys) (RigV zs) = Refl
rigPlusAssociative Rig1 Rig0 Rig0 = Refl
rigPlusAssociative Rig1 Rig0 Rig1 = Refl
rigPlusAssociative Rig1 Rig0 RigW = Refl
rigPlusAssociative Rig1 Rig0 (RigV zs) = Refl
rigPlusAssociative Rig1 Rig1 Rig0 = Refl
rigPlusAssociative Rig1 Rig1 Rig1 = Refl
rigPlusAssociative Rig1 Rig1 RigW = Refl
rigPlusAssociative Rig1 Rig1 (RigV zs) = Refl
rigPlusAssociative Rig1 RigW Rig0 = Refl
rigPlusAssociative Rig1 RigW Rig1 = Refl
rigPlusAssociative Rig1 RigW RigW = Refl
rigPlusAssociative Rig1 RigW (RigV zs) = Refl
rigPlusAssociative Rig1 (RigV ys) Rig0 = Refl
rigPlusAssociative Rig1 (RigV ys) Rig1 = Refl
rigPlusAssociative Rig1 (RigV ys) RigW = Refl
rigPlusAssociative Rig1 (RigV ys) (RigV zs) = Refl
rigPlusAssociative RigW Rig0 Rig0 = Refl
rigPlusAssociative RigW Rig0 Rig1 = Refl
rigPlusAssociative RigW Rig0 RigW = Refl
rigPlusAssociative RigW Rig0 (RigV zs) = Refl
rigPlusAssociative RigW Rig1 Rig0 = Refl
rigPlusAssociative RigW Rig1 Rig1 = Refl
rigPlusAssociative RigW Rig1 RigW = Refl
rigPlusAssociative RigW Rig1 (RigV zs) = Refl
rigPlusAssociative RigW RigW Rig0 = Refl
rigPlusAssociative RigW RigW Rig1 = Refl
rigPlusAssociative RigW RigW RigW = Refl
rigPlusAssociative RigW RigW (RigV zs) = Refl
rigPlusAssociative RigW (RigV ys) Rig0 = Refl
rigPlusAssociative RigW (RigV ys) Rig1 = Refl
rigPlusAssociative RigW (RigV ys) RigW = Refl
rigPlusAssociative RigW (RigV ys) (RigV zs) = Refl
rigPlusAssociative (RigV xs) Rig0 Rig0 = Refl
rigPlusAssociative (RigV xs) Rig0 Rig1 = Refl
rigPlusAssociative (RigV xs) Rig0 RigW = Refl
rigPlusAssociative (RigV xs) Rig0 (RigV zs) = Refl
rigPlusAssociative (RigV xs) Rig1 Rig0 = Refl
rigPlusAssociative (RigV xs) Rig1 Rig1 = Refl
rigPlusAssociative (RigV xs) Rig1 RigW = Refl
rigPlusAssociative (RigV xs) Rig1 (RigV zs) = Refl
rigPlusAssociative (RigV xs) RigW Rig0 = Refl
rigPlusAssociative (RigV xs) RigW Rig1 = Refl
rigPlusAssociative (RigV xs) RigW RigW = Refl
rigPlusAssociative (RigV xs) RigW (RigV zs) = Refl
rigPlusAssociative (RigV xs) (RigV ys) Rig0 = Refl
rigPlusAssociative (RigV xs) (RigV ys) Rig1 = Refl
rigPlusAssociative (RigV xs) (RigV ys) RigW = Refl
rigPlusAssociative (RigV xs) (RigV ys) (RigV zs) = Refl

rigPlusCommutative : (x, y : ZeroOneOmega) ->
  rigPlus x y = rigPlus y x
rigPlusCommutative Rig0 Rig0 = Refl
rigPlusCommutative Rig0 Rig1 = Refl
rigPlusCommutative Rig0 RigW = Refl
rigPlusCommutative Rig0 (RigV ys) = Refl
rigPlusCommutative Rig1 Rig0 = Refl
rigPlusCommutative Rig1 Rig1 = Refl
rigPlusCommutative Rig1 RigW = Refl
rigPlusCommutative Rig1 (RigV ys) = Refl
rigPlusCommutative RigW Rig0 = Refl
rigPlusCommutative RigW Rig1 = Refl
rigPlusCommutative RigW RigW = Refl
rigPlusCommutative RigW (RigV ys) = Refl
rigPlusCommutative (RigV xs) Rig0 = Refl
rigPlusCommutative (RigV xs) Rig1 = Refl
rigPlusCommutative (RigV xs) RigW = Refl
rigPlusCommutative (RigV xs) (RigV ys) = Refl

data Concrete : ZeroOneOmega -> Type where
  C0 : Concrete Rig0
  C1 : Concrete Rig1
  CW : Concrete RigW

rigMultAssociative : (x, y, z : ZeroOneOmega) ->
  Concrete x -> Concrete y -> Concrete z ->
  rigMult x (rigMult y z) = rigMult (rigMult x y) z
rigMultAssociative Rig0 Rig0 Rig0 C0 C0 C0 = Refl
rigMultAssociative Rig0 Rig0 Rig1 C0 C0 C1 = Refl
rigMultAssociative Rig0 Rig0 RigW C0 C0 CW = Refl
rigMultAssociative Rig0 Rig1 Rig0 C0 C1 C0 = Refl
rigMultAssociative Rig0 Rig1 Rig1 C0 C1 C1 = Refl
rigMultAssociative Rig0 Rig1 RigW C0 C1 CW = Refl
rigMultAssociative Rig0 RigW Rig0 C0 CW C0 = Refl
rigMultAssociative Rig0 RigW Rig1 C0 CW C1 = Refl
rigMultAssociative Rig0 RigW RigW C0 CW CW = Refl
rigMultAssociative Rig1 Rig0 Rig0 C1 C0 C0 = Refl
rigMultAssociative Rig1 Rig0 Rig1 C1 C0 C1 = Refl
rigMultAssociative Rig1 Rig0 RigW C1 C0 CW = Refl
rigMultAssociative Rig1 Rig1 Rig0 C1 C1 C0 = Refl
rigMultAssociative Rig1 Rig1 Rig1 C1 C1 C1 = Refl
rigMultAssociative Rig1 Rig1 RigW C1 C1 CW = Refl
rigMultAssociative Rig1 RigW Rig0 C1 CW C0 = Refl
rigMultAssociative Rig1 RigW Rig1 C1 CW C1 = Refl
rigMultAssociative Rig1 RigW RigW C1 CW CW = Refl
rigMultAssociative RigW Rig0 Rig0 CW C0 C0 = Refl
rigMultAssociative RigW Rig0 Rig1 CW C0 C1 = Refl
rigMultAssociative RigW Rig0 RigW CW C0 CW = Refl
rigMultAssociative RigW Rig1 Rig0 CW C1 C0 = Refl
rigMultAssociative RigW Rig1 Rig1 CW C1 C1 = Refl
rigMultAssociative RigW Rig1 RigW CW C1 CW = Refl
rigMultAssociative RigW RigW Rig0 CW CW C0 = Refl
rigMultAssociative RigW RigW Rig1 CW CW C1 = Refl
rigMultAssociative RigW RigW RigW CW CW CW = Refl

rigMultCommutative : (x, y : ZeroOneOmega) -> Concrete x -> Concrete y ->
  rigMult x y = rigMult y x
rigMultCommutative Rig0 Rig0 C0 C0 = Refl
rigMultCommutative Rig0 Rig1 C0 C1 = Refl
rigMultCommutative Rig0 RigW C0 CW = Refl
rigMultCommutative Rig1 Rig0 C1 C0 = Refl
rigMultCommutative Rig1 Rig1 C1 C1 = Refl
rigMultCommutative Rig1 RigW C1 CW = Refl
rigMultCommutative RigW Rig0 CW C0 = Refl
rigMultCommutative RigW Rig1 CW C1 = Refl
rigMultCommutative RigW RigW CW CW = Refl
