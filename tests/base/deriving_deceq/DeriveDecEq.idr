import Deriving.DecEq
import Data.Nat

%language ElabReflection
%default total

%logging "derive.deceq.clauses" 1

namespace Enum
  public export
  data Enum = A | B | C
  export %hint
  enumDecEq : DecEq Enum
  enumDecEq = %runElab derive

namespace Tree
  public export
  data Tree a = Leaf a | Node (Tree a) a (Tree a)
  public export %hint
  treeDecEq : DecEq a => DecEq (Tree a)
  treeDecEq = %runElab derive

namespace Vect
  public export
  data Vect : Nat -> Type -> Type where
    Nil : Vect Z a
    (::) : a -> Vect n a -> Vect (S n) a
  export %hint
  vectDecEq : DecEq a => DecEq (Vect n a)
  vectDecEq = %runElab derive

namespace Rose
  public export
  data Rose a = MkRose a (List (Rose a))
  export %hint
  roseDecEq : DecEq a => DecEq (Rose a)
  roseDecEq = %runElab derive

namespace Record
  -- a dependent record: the type of the second field depends on the first
  public export
  record Sized where
    constructor MkSized
    size : Nat
    elems : Vect size Bool
  export %hint
  sizedDecEq : DecEq Sized
  sizedDecEq = %runElab derive

namespace Elem
  -- an indexed family: only the pairs of constructors which can build
  -- values of one type get a clause
  public export
  data Ty = TNat | TBool | TList Ty
  public export %hint
  tyDecEq : DecEq Ty
  tyDecEq = %runElab derive

  public export
  data Val : Ty -> Type where
    VNat : Nat -> Val TNat
    VBool : Bool -> Val TBool
    VNil : Val (TList t)
    VCons : Val t -> Val (TList t) -> Val (TList t)
  public export %hint
  valDecEq : DecEq (Val t)
  valDecEq = %runElab derive

namespace Empty
  data Empty : Type where
  emptyDecEq : DecEq Empty
  emptyDecEq = %runElab derive

namespace Erased
  record Bounded where
    constructor MkBounded
    value : Nat
    0 bound : LTE value 10
  failing "has an erased field"
    boundedDecEq : DecEq Bounded
    boundedDecEq = %runElab derive

namespace STree
  data STree : Nat -> Type -> Type where
    Leaf : STree 0 t
    Node : STree l t -> t -> STree r t -> STree (S (l + r)) t
  failing "not made of constructors and variables"
    stDecEq : DecEq t => DecEq (STree n t)
    stDecEq = %runElab derive

-- The derived implementations are total and compute
decide : DecEq a => a -> a -> Bool
decide x y = case decEq x y of
  Yes _ => True
  No _ => False

-- and, when they are public, they reduce at compile time
proof1 : decide (Node (Leaf 1) 2 (Leaf 3)) (Node (Leaf 1) 2 (Leaf 3)) = True
proof1 = Refl

proof2 : decide (VCons (VNat 1) VNil) (VCons (VNat 2) VNil) = False
proof2 = Refl

main : IO ()
main = do
  printLn (decide A A, decide A C)
  printLn (decide (Node (Leaf 1) 2 (Leaf 3)) (Node (Leaf 1) 2 (Leaf 3)),
           decide (Node (Leaf 1) 2 (Leaf 3)) (Leaf 1))
  printLn (decide (the (Vect 2 Nat) [1, 2]) [1, 2], decide (the (Vect 2 Nat) [1, 2]) [2, 2])
  printLn (decide (MkRose 'a' [MkRose 'b' []]) (MkRose 'a' [MkRose 'b' []]),
           decide (MkRose 'a' [MkRose 'b' []]) (MkRose 'a' []))
  printLn (decide (MkSized 2 [True, False]) (MkSized 2 [True, False]),
           decide (MkSized 1 [True]) (MkSized 2 [True, False]))
  printLn (decide (VCons (VBool True) VNil) (VCons (VBool True) VNil),
           decide (VCons (VBool True) VNil) VNil)
  printLn (decide (TList TNat) (TList TNat), decide TNat TBool)
