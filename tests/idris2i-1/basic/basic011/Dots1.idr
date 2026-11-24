partial
bar : (n : Nat) -> (m : Nat) -> n = m -> Nat
bar (S m) (S m) (Refl {x = S m}) = m

data Baz : Int -> Type where
     AddThings : (x : Int) -> (y : Int) -> Baz (x + y)

addBaz : (x : Int) -> Baz x -> Int
addBaz (x + y) (AddThings x y) = x + y

-- Not allowed in Idris2i-1, we use unification rather than matching!
-- addBaz2 : (x : Int) -> Baz x -> Int
-- addBaz2 (_ + _) (AddThings x y) = x + y

-- Also not allowed in Idris2i-1!
-- addBaz3 : (x : Int) -> Baz x -> Int
-- addBaz3 (x + y) (AddThings _ _) = x + y
