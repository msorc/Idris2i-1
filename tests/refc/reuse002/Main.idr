module Main

-- A constructor takes over the cell of another constructor with as many
-- fields (size-based reuse), when the cell is unique: its tag changes, and
-- the fields that stay where they were are not stored again.

data Shape = Circle Int Int | Rect Int Int | Tri Int Int Int

Show Shape where
  show (Circle a b) = "Circle \{show a} \{show b}"
  show (Rect a b) = "Rect \{show a} \{show b}"
  show (Tri a b c) = "Tri \{show a} \{show b} \{show c}"

-- the fields swap places
turn : Shape -> Shape
turn (Circle a b) = Rect b a
turn (Rect a b) = Circle a (b + 1)
turn (Tri a b c) = Tri c b a

-- a field that stays where it was, but is used twice: the cell keeps its
-- reference, and the other use takes one
dupe : Shape -> Shape
dupe (Circle a b) = Circle b b
dupe (Rect a b) = Circle b b
dupe s = s

-- across types: Either to Maybe-like (one field each)
data Opt a = None | Some a

Show a => Show (Opt a) where
  show None = "None"
  show (Some x) = "Some " ++ show x

swap : Either a b -> Either b a
swap (Left x) = Right x
swap (Right y) = Left y

toOpt : Either String a -> Opt a
toOpt (Left _) = None
toOpt (Right x) = Some x

data Expr = Num Int | Add Expr Expr | Mul Expr Expr

eval : Expr -> Int
eval (Num n) = n
eval (Add a b) = eval a + eval b
eval (Mul a b) = eval a * eval b

-- a rewrite that keeps both cells: Mul (Add a b) c to Add (Mul a c) (Mul b c)
distrib : Expr -> Expr
distrib (Mul (Add a b) c) = Add (Mul a c) (Mul b c)
distrib (Add a b) = Add (distrib a) (distrib b)
distrib e = e

main : IO ()
main = do
  let shapes = [Circle 1 2, Rect 3 4, Tri 5 6 7]
  -- the list is used again below, so these cells are shared: no reuse
  printLn (map turn shapes)
  printLn shapes
  -- unique cells: reused
  printLn (map turn (map turn [Circle 10 20, Rect 30 40, Tri 50 60 70]))
  printLn (map dupe [Circle 1 2, Rect 3 4, Tri 5 6 7])
  let ss = [Circle 1 2, Rect 3 4]
  printLn (map dupe ss, ss)
  let es = [Left 1, Right "two", Left 3]
  printLn (map swap es)
  printLn (map (swap . swap) es)
  printLn (map toOpt [Left "no", Right (the Int 5)])
  let e = Mul (Add (Num 2) (Num 3)) (Num 4)
  printLn (eval (distrib e), eval e)
  printLn (eval (distrib (Mul (Add (Num 1) (Num 1)) (Num 10))))
