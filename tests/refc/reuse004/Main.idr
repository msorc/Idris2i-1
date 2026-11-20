module Main

-- The cell of a value that a branch does not use any more is taken over by
-- a constructor of the branch: the cell itself when it is unique, a copy of
-- it otherwise (made out of line), so that the fields that the constructor
-- leaves where they are are not stored again, and the branch has no test of
-- its own after the one that gives the cell.

data Tree = Leaf | Node Tree Int Tree

Show Tree where
  show Leaf = "."
  show (Node l v r) = "(" ++ show l ++ " " ++ show v ++ " " ++ show r ++ ")"

insert : Int -> Tree -> Tree
insert x Leaf = Node Leaf x Leaf
insert x (Node l v r) = if x < v then Node (insert x l) v r
                                 else Node l v (insert x r)

-- every field but one stays where it was
bump : Tree -> Tree
bump Leaf = Leaf
bump (Node l v r) = Node l (v + 1) r

-- the fields move: all of them are stored
mirror : Tree -> Tree
mirror Leaf = Leaf
mirror (Node l v r) = Node (mirror r) v (mirror l)

-- a field that is not used any more is released, the cell is taken over
dropLeft : Tree -> Tree
dropLeft Leaf = Leaf
dropLeft (Node _ v r) = Node Leaf v r

main : IO ()
main = do
  let t = foldr insert Leaf [5, 3, 8, 1, 4, 7, 9]
  -- `t` is used again below: its cells are shared, and copied
  printLn (bump t)
  printLn (mirror t)
  printLn (dropLeft t)
  printLn t
  -- unique cells: taken over
  printLn (bump (mirror (foldr insert Leaf [2, 1, 3])))
  printLn (dropLeft (foldr insert Leaf [2, 1, 3]))
