module A

-- The same definitions as in A.B, in the namespace A.B (see A/B.idr)
namespace B
  export
  g : Nat -> Nat
  g n = go n 1
    where
      go : Nat -> Nat -> Nat
      go Z acc = acc
      go (S k) acc = go k (acc * 2)

  public export
  data V = MkV Nat

  export
  Show V where
    show (MkV n) with (n)
      show (MkV n) | Z = "V"
      show (MkV n) | S k = "v" ++ show k
