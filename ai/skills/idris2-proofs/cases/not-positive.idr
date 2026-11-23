-- expect: E0701

total
data Bad = MkBad (Bad -> Nat)
