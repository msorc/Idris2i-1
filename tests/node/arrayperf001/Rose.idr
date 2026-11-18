module Rose

import Data.Linear.Array

-- A recursive type through IArray, which is defined with IOArray and
-- ArrayData, from modules that this one does not import: the positivity
-- check trusts them.
public export
data Rose = Node Int (IArray Rose)

export
leaf : Int -> Rose
leaf x = Node x (newArray 0 (\a => toIArray a id))

export
node : Int -> List Rose -> Rose
node x cs = Node x (newArray (cast (length cs)) (fill 0 cs))
  where
    fill : Int -> List Rose -> (1 _ : LinArray Rose) -> IArray Rose
    fill i [] a = toIArray a id
    fill i (c :: cs) a = let (_ # a) = write a i c in fill (i + 1) cs a

export
covering
sumRose : Rose -> Int
sumRose (Node x cs) = x + go 0 (size cs) 0
  where
    go : Int -> Int -> Int -> Int
    go i n acc = if i >= n then acc else
      case read cs i of
        Just c => go (i + 1) n (acc + assert_total (sumRose c))
        Nothing => go (i + 1) n acc
