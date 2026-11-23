module Total

%default total

count : Nat -> Nat
count n = count (S n)

covering
loop : Nat -> Nat
loop n = loop n

usesLoop : Nat -> Nat
usesLoop n = loop n
