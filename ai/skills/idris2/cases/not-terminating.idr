-- expect: E0704
total
count : List Int -> Nat
count [] = 0
count (x :: xs) = S (count (filter (/= x) xs))
