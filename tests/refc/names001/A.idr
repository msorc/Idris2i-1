module A

-- (the definition before the namespace makes the index of `g` in the context
-- differ from that of `f` in A.B, and the record there makes the numbers of
-- the nested functions the same)
y : Nat
y = 1

namespace B
  export
  g : Nat -> Nat
  g n = go n 1
    where
      go : Nat -> Nat -> Nat
      go Z acc = acc
      go (S k) acc = go k (acc * 2)
