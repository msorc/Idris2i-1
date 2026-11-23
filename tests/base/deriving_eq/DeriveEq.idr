import Deriving.Eq

%language ElabReflection
%default total

%logging "derive.eq.clauses" 1

namespace Enum
  public export
  data Enum = A | B | C
  export %hint
  enumEq : Eq Enum
  enumEq = %runElab derive

namespace Sum
  public export
  data Sum = AString String | ANat Nat
  export %hint
  sumEq : Eq Sum
  sumEq = %runElab derive

namespace Tree
  public export
  data Tree a = Leaf a | Node (Tree a) a (Tree a)
  export %hint
  treeEq : Eq a => Eq (Tree a)
  treeEq = %runElab derive

namespace Vect
  public export
  data Vect : Nat -> Type -> Type where
    Nil : Vect Z a
    (::) : a -> Vect n a -> Vect (S n) a
  export %hint
  vectEq : Eq a => Eq (Vect n a)
  vectEq = %runElab derive

namespace Rose
  public export
  data Rose a = MkRose a (List (Rose a))
  -- the nested occurrence needs the implementation being defined
  export %hint
  roseEq : Eq a => Eq (Rose a)
  roseEq = %runElab derive

namespace Full
  -- a nested type: the recursive field is at another parameter
  public export
  data Full a = FLeaf a | FNode (Full (a, a))
  export %hint
  fullEq : Eq a => Eq (Full a)
  fullEq = %runElab derive

namespace Forest
  public export
  data RTree : Type -> Type
  public export
  data Forest : Type -> Type
  data RTree : Type -> Type where
    RLeaf : a -> RTree a
    RNode : Forest a -> RTree a
  data Forest : Type -> Type where
    None : Forest a
    Plant : RTree a -> Forest a -> Forest a
  export %hint tree : Eq a => Eq (RTree a)
  export %hint forest : Eq a => Eq (Forest a)
  tree = %runElab derive {mutualWith = [`{Forest}]}
  forest = %runElab derive {mutualWith = [`{RTree}]}

namespace Point
  -- a record, with an erased field which is not compared
  public export
  record Point where
    constructor MkPoint
    x : Int
    y : Int
    0 prf : x = x
  export %hint
  pointEq : Eq Point
  pointEq = %runElab derive

namespace Phantom
  -- only the parameters which fields use get a constraint
  public export
  record Tagged (tag : Type) (a : Type) where
    constructor MkTagged
    value : a
  export %hint
  taggedEq : Eq a => Eq (Tagged tag a)
  taggedEq = %runElab derive

namespace Elem
  public export
  data El : Bool -> Type where
    ElNat : Nat -> El True
    ElStr : String -> El False
    ElAny : Int -> El b
  export %hint
  elEq : Eq (El b)
  elEq = %runElab derive

namespace Empty
  data Empty : Type where
  emptyEq : Eq Empty
  emptyEq = %runElab derive

namespace Reducible
  public export
  Y : Bool -> Type
  Y True  = Bool
  Y False = Nat
  public export
  data X : Type where
    X0 : X
    X2 : Y True -> Y False -> X
  export %hint
  xEq : Eq X
  xEq = %runElab derive

namespace STree
  data STree : Nat -> Type -> Type where
    Leaf : STree 0 t
    Node : STree l t -> t -> STree r t -> STree (S (l + r)) t
  failing "not made of constructors and variables"
    stEq : Eq t => Eq (STree n t)
    stEq = %runElab derive

namespace Expr
  data Dir = Write | Read
  data Expr : Dir -> Type where
    Lam : String -> Expr d -> Expr Write
    Val : Int -> Expr d
  failing "implicit argument d, which its type does not determine"
    exprEq : Eq (Expr d)
    exprEq = %runElab derive

main : IO ()
main = do
  printLn (A == A, A == B, ANat 1 == ANat 1, ANat 1 == AString "1")
  printLn (Node (Leaf 1) 2 (Leaf 3) == Node (Leaf 1) 2 (Leaf 3),
           Node (Leaf 1) 2 (Leaf 3) == Node (Leaf 1) 2 (Leaf 4),
           Leaf 1 /= Node (Leaf 1) 1 (Leaf 1))
  printLn (the (Vect 2 Nat) [1, 2] == [1, 2], the (Vect 2 Nat) [1, 2] == [1, 3])
  printLn (MkRose 1 [MkRose 2 []] == MkRose 1 [MkRose 2 []],
           MkRose 1 [MkRose 2 []] == MkRose 1 [])
  printLn (FNode (FNode (FLeaf ((1, 2), (3, 4)))) == FNode (FNode (FLeaf ((1, 2), (3, 4)))),
           FNode (FLeaf (1, 2)) == FNode (FLeaf (1, 3)))
  printLn (RNode (Plant (RLeaf 1) None) == RNode (Plant (RLeaf 1) None),
           Plant (RLeaf 1) None == None)
  printLn (MkPoint 1 2 Refl == MkPoint 1 2 Refl, MkPoint 1 2 Refl == MkPoint 2 1 Refl)
  printLn (MkTagged {tag = Void} 'a' == MkTagged 'a')
  printLn (ElNat 1 == ElNat 1, ElAny {b = True} 1 == ElNat 1, ElStr "a" == ElAny 2)
  printLn (X2 True 1 == X2 True 1, X0 == X2 False 0)
