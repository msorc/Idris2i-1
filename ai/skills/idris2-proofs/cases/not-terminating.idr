-- expect: E0704

data Rose a = Node a (List (Rose a))

total
size : Rose a -> Nat
size (Node _ ts) = S (sum (map size ts))
