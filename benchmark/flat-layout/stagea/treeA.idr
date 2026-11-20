-- Variant A of treeInt: the original program (BTree, insert, toList, toTree,
-- treesort) with the `Ord` dictionary specialised away by hand (the functions
-- take Int and compare with `x < v`), in one module.  `++` is the Prelude's,
-- which the %transform turns into `reverseOnto ys (reverse xs)`.  The input is
-- made by a plain recursive function instead of `take size (lincong seed)` on a
-- Stream of Integer, as in variant B (same numbers).
module Main

data BTree a = Leaf
             | Node (BTree a) a (BTree a)

insert : Int -> BTree Int -> BTree Int
insert x Leaf = Node Leaf x Leaf
insert x (Node l v r) = case x < v of
                             True  => Node (insert x l) v r
                             False => Node l v (insert x r)

toList : BTree Int -> List Int
toList Leaf = []
toList (Node l v r) = Main.toList l ++ (v :: Main.toList r)

toTree : List Int -> BTree Int
toTree [] = Leaf
toTree (x :: xs) = insert x (toTree xs)

treesort : List Int -> List Int
treesort xs = Main.toList $ toTree xs

gen : Int -> Int -> List Int
gen 0 n = []
gen k n = let n' = (1103515245 * n + 12345) `mod` 2147483648 in
              n' :: gen (k - 1) n'

mylast : List Int -> Maybe Int
mylast [] = Nothing
mylast [x] = Just x
mylast (x::xs) = mylast xs

doSort : Int -> IO ()
doSort 0 = putStrLn "Done"
doSort k = do let xs = treesort $ gen 30000 (k - 1)
              putStrLn $ show $ mylast xs
              doSort (k - 1)

main : IO ()
main = do max <- getLine
          doSort (cast max)
