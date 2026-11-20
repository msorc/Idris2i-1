-- Variant B of treeInt: owned style.  `OTree` and `OList` stand for types the
-- planned `[owned]` checker would accept: recursive fields have quantity 1 and
-- every function takes and returns them at quantity 1, so no value of them is
-- ever duplicated or dropped.  The comparison is `x < v` on Int, as in A.
--
-- Uniqueness at run time: every OList cell is made by `gen`, `reverseOnto` or
-- `toList`, every OTree cell by `insert`, each from fresh or just-matched
-- cells; the result of `gen` goes straight into `treesort` and its result
-- straight into `mylast` (no let binding at quantity omega, no top-level
-- constant of these types), and every function consumes its owned arguments
-- exactly once, so each cell has exactly one reference.
module Main

data OList : Type where
  Nil  : OList
  Cons : Int -> (1 _ : OList) -> OList

data OTree : Type where
  Leaf : OTree
  Node : (1 _ : OTree) -> Int -> (1 _ : OTree) -> OTree

reverseOnto : (1 acc : OList) -> (1 _ : OList) -> OList
reverseOnto acc Nil = acc
reverseOnto acc (Cons x xs) = reverseOnto (Cons x acc) xs

-- the Prelude's `xs ++ ys` after its %transform
append : (1 _ : OList) -> (1 _ : OList) -> OList
append xs ys = reverseOnto ys (reverseOnto Nil xs)

insert : Int -> (1 _ : OTree) -> OTree
insert x Leaf = Node Leaf x Leaf
insert x (Node l v r) = case x < v of
                             True  => Node (insert x l) v r
                             False => Node l v (insert x r)

toList : (1 _ : OTree) -> OList
toList Leaf = Nil
toList (Node l v r) = append (Main.toList l) (Cons v (Main.toList r))

toTree : (1 _ : OList) -> OTree
toTree Nil = Leaf
toTree (Cons x xs) = insert x (toTree xs)

treesort : (1 _ : OList) -> OList
treesort xs = Main.toList (toTree xs)

gen : Int -> Int -> OList
gen 0 n = Nil
gen k n = let n' = (1103515245 * n + 12345) `mod` 2147483648 in
              Cons n' (gen (k - 1) n')

mylast : (1 _ : OList) -> Maybe Int
mylast Nil = Nothing
mylast (Cons x Nil) = Just x
mylast (Cons x xs) = mylast xs

doSort : Int -> IO ()
doSort 0 = putStrLn "Done"
doSort k = do putStrLn $ show $ mylast (treesort (gen 30000 (k - 1)))
              doSort (k - 1)

main : IO ()
main = do max <- getLine
          doSort (cast max)
