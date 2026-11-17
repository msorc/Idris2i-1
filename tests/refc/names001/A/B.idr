module A.B

-- (see A.idr)
record R where
  constructor MkR

export
f : Nat -> Nat
f n = go n 0
  where
    go : Nat -> Nat -> Nat
    go Z acc = acc
    go (S k) acc = go k (acc + 2)
