module Main

import Data.Fin
import Data.Hashable
import Data.HashMap as HashMap
import Data.Integral
import Data.List
import Data.Maybe

import Keys
import Model
import Sets

import Sequences

-- Checks --------------------------------------------------------------------

showHash : Bits64 -> IO ()
showHash h = putStrLn (show h)

hashes : IO ()
hashes = do
  putStrLn "-- hashes"
  showHash (hash (the Int 0))
  showHash (hash (the Int 1))
  showHash (hash (the Int (-1)))
  showHash (hash (the Int 1234567))
  showHash (hash (the Int8 (-5)))
  showHash (hash (the Int16 300))
  showHash (hash (the Int32 (-70000)))
  showHash (hash (the Int64 5000000000))
  showHash (hash (the Bits8 255))
  showHash (hash (the Bits16 65535))
  showHash (hash (the Bits32 4000000000))
  showHash (hash (the Bits64 18446744073709551615))
  showHash (hash (the Integer 0))
  showHash (hash (the Integer 18446744073709551615))
  showHash (hash (the Integer 18446744073709551616))
  showHash (hash (the Integer (-18446744073709551616)))
  showHash (hash (the Integer 123456789012345678901234567890))
  showHash (hash (the Nat 42))
  showHash (hash 'a')
  showHash (hash '\x1F600')
  showHash (hash "")
  showHash (hash "hello")
  showHash (hash "h\xE9llo w\x00F6rld \x4E2D")
  showHash (hash True)
  showHash (hash False)
  showHash (hash ())
  showHash (hash (the Ordering LT))
  showHash (hash (the (Fin 5) 3))
  showHash (hash (the Double 1.5))
  showHash (hash (the Double (-1.5)))
  showHash (hash (the Double 0.0))
  showHash (hash (the Double (-0.0)))
  showHash (hash (the Double 1.0e100))
  showHash (hash (the Double 1.0e-100))
  showHash (hash (the Double 3.14159265358979))
  showHash (hash (the Double (1.0 / 0.0)))
  showHash (hash (the Double (-1.0 / 0.0)))
  showHash (hash (the Double (0.0 / 0.0)))
  showHash (hash (the Int 1, "two"))
  showHash (hash (the Int 1, "two", 'c'))
  showHash (hash (Nothing {ty = Int}))
  showHash (hash (Just (the Int 7)))
  showHash (hash (the (Either Int Int) (Left 7)))
  showHash (hash (the (Either Int Int) (Right 7)))
  showHash (hash [the Int 1, 2, 3])
  showHash (hash (the (List Int) []))
  showHash (hashWithSalt 12345 "salted")
  checkSequences
  check "0.0 and -0.0 hash alike" (hash (the Double 0.0) == hash (the Double (-0.0)))
  check "order matters" (hash (the Int 1, the Int 2) /= hash (the Int 2, the Int 1))
  check "salt matters" (hashWithSalt 1 "x" /= hashWithSalt 2 "x")
  check "Int hashes of 0..1999 are distinct"
    (let hs = sort (map (hash {a = Int}) (upTo 2000))
     in all id (zipWith (/=) hs (drop 1 hs)))

