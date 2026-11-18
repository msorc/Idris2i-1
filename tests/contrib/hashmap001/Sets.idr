module Sets

import Data.HashMap as HashMap
import Data.HashSet
import Data.Integral
import Data.List

import Keys

export
sets : IO ()
sets = do
  putStrLn "-- sets"
  let s = the (HashSet Int) (fromList [3, 1, 2, 3, 1])
  let t = the (HashSet Int) (fromList [2, 3, 4])
  check "size" (size s == 3)
  check "contains" (contains 1 s && not (contains 4 s))
  check "member" (member 2 s)
  check "insert" (contains 9 (insert 9 s) && size (insert 9 s) == 4 && size (insert 1 s) == 3)
  check "delete" (not (contains 1 (delete 1 s)) && size (delete 1 s) == 2)
  check "singleton" (toList (singleton 'x') == ['x'])
  check "empty" (null (the (HashSet Int) empty))
  check "toList" (sort (toList s) == [1, 2, 3])
  check "union" (sort (toList (union s t)) == [1, 2, 3, 4])
  check "difference" (sort (toList (difference s t)) == [1])
  check "intersection" (sort (toList (intersection s t)) == [2, 3])
  check "symDifference" (sort (toList (symDifference s t)) == [1, 4])
  check "isSubsetOf" (isSubsetOf (fromList [2, 3]) s && not (isSubsetOf t s))
  check "filter" (sort (toList (filter even s)) == [2])
  check "Foldable sum" (sum s == 6)
  check "foldr" (foldr (::) [] s == toList s)
  check "Eq" (s == fromList [1, 2, 3] && s /= t && s /= fromList [1, 2])
  check "Semigroup" (s <+> t == union s t)
  check "Monoid" (the (HashSet Int) neutral == empty)
  check "keySet" (sort (Prelude.toList (keySet (the (HashMap Int Char) (HashMap.fromList [(1, 'a'), (2, 'b')])))) == [1, 2])
  check "differenceMap" (keys (differenceMap (the (HashMap Int Char) (HashMap.fromList [(1, 'a'), (2, 'b')])) (singleton 1)) == [2])
  check "intersectionMap" (keys (intersectionMap (the (HashMap Int Char) (HashMap.fromList [(1, 'a'), (2, 'b')])) (singleton 1)) == [1])
  putStrLn (show (the (HashSet Int) (fromList [5])))

