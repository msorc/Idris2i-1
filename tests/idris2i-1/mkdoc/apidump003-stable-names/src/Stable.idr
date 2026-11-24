module Stable

-- A name in the dump is the same whatever the source positions, the numbers of
-- machine generated names and the modules that are loaded

-- The implementations in the type of a constructor, in the left operand of an
-- operator as well as in the right one
public export
data InRange : Int -> Type where
  MkInRange : (n : Int) -> (n >= 0 && n < 100) === True -> InRange n

-- The name of an unnamed constraint, that is given in a type
public export
pick : Ord a => a -> a -> a
pick x y = if x < y then x else y

export
pickSame : Ord a => (x : a) -> pick x x === x
pickSame x = believe_me (Refl {x = x})

-- A left operand that is an operator too
export
assoc : (x, y, z : Bool) -> ((x && y) && z) === (x && (y && z))
assoc x y z = believe_me (Refl {x = x})
