%default total

data Tree = Leaf | Node Tree Nat Tree

-- The argument is matched but passed on unchanged
same : Nat -> Nat
same Z = Z
same (S k) = same (S k)

-- The argument grows
grow : List Nat -> Nat
grow [] = 0
grow (x :: xs) = grow (x :: x :: xs)

-- Two arguments, neither gets smaller; only the matched one is explained
size : Tree -> Nat -> Nat
size Leaf acc = acc
size (Node l x r) acc = size (Node r x l) (acc + x)

-- No argument is matched against a constructor
count : Nat -> Nat
count n = if n == 0 then 0 else count (n `minus` 1)

-- A mutual recursion cycle
mutual
  isEven : Nat -> Bool
  isEven n = isOdd (S n)

  isOdd : Nat -> Bool
  isOdd Z = False
  isOdd (S k) = isEven (S k)

-- A call to a function that is not total
partial
spin : Nat -> Nat
spin n = spin n

useSpin : Nat -> Nat
useSpin n = spin n + 1
