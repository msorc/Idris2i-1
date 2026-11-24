-- dependent pair hiding negative
%default total
data Bad : Type where
  MkBad : (x : Nat ** (Bad -> Void)) -> Bad

notBad : Bad -> Void
notBad (MkBad (_ ** f)) = f (MkBad (Z ** f))

void : Void
void = notBad (MkBad (Z ** notBad))
