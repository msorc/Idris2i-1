-- --spec-interfaces: functions that take implementations of interfaces are
-- specialised where the implementations are known, so that their methods
-- are called directly.
import Data.List
import Data.Stream

data Tree a = Leaf | Node (Tree a) a (Tree a)

insert : Ord a => a -> Tree a -> Tree a
insert x Leaf = Node Leaf x Leaf
insert x t@(Node l v r)
    = case compare x v of
           LT => Node (insert x l) v r
           GT => Node l v (insert x r)
           EQ => t

toList : Tree a -> List a
toList Leaf = []
toList (Node l v r) = toList l ++ v :: toList r

treeSort : Ord a => List a -> List a
treeSort = toList . foldr insert Leaf

-- An implementation whose methods use other implementations of the type
-- (its normal form is infinite: it is not normalised).
lincong : Integral a => a -> Stream a
lincong = tail . iterate (\n => (1103515245 * n + 12345) `mod` 2147483648)

-- Not known here: not specialised, but still correct.
sortedBy : Ord b => (a -> b) -> List a -> List a
sortedBy f = sortBy (\x, y => compare (f x) (f y))

main : IO ()
main = do
  printLn (treeSort [the Integer 5, 3, 8, 1, 4, 3])
  printLn (treeSort ["pear", "apple", "fig"])
  printLn (take 4 (lincong (the Integer 1)))
  printLn (take 2 (lincong (the Int 1)))
  printLn (sortedBy negate [the Int 2, 7, 1])
  -- (elem goes through Foldable and the named Monoid implementation Any,
  -- whose Semigroup is that of a parent)
  printLn (elem "b" ["a", "b"], elem "c" ["a", "b"], elem (the Int 3) [1, 2, 3])
  printLn (all (> 0) [the Integer 1, 2], any (== 'x') (unpack "abc"))
