module A.B

-- The names that the counter of the module makes (here, of the nested function
-- `go` and of the with block in `show`) are the same as in the namespace A.B
-- of the module A, which has the same definitions in the same order.
export
f : Nat -> Nat
f n = go n 0
  where
    go : Nat -> Nat -> Nat
    go Z acc = acc
    go (S k) acc = go k (acc + 2)

public export
data W = MkW Nat

export
Show W where
  show (MkW n) with (n)
    show (MkW n) | Z = "W"
    show (MkW n) | S k = "w" ++ show k
