-- expect: E0102
-- plus recurses on its first argument, so n + 0 does not evaluate.

plusZ : (n : Nat) -> n + 0 = n
plusZ n = Refl
