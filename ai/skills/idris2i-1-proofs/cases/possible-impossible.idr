-- expect: E0603

f : Nat -> Nat
f Z impossible
f (S k) = k
