module Main

-- A value that matched a constructor without fields is NULL or an immortal
-- value of the runtime: no reference is dropped or taken for it in the
-- branch.

data Tree = Leaf | Node Tree Int Tree

data Colour = Red | Green | Blue | Mix Colour Colour

insert : Int -> Tree -> Tree
insert x Leaf = Node Leaf x Leaf
insert x (Node l v r) = if x < v then Node (insert x l) v r
                                 else Node l v (insert x r)

size : Tree -> Int
size Leaf = 0
size (Node l _ r) = size l + 1 + size r

-- the matched value is passed on: no reference is taken
keep : Colour -> (Colour, Colour)
keep Red = (Red, Red)
keep c@Green = (c, c)
keep c@Blue = (c, Mix c c)
keep (Mix a b) = (a, b)

describe : (Colour, Colour) -> String
describe (a, b) = name a ++ "/" ++ name b
  where
    name : Colour -> String
    name Red = "red"
    name Green = "green"
    name Blue = "blue"
    name (Mix _ _) = "mix"

main : IO ()
main = do
  printLn (size (foldr insert Leaf [5, 3, 8, 1, 4]))
  traverse_ (putStrLn . describe . keep) [Red, Green, Blue, Mix Red Blue]
