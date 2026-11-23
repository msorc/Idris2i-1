module Check

import Data.Fin
import Data.Nat
import Decidable.Decidable
import Decidable.Equality
import Syntax

%default total

-- Total functions that use each implementation: they check only when the
-- implementations exist and are total.
sameTy : (a, b : Ty) -> Dec (a = b)
sameTy a b = decEq a b

sameOp : (a, b : Op) -> Dec (a = b)
sameOp a b = decEq a b

sameTerm : {n : Nat} -> (a, b : Term n) -> Dec (a = b)
sameTerm a b = decEq a b

sameRose : (a, b : Rose) -> Dec (a = b)
sameRose a b = decEq a b

samePos : (a, b : Pos) -> Dec (a = b)
samePos a b = decEq a b

yn : Dec p -> String
yn (Yes _) = "same"
yn (No _) = "different"

tys : List Ty
tys = [TInt, TBool, TFun TInt TBool, TFun TBool TInt, TList TInt, TList (TList TInt),
       TPair TInt TBool, TPair TInt TInt, TFun (TPair TInt TBool) (TList TBool)]

ops : List Op
ops = [Add, Sub, Mul, Lt, Same, And, Or]

terms : List (Term 2)
terms =
  [ Var 0, Var 1, Num 0, Num 1, Truth True, Truth False
  , Lam TInt (Var 2), Lam TInt (Var 0), Lam TBool (Var 2)
  , App (Var 0) (Var 1), App (Var 1) (Var 0)
  , Bin Add (Num 1) (Num 2), Bin Sub (Num 1) (Num 2), Bin Add (Num 1) (Num 3)
  , If (Truth True) (Num 1) (Num 2), If (Truth True) (Num 1) (Num 3)
  , Let (Num 1) (Var 2), Let (Num 1) (Var 1), Let (Num 2) (Var 2)
  , Empty TInt, Empty TBool, Cons (Num 1) (Empty TInt), Cons (Num 1) (Empty TBool)
  , Lam TInt (Let (Var 0) (Bin Mul (Var 3) (Var 0)))
  , Lam TInt (Let (Var 0) (Bin Mul (Var 3) (Var 1)))
  ]

roses : List Rose
roses =
  [ MkRose Add [], MkRose Sub [], MkRose Add [MkRose Add []]
  , MkRose Add [MkRose Add [], MkRose Sub []], MkRose Add [MkRose Sub [], MkRose Add []]
  , MkRose Add [MkRose Add [MkRose Or []]], MkRose Add [MkRose Add [MkRose And []]]
  ]

poss : List Pos
poss = [MkPos 1 ItIsSucc, MkPos 2 ItIsSucc, MkPos 7 ItIsSucc]

-- One character per pair: `=` when decEq says Yes, `.` when it says No.
table : (a -> a -> Bool) -> List a -> List String
table same xs = map (\x => pack (map (\y => if same x y then '=' else '.') xs)) xs

main : IO ()
main = do
  putStrLn "Ty";   traverse_ putStrLn (table (\a, b => isYes (sameTy a b)) tys)
  putStrLn "Op";   traverse_ putStrLn (table (\a, b => isYes (sameOp a b)) ops)
  putStrLn "Term"; traverse_ putStrLn (table (\a, b => isYes (sameTerm a b)) terms)
  putStrLn "Rose"; traverse_ putStrLn (table (\a, b => isYes (sameRose a b)) roses)
  putStrLn "Pos";  traverse_ putStrLn (table (\a, b => isYes (samePos a b)) poss)
  putStrLn (yn (sameTerm (the (Term 0) (Lam TInt (Var 0))) (Lam TInt (Var 0))))
