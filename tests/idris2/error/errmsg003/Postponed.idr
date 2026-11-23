-- A constraint that is postponed and fails later: it keeps the order of
-- the expected type and the type of the expression
record R where
  constructor MkR
  ty : Pair Type Type
  fn : fst ty -> Bool

r : R
r = MkR (Nat, String) (\ s : String => True)
