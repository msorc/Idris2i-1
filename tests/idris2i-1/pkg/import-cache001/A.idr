module A

export infixl 6 +++

public export
data T = MkT Nat

public export
f : T -> Nat
f (MkT n) = n

public export
(+++) : Nat -> Nat -> Nat
x +++ y = x * 10 + y

public export
g : Nat
g = 1

public export
interface Describe a where
  describe : a -> String

public export
Describe T where
  describe (MkT n) = "T " ++ show n
