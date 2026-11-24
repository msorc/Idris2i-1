module Tree

-- With --spec-interfaces, a recursive function is copied once by an
-- implementation, and the copy calls itself: the implementation that the
-- recursive call takes is the one that the copy was made by, not one that is
-- reduced a bit more (which made four copies of toTree, one in another,
-- before they were the same).

data Tree a = Leaf | Node (Tree a) a (Tree a)

insert : Ord a => a -> Tree a -> Tree a
insert x Leaf = Node Leaf x Leaf
insert x (Node l v r) = if x < v then Node (insert x l) v r
                                 else Node l v (insert x r)

toTree : Ord a => List a -> Tree a
toTree [] = Leaf
toTree (x :: xs) = insert x (toTree xs)

toList : Tree a -> List a
toList Leaf = []
toList (Node l v r) = toList l ++ v :: toList r

sort : Ord a => List a -> List a
sort xs = toList (toTree xs)

countBelow : Ord a => a -> List a -> Nat
countBelow y xs = go 0 xs
  where
    go : Nat -> List a -> Nat
    go acc [] = acc
    go acc (x :: xs) = go (if x < y then S acc else acc) xs

main : IO ()
main = do printLn (sort [3, 1, 2, the Integer 5, 4])
          printLn (countBelow 3 [1, 2, the Integer 3, 4, 1])
