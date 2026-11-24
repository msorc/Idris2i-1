||| A function declared before its clauses is checked as before: within the
||| mutual block, `T` is one copy, so `T : T` is rejected.
module Forward

%default total

T : Type
selfT : T

mutual
  T = Type
  selfT = T
