-- expect: E0606
-- n is erased and two constructors could match: the match would need n at run time.

isZ : (0 n : Nat) -> Bool
isZ Z = True
isZ (S _) = False
