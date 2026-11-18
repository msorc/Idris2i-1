module PosB

-- PosA is imported privately
import PosA

public export
data Wrap a = MkWrap (Tree a) (List a)

export
wrap : a -> Wrap a
wrap x = MkWrap (Node Leaf (MkBox x) Leaf) [x]
