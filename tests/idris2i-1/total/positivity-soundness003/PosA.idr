module PosA

public export
data Box a = MkBox a | Empty

public export
data Tree a = Leaf | Node (Tree a) (Box a) (Tree a)