basics : IO ()
basics = do
  putStrLn "-- basic operations"
  let m = the (HashMap Int String) (fromList [(1, "one"), (2, "two"), (3, "three")])
  check "size" (size m == 3)
  check "lookup" (lookup 2 m == Just "two")
  check "lookup missing" (lookup 4 m == Nothing)
  check "lookup'" (lookup' m 3 == Just "three")
  check "lookupDefault" (lookupDefault "?" 9 m == "?" && lookupDefault "?" 1 m == "one")
  check "member" (member 1 m && not (member 7 m))
  check "contains" (contains 1 m && not (contains 7 m))
  check "empty" (null (the (HashMap Int Int) empty) && size (the (HashMap Int Int) empty) == 0)
  check "singleton" (HashMap.toList (singleton "k" 'v') == [("k", 'v')])
  check "not null" (not (null m))
  let m2 = insert 2 "TWO" m
  check "insert replaces" (lookup 2 m2 == Just "TWO" && size m2 == 3)
  check "persistent" (lookup 2 m == Just "two")
  let m3 = insertWith (++) 2 "x" m
  check "insertWith new ++ old" (lookup 2 m3 == Just "xtwo")
  check "insertWith absent" (lookup 5 (insertWith (++) 5 "x" m) == Just "x")
  let d = delete 2 m
  check "delete" (lookup 2 d == Nothing && size d == 2 && size m == 3)
  check "delete absent" (delete 99 m == m)
  check "delete everything" (null (foldr delete m (the (List Int) [1, 2, 3])))
  check "update insert" (lookup 8 (update (const (Just "eight")) 8 m) == Just "eight")
  check "update change" (lookup 1 (update (map (++ "!")) 1 m) == Just "one!")
  check "update delete" (lookup 1 (update (const Nothing) 1 m) == Nothing)
  check "alter" (lookup 1 (alter (const (Just "uno")) 1 m) == Just "uno")
  check "updateExisting present" (lookup 1 (updateExisting (++ "?") 1 m) == Just "one?")
  check "updateExisting absent" (updateExisting (++ "?") 9 m == m)
  check "fromListWith" (lookup 1 (fromListWith (+) [(1, 1), (2, 5), (1, 10), (1, 100)]) == Just (the Int 111))
  check "fromList last wins" (lookup 1 (fromList [(1, 'a'), (1, 'b')]) == Just 'b')
  check "insertFrom" (size (insertFrom [(10, "a"), (11, "b")] m) == 5)
  check "insertFromWith" (lookup 1 (insertFromWith (++) [(1, "a")] m) == Just "aone")
  putStrLn "-- traversals"
  check "toList sorted" (sort (HashMap.toList m) == [(1, "one"), (2, "two"), (3, "three")])
  check "kvList" (sort (kvList m) == sort (HashMap.toList m))
  check "keys" (sort (keys m) == [1, 2, 3])
  check "values" (sort (values m) == ["one", "three", "two"])
  check "foldrWithKey" (foldrWithKey (\k, _, acc => k + acc) 0 m == 6)
  check "foldlWithKey" (foldlWithKey (\acc, k, v => acc + k + cast (length v)) 0 m == 17)
  check "Foldable sum of lengths" (foldl (\a, v => a + length v) (the Nat 0) m == 11)
  check "Foldable foldr" (foldr (\v, a => a + length v) (the Nat 0) m == 11)
  check "Foldable toList" (sort (Prelude.toList m) == ["one", "three", "two"])
  check "Foldable foldMap" (length (foldMap id m) == 11)
  check "mapWithKey" (sort (HashMap.toList (mapWithKey (\k, v => show k ++ v) m)) == [(1, "1one"), (2, "2two"), (3, "3three")])
  check "Functor" (sort (values (map length m)) == [3, 3, 5])
  check "filter" (sort (keys (filter ((== 3) . length) m)) == [1, 2])
  check "filterWithKey" (keys (filterWithKey (\k, _ => k > 2) m) == [3])
  check "filter nothing removed" (filter (const True) m == m)
  check "filter all removed" (null (filter (const False) m))
  r <- traverse (\v => do putStr ""; pure (the Nat (length v))) m
  check "Traversable IO" (sort (values r) == [3, 3, 5] && size r == 3)
  check "Traversable Maybe" (map (sort . values) (traverse (\v => if v == "" then Nothing else Just v) m) == Just ["one", "three", "two"])
  check "Traversable Nothing" (isNothing (traverse (\v => if v == "two" then Nothing else Just v) m))
  putStrLn "-- merging"
  let a = the (HashMap Int String) (fromList [(1, "a1"), (2, "a2")])
  let b = the (HashMap Int String) (fromList [(2, "b2"), (3, "b3")])
  check "mergeWith" (sort (HashMap.toList (mergeWith (++) a b)) == [(1, "a1"), (2, "a2b2"), (3, "b3")])
  check "merge" (sort (HashMap.toList (merge a b)) == [(1, "a1"), (2, "a2b2"), (3, "b3")])
  check "<+>" (a <+> b == merge a b)
  check "mergeLeft" (sort (HashMap.toList (mergeLeft a b)) == [(1, "a1"), (2, "a2"), (3, "b3")])
  check "union" (union a b == mergeLeft a b)
  check "unionWith" (unionWith (++) a b == mergeWith (++) a b)
  check "neutral" ((neutral <+> a) == a && (a <+> neutral) == a)
  putStrLn "-- Eq and Show"
  check "Eq independent of insertion order"
    (fromList [(1, 'a'), (2, 'b'), (3, 'c')] == fromList [(3, 'c'), (1, 'a'), (2, 'b')])
  check "Eq after deletion" (delete 3 (fromList [(1, 'a'), (3, 'c')]) == fromList [(1, 'a')])
  check "Eq different values" (fromList [(1, 'a')] /= fromList [(1, 'b')])
  check "Eq different keys" (fromList [(1, 'a')] /= fromList [(2, 'a')])
  check "Eq different sizes" (fromList [(1, 'a')] /= fromList [(1, 'a'), (2, 'b')])
  putStrLn (show (the (HashMap Int String) (fromList [(1, "one")])))
  putStrLn (show (the (HashMap Int Int) empty))

-- Collisions ----------------------------------------------------------------

range : List Int
range = upTo 200

collisions : (Hashable k, Show k) => String -> (Int -> k) -> IO ()
collisions name mk = do
  let ks = map mk range
  let m = foldl (\acc, i => insert (mk i) i acc) empty range
  check (name ++ ": size") (size m == 200)
  check (name ++ ": all found") (all (\i => lookup (mk i) m == Just i) range)
  check (name ++ ": absent") (lookup (mk 200) m == Nothing)
  check (name ++ ": replace") (lookup (mk 7) (insert (mk 7) 1000 m) == Just 1000 && size (insert (mk 7) 1000 m) == 200)
  check (name ++ ": insertWith") (lookup (mk 7) (insertWith (+) (mk 7) 1000 m) == Just 1007)
  let evens = foldl (\acc, i => delete (mk i) acc) m (filter even range)
  check (name ++ ": delete evens") (size evens == 100 && all (\i => lookup (mk i) evens == (if even i then Nothing else Just i)) range)
  check (name ++ ": toList") (sort (map snd (HashMap.toList evens)) == filter odd range)
  check (name ++ ": delete absent") (size (delete (mk 1000) m) == 200)
  let none = foldl (\acc, i => delete (mk i) acc) m range
  check (name ++ ": delete all") (null none && size none == 0)
  -- the same map built in another order and with deletions is equal
  let m' = foldl (\acc, i => insert (mk i) i acc) empty (reverse range)
  check (name ++ ": Eq") (m == m')
  check (name ++ ": filter") (size (filter even m) == 100)
  check (name ++ ": mapWithKey") (all (\i => lookup (mk i) (map (+ 1) m) == Just (i + 1)) range)
  check (name ++ ": merge") (size (mergeWith (+) m evens) == 200 && lookup (mk 1) (mergeWith (+) m evens) == Just 2)

collisionTests : IO ()
collisionTests = do
  putStrLn "-- collisions"
  collisions "same hash" MkSame
  collisions "few hashes" MkFew
  collisions "high bits" MkHigh

-- A bigger map ---------------------------------------------------------------

big : IO ()
big = do
  putStrLn "-- bigger map"
  let n = 20000
  let m = foldl (\acc, i => insert i (i * i) acc) empty (upTo n)
  check "size" (size m == cast n)
  check "lookups" (all (\i => lookup i m == Just (i * i)) (upTo n))
  check "absent" (not (any (\i => member i m) (map (+ n) (upTo 1001))))
  let h = foldl (\acc, i => delete i acc) m (filter even (upTo n))
  check "delete half" (size h == cast (n `div` 2) && all (\i => member i h == odd i) (upTo n))
  check "sum" (sum m == sum (map (\i => i * i) (upTo n)))
  let strs = foldl (\acc, i => insert (show i) i acc) empty (upTo 10000)
  check "string keys" (size strs == 10000 && all (\i => lookup (show i) strs == Just i) (upTo 2000))

main : IO ()
main = do
  hashes
  basics
  sets
  collisionTests
  modelTests
  big
