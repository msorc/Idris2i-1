||| Persistent hash sets, on top of `Data.HashMap`.
|||
||| A `HashSet a` holds elements of a `Hashable` type without duplicates.
||| Membership, insertion and deletion are as fast as the operations of
||| `Data.HashMap`; the elements are not kept in any order that can be relied
||| on (they come out in the order of their hashes).  See `Data.SortedSet` for
||| the same interface on ordered elements.
module Data.HashSet

import Data.HashMap
import Data.List

%default total

||| A persistent set of elements with hashing.
export
data HashSet : Type -> Type where
  MkHashSet : HashMap a () -> HashSet a

||| The set with no elements.
export
empty : HashSet a
empty = MkHashSet empty

||| The set with one element.
export
singleton : Hashable a => a -> HashSet a
singleton x = MkHashSet (singleton x ())

||| The number of elements.  The set does not store it: this takes time in the
||| size of the set (see `Data.HashMap.size`).
export
size : HashSet a -> Nat
size (MkHashSet m) = size m

||| Adds an element.
export
insert : Hashable a => a -> HashSet a -> HashSet a
insert x (MkHashSet m) = MkHashSet (insert x () m)

||| `insert` with the arguments flipped.
public export %inline
insert' : Hashable a => HashSet a -> a -> HashSet a
insert' = flip insert

||| Removes an element; the set is unchanged if it is not in it.
export
delete : Hashable a => a -> HashSet a -> HashSet a
delete x (MkHashSet m) = MkHashSet (delete x m)

||| `delete` with the arguments flipped.
public export %inline
delete' : Hashable a => HashSet a -> a -> HashSet a
delete' = flip delete

||| Is the element in the set?
export
contains : Hashable a => a -> HashSet a -> Bool
contains x (MkHashSet m) = member x m

||| Is the element in the set?  (The same as `contains`, the name used by
||| `Data.HashMap`.)
export
member : Hashable a => a -> HashSet a -> Bool
member = contains

||| `contains` with the arguments flipped.
public export %inline
contains' : Hashable a => HashSet a -> a -> Bool
contains' = flip contains

||| The set of the elements of a list.
export
fromList : Hashable a => List a -> HashSet a
fromList xs = MkHashSet (foldl (\m, x => insert x () m) empty xs)

||| The elements come out in the order of their hashes.
export
Foldable HashSet where
  foldr f z (MkHashSet m) = foldrWithKey (\k, _, acc => f k acc) z m
  foldl f z (MkHashSet m) = foldlWithKey (\acc, k, _ => f acc k) z m
  null (MkHashSet m) = null m
  toList (MkHashSet m) = keys m

||| Keeps the elements for which the predicate holds.
export
filter : (a -> Bool) -> HashSet a -> HashSet a
filter p (MkHashSet m) = MkHashSet (filterWithKey (\k, _ => p k) m)

||| Set union.
export
union : Hashable a => HashSet a -> HashSet a -> HashSet a
union (MkHashSet x) (MkHashSet y) = MkHashSet (mergeLeft x y)

||| Set difference: the elements of the first set that are not in the second.
export
difference : Hashable a => HashSet a -> HashSet a -> HashSet a
difference x y = filter (\e => not (contains e y)) x

||| Set intersection.
export
intersection : Hashable a => HashSet a -> HashSet a -> HashSet a
intersection x y = filter (\e => contains e y) x

||| Set symmetric difference: the elements that are in exactly one of the sets.
export
symDifference : Hashable a => HashSet a -> HashSet a -> HashSet a
symDifference x y = union (difference x y) (difference y x)

||| Is every element of the first set in the second?
export
isSubsetOf : Hashable a => HashSet a -> HashSet a -> Bool
isSubsetOf x y = size x <= size y && foldr (\e, ok => ok && contains e y) True x

||| The set of the keys of a map.
export
keySet : HashMap k v -> HashSet k
keySet m = MkHashSet (map (const ()) m)

||| The map from the elements of a set to the unit value.
export %inline
toHashMap : HashSet a -> HashMap a ()
toHashMap (MkHashSet m) = m

||| A set from a map of keys with the unit value.
export %inline
fromHashMap : HashMap a () -> HashSet a
fromHashMap = MkHashSet

||| Removes all the given keys from a map.
export
differenceMap : Hashable k => HashMap k v -> HashSet k -> HashMap k v
differenceMap m s = foldr delete m s

||| Keeps only the given keys in a map.
export
intersectionMap : Hashable k => HashMap k v -> HashSet k -> HashMap k v
intersectionMap m s = filterWithKey (\k, _ => contains k s) m

||| `<+>` is the union.
export
Hashable a => Semigroup (HashSet a) where
  (<+>) = union

||| The neutral element is the empty set.
export
Hashable a => Monoid (HashSet a) where
  neutral = empty

||| Two sets are equal if they have the same elements.
export
Hashable a => Eq (HashSet a) where
  x == y = size x == size y && isSubsetOf x y

||| Shows a set as `fromList` of its elements, in the order of their hashes.
export
Show a => Show (HashSet a) where
  show s = "fromList " ++ show (Prelude.toList s)
