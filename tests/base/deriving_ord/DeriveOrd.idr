import Deriving.Eq
import Deriving.Ord
import Data.Nat

%language ElabReflection
%default total

%logging "derive.ord.clauses" 1

namespace Enum
  public export
  data Enum = A | B | C
  export %hint
  enumEq : Eq Enum
  enumEq = %runElab derive
  export %hint
  enumOrd : Ord Enum
  enumOrd = %runElab derive
  export
  Show Enum where
    show A = "A"
    show B = "B"
    show C = "C"

namespace Tree
  public export
  data Tree a = Leaf a | Node (Tree a) a (Tree a)
  export %hint
  treeEq : Eq a => Eq (Tree a)
  treeEq = %runElab derive
  export %hint
  treeOrd : Ord a => Ord (Tree a)
  treeOrd = %runElab derive

namespace Vect
  public export
  data Vect : Nat -> Type -> Type where
    Nil : Vect Z a
    (::) : a -> Vect n a -> Vect (S n) a
  export %hint
  vectEq : Eq a => Eq (Vect n a)
  vectEq = %runElab derive
  export %hint
  vectOrd : Ord a => Ord (Vect n a)
  vectOrd = %runElab derive

namespace Rose
  public export
  data Rose a = MkRose a (List (Rose a))
  export %hint
  roseEq : Eq a => Eq (Rose a)
  roseEq = %runElab derive
  export %hint
  roseOrd : Ord a => Ord (Rose a)
  roseOrd = %runElab derive

namespace Version
  -- a record, compared field by field; the erased field is not compared
  public export
  record Version where
    constructor MkVersion
    major : Nat
    minor : Nat
    label : String
    0 valid : LTE minor 100
  export %hint
  versionEq : Eq Version
  versionEq = %runElab derive
  export %hint
  versionOrd : Ord Version
  versionOrd = %runElab derive

namespace Elem
  public export
  data El : Bool -> Type where
    ElNat : Nat -> El True
    ElStr : String -> El False
    ElAny : Int -> El b
  export %hint
  elEq : Eq (El b)
  elEq = %runElab derive
  export %hint
  elOrd : Ord (El b)
  elOrd = %runElab derive

namespace NoEq
  data T = MkT Nat
  failing "Can't find an implementation for Eq T"
    tOrd : Ord T
    tOrd = %runElab derive

printList : Show a => List a -> IO ()
printList = printLn

main : IO ()
main = do
  printList [compare A B, compare C B, compare B B]
  printLn (max A C)
  printList (sortEnum [C, A, B, A])
  printList [ compare (Leaf 1) (Node (Leaf 0) 0 (Leaf 0))
          , compare (Node (Leaf 1) 2 (Leaf 3)) (Node (Leaf 1) 2 (Leaf 4))
          , compare (Node (Leaf 2) 0 (Leaf 0)) (Node (Leaf 1) 9 (Leaf 9)) ]
  printLn (Leaf 3 <= Leaf 3)
  printList [compare (the (Vect 2 Nat) [1, 2]) [1, 3], compare (the (Vect 2 Nat) [2, 0]) [1, 3]]
  printLn (compare (MkRose 1 [MkRose 2 []]) (MkRose 1 []))
  printLn (MkRose 1 [] < MkRose 1 [MkRose 0 []])
  let v1 = MkVersion 1 2 "a" (lteAddRight 2)
  let v2 = MkVersion 1 10 "a" (lteAddRight 10)
  let v3 = MkVersion 1 2 "b" (lteAddRight 2)
  printList [compare v1 v2, compare v2 v1, compare v1 v3]
  printList [v1 == v1, v1 > v3]
  printLn (compare (ElNat 1) (ElAny 0))
  printLn (compare (ElAny {b = True} 5) (ElAny 2))
  printLn (compare (ElStr "a") (ElStr "a"))
  where
    insert : Enum -> List Enum -> List Enum
    insert y [] = [y]
    insert y (z :: zs) = if y <= z then y :: z :: zs else z :: insert y zs

    sortEnum : List Enum -> List Enum
    sortEnum Nil = Nil
    sortEnum (x :: xs) = insert x (sortEnum xs)
