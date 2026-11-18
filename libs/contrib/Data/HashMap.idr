||| Persistent hash maps: hash tries with collision buckets.
|||
||| A `HashMap k v` maps keys to values, for keys with a `Hashable` instance
||| (see `Data.Hashable`).  Compared to `Data.SortedMap`, no ordering of the
||| keys is needed, and lookup, insertion and deletion take time that depends
||| on the size of the map only through the depth of the trie, which is about
||| `log4 n` (at most 15) levels, instead of `log n` comparisons of keys.
||| The price is that the entries are not in key order: `toList`, `keys`,
||| `values` and the folds visit the entries in the order of the hashes of
||| the keys, which is deterministic, the same on every back end, but arbitrary.
|||
||| The map is a trie on the low 30 bits of the hash of the key, 2 bits per
||| level.  A node is empty, holds one entry, is a bucket of entries whose keys
||| have the same 30 bits of hash, or branches four ways.  Updates copy the
||| nodes on the path from the root to the changed entry (and nothing else),
||| so old versions of a map stay valid.  Nodes are plain constructors with
||| four fields rather than arrays of sub-tries: the array primitives of the
||| standard libraries (`Data.IOArray`, `Data.Linear.Array`) can only be used
||| from pure code through `unsafePerformIO`, and an implementation with 32-way
||| nodes in such arrays, which was tried, took 75000 instructions per insertion
||| into a map of 100000 entries on Chez, against 4000 for `Data.SortedMap`,
||| because every update copies an array element by element.
|||
||| Every function is total.  Keys are compared with `==` after their hashes
||| compare equal, so `Eq` and `Hashable` must agree: `x == y` must imply
||| `hash x == hash y`.
module Data.HashMap

import public Data.Hashable
import Data.List
import Data.Maybe

%default total

--------------------------------------------------------------------------------
-- Trie nodes
--------------------------------------------------------------------------------

-- The key in the trie is the low 30 bits of the hash, as an Int that has the
-- same value on every back end (the JavaScript back ends have 32 bit Ints).
-- Two keys with the same trie key share a Bucket.
%inline
trieKey : Hashable k => k -> Int
trieKey k = cast (prim__and_Bits64 (hash k) 0x3fffffff)

-- The two bits of the trie key, after a shift, that select a child.
%inline
chunk : Int -> Int -> Int
chunk key shift = prim__and_Int (prim__shr_Int key shift) 3

-- A node whose index is the number of levels of branches that may still be
-- below it.  A node of index Z can only be empty, an entry or a bucket, so
-- all the recursions on nodes are structural on the index and the code needs
-- neither fuel nor assert_total.
--
-- Entries keep the trie key of their key, to avoid hashing again when the
-- trie is rebuilt and to compare cheaply before comparing keys.
data Node : Nat -> Type -> Type -> Type where
  -- No entries.  Children of a branch are Empty where there is nothing.
  Empty : Node n k v
  -- One entry.
  Leaf : (trieKey : Int) -> (key : k) -> (val : v) -> Node n k v
  -- Several entries, in no particular order.  All of them have the same trie
  -- key, which fits in 15 levels of 2 bits, unless the node is at index Z.
  Bucket : List (Int, k, v) -> Node n k v
  -- A branch with the children for the chunks 0, 1, 2 and 3.
  Branch : (c0, c1, c2, c3 : Node n k v) -> Node (S n) k v

-- 30 bits of trie key at 2 bits per level.
Levels : Nat
Levels = 15

-- The index of a node as a value that is there at run time, for the functions
-- that must tell Z from S: it is a chain of constructors, which is cheaper than
-- arithmetic on Nat (a big number on some back ends).
data Level : Nat -> Type where
  LZ : Level Z
  LS : Level n -> Level (S n)

topLevel : Level Levels
topLevel = LS (LS (LS (LS (LS (LS (LS (LS (LS (LS (LS (LS (LS (LS (LS LZ))))))))))))))

||| A persistent map from keys to values, with hashing.
export
data HashMap : Type -> Type -> Type where
  MkHashMap : (size : Int) -> Node Levels k v -> HashMap k v

--------------------------------------------------------------------------------
-- Lookup
--------------------------------------------------------------------------------

findEntry : Eq k => Int -> k -> List (Int, k, v) -> Maybe v
findEntry _ _ [] = Nothing
findEntry hk k ((hk', k', v) :: es) =
  if hk == hk' && k == k' then Just v else findEntry hk k es

lookupAt : Eq k => (0 lvl : Nat) -> (shift : Int) -> Int -> k ->
           Node lvl k v -> Maybe v
lookupAt _ _ _ _ Empty = Nothing
lookupAt _ _ hk k (Leaf hk' k' v) =
  if hk == hk' && k == k' then Just v else Nothing
lookupAt _ _ hk k (Bucket es) = findEntry hk k es
lookupAt (S m) shift hk k (Branch c0 c1 c2 c3) =
  case chunk hk shift of
    0 => lookupAt m (shift + 2) hk k c0
    1 => lookupAt m (shift + 2) hk k c1
    2 => lookupAt m (shift + 2) hk k c2
    _ => lookupAt m (shift + 2) hk k c3

--------------------------------------------------------------------------------
-- Insertion
--------------------------------------------------------------------------------

-- A node for entries that all have the same trie key.
fromEntries : List (Int, k, v) -> Node n k v
fromEntries [] = Empty
fromEntries [(hk, k, v)] = Leaf hk k v
fromEntries es = Bucket es

-- The trie key of a leaf or a bucket.
nodeKey : Node n k v -> Int
nodeKey (Leaf hk _ _) = hk
nodeKey (Bucket ((hk, _, _) :: _)) = hk
nodeKey _ = 0

-- A branch with one child.
single : Int -> Node n k v -> Node (S n) k v
single 0 x = Branch x Empty Empty Empty
single 1 x = Branch Empty x Empty Empty
single 2 x = Branch Empty Empty x Empty
single _ x = Branch Empty Empty Empty x

-- Put a child into an empty slot of a branch.
fill : Int -> Node n k v -> Node (S n) k v -> Node (S n) k v
fill 0 x (Branch _ c1 c2 c3) = Branch x c1 c2 c3
fill 1 x (Branch c0 _ c2 c3) = Branch c0 x c2 c3
fill 2 x (Branch c0 c1 _ c3) = Branch c0 c1 x c3
fill _ x (Branch c0 c1 c2 _) = Branch c0 c1 c2 x
fill _ _ other = other -- cannot happen: only called on branches

-- Put two groups of entries with different trie keys into a node at some level.
-- At the last level (index Z) all the entries go into one bucket.
merge2 : Level lvl -> (shift : Int) ->
         (ha : Int) -> List (Int, k, v) ->
         (hb : Int) -> List (Int, k, v) -> Node lvl k v
merge2 LZ _ _ as _ bs = Bucket (as ++ bs)
merge2 (LS m) shift ha as hb bs =
  let ca = chunk ha shift
      cb = chunk hb shift
  in if ca == cb
        then single ca (merge2 m (shift + 2) ha as hb bs)
        else fill cb (fromEntries bs) (single ca (fromEntries as))

-- Add or combine an entry in a bucket.  The result says if the number of
-- entries grew.
insertBucket : Eq k => (v -> v -> v) -> Int -> k -> v ->
               List (Int, k, v) -> (Int, List (Int, k, v))
insertBucket f hk k v [] = (1, [(hk, k, v)])
insertBucket f hk k v (e@(hk', k', v') :: es) =
  if hk == hk' && k == k'
     then (0, (hk, k, f v v') :: es)
     else let (d, es') = insertBucket f hk k v es in (d, e :: es')

-- Insert, combining with `f new old` if the key is present.  The result is the
-- change in the number of entries and the new node.
insertAt : Eq k => Level lvl -> (shift : Int) -> (v -> v -> v) ->
           Int -> k -> v -> Node lvl k v -> (Int, Node lvl k v)
insertAt _ _ _ hk k v Empty = (1, Leaf hk k v)
insertAt lvl shift f hk k v (Leaf hk' k' v') =
  if hk == hk'
     then if k == k'
             then (0, Leaf hk k (f v v'))
             else (1, Bucket [(hk, k, v), (hk', k', v')])
     else (1, merge2 lvl shift hk [(hk, k, v)] hk' [(hk', k', v')])
insertAt lvl shift f hk k v node@(Bucket es) =
  if hk /= nodeKey node
     then (1, merge2 lvl shift hk [(hk, k, v)] (nodeKey node) es)
     else let (d, es') = insertBucket f hk k v es in (d, Bucket es')
insertAt (LS m) shift f hk k v (Branch c0 c1 c2 c3) =
  case chunk hk shift of
    0 => let (d, c) = insertAt m (shift + 2) f hk k v c0 in (d, Branch c c1 c2 c3)
    1 => let (d, c) = insertAt m (shift + 2) f hk k v c1 in (d, Branch c0 c c2 c3)
    2 => let (d, c) = insertAt m (shift + 2) f hk k v c2 in (d, Branch c0 c1 c c3)
    _ => let (d, c) = insertAt m (shift + 2) f hk k v c3 in (d, Branch c0 c1 c2 c)

--------------------------------------------------------------------------------
-- Deletion
--------------------------------------------------------------------------------

deleteBucket : Eq k => Int -> k -> List (Int, k, v) ->
               Maybe (List (Int, k, v))
deleteBucket _ _ [] = Nothing
deleteBucket hk k (e@(hk', k', v') :: es) =
  if hk == hk' && k == k'
     then Just es
     else map (e ::) (deleteBucket hk k es)

isEmpty : Node n k v -> Bool
isEmpty Empty = True
isEmpty _ = False

-- A leaf or a bucket, at any index.
leafy : Node n k v -> Maybe (Node m k v)
leafy (Leaf hk k v) = Just (Leaf hk k v)
leafy (Bucket es) = Just (Bucket es)
leafy _ = Nothing

-- A branch that has only a leaf or a bucket as a child is replaced by that
-- child; this keeps the trie in the same shape whatever the order of the
-- operations that led to it.
tidy : (c0, c1, c2, c3 : Node n k v) -> Node (S n) k v
tidy c0 c1 c2 c3 =
  case (isEmpty c0, isEmpty c1, isEmpty c2, isEmpty c3) of
    (True, True, True, True) => Empty
    (False, True, True, True) => fromMaybe (Branch c0 c1 c2 c3) (leafy c0)
    (True, False, True, True) => fromMaybe (Branch c0 c1 c2 c3) (leafy c1)
    (True, True, False, True) => fromMaybe (Branch c0 c1 c2 c3) (leafy c2)
    (True, True, True, False) => fromMaybe (Branch c0 c1 c2 c3) (leafy c3)
    _ => Branch c0 c1 c2 c3

-- Delete a key.  `Nothing` means that the key is not in the node.
deleteAt : Eq k => (0 lvl : Nat) -> (shift : Int) -> Int -> k ->
           Node lvl k v -> Maybe (Node lvl k v)
deleteAt _ _ _ _ Empty = Nothing
deleteAt _ _ hk k (Leaf hk' k' _) =
  if hk == hk' && k == k' then Just Empty else Nothing
deleteAt _ _ hk k (Bucket es) =
  case deleteBucket hk k es of
    Nothing => Nothing
    Just es' => Just (fromEntries es')
deleteAt (S m) shift hk k (Branch c0 c1 c2 c3) =
  case chunk hk shift of
    0 => map (\c => tidy c c1 c2 c3) (deleteAt m (shift + 2) hk k c0)
    1 => map (\c => tidy c0 c c2 c3) (deleteAt m (shift + 2) hk k c1)
    2 => map (\c => tidy c0 c1 c c3) (deleteAt m (shift + 2) hk k c2)
    _ => map (\c => tidy c0 c1 c2 c) (deleteAt m (shift + 2) hk k c3)

--------------------------------------------------------------------------------
-- Folds and maps
--------------------------------------------------------------------------------

foldrNode : (0 lvl : Nat) -> (Int -> k -> v -> b -> b) -> b ->
            Node lvl k v -> b
foldrNode _ f z Empty = z
foldrNode _ f z (Leaf hk k v) = f hk k v z
foldrNode _ f z (Bucket es) = foldr (\(hk, k, v), acc => f hk k v acc) z es
foldrNode (S m) f z (Branch c0 c1 c2 c3) =
  foldrNode m f (foldrNode m f (foldrNode m f (foldrNode m f z c3) c2) c1) c0

foldlNode : (0 lvl : Nat) -> (b -> Int -> k -> v -> b) -> b ->
            Node lvl k v -> b
foldlNode _ f z Empty = z
foldlNode _ f z (Leaf hk k v) = f z hk k v
foldlNode _ f z (Bucket es) = foldl (\acc, (hk, k, v) => f acc hk k v) z es
foldlNode (S m) f z (Branch c0 c1 c2 c3) =
  foldlNode m f (foldlNode m f (foldlNode m f (foldlNode m f z c0) c1) c2) c3

mapNode : (0 lvl : Nat) -> (k -> v -> w) -> Node lvl k v -> Node lvl k w
mapNode _ f Empty = Empty
mapNode _ f (Leaf hk k v) = Leaf hk k (f k v)
mapNode _ f (Bucket es) = Bucket (map (\(hk, k, v) => (hk, k, f k v)) es)
mapNode (S m) f (Branch c0 c1 c2 c3) =
  Branch (mapNode m f c0) (mapNode m f c1) (mapNode m f c2) (mapNode m f c3)

traverseNode : Applicative f => (0 lvl : Nat) -> (k -> v -> f w) ->
               Node lvl k v -> f (Node lvl k w)
traverseNode _ g Empty = pure Empty
traverseNode _ g (Leaf hk k v) = Leaf hk k <$> g k v
traverseNode _ g (Bucket es) =
  Bucket <$> traverse (\(hk, k, v) => (\w => (hk, k, w)) <$> g k v) es
traverseNode (S m) g (Branch c0 c1 c2 c3) =
  Branch <$> traverseNode m g c0 <*> traverseNode m g c1
         <*> traverseNode m g c2 <*> traverseNode m g c3

--------------------------------------------------------------------------------
-- Construction and queries
--------------------------------------------------------------------------------

||| The map with no entries.
export
empty : HashMap k v
empty = MkHashMap 0 Empty

||| The map with one entry.
export
singleton : Hashable k => k -> v -> HashMap k v
singleton k v = MkHashMap 1 (Leaf (trieKey k) k v)

||| The number of entries, in constant time.
export
size : HashMap k v -> Nat
size (MkHashMap n _) = integerToNat (cast n)

||| Looks up the value of a key.
export
lookup : Hashable k => k -> HashMap k v -> Maybe v
lookup k (MkHashMap _ root) = lookupAt Levels 0 (trieKey k) k root

||| `lookup` with the arguments flipped.
public export %inline
lookup' : Hashable k => HashMap k v -> k -> Maybe v
lookup' = flip lookup

||| Looks up the value of a key, with a default for the keys that are not in the map.
export
lookupDefault : Hashable k => v -> k -> HashMap k v -> v
lookupDefault def k m = fromMaybe def (lookup k m)

||| Is the key in the map?
export
member : Hashable k => k -> HashMap k v -> Bool
member k m = isJust (lookup k m)

||| Is the key in the map? (The same as `member`, the name that `Data.SortedSet`
||| uses.)
export
contains : Hashable k => k -> HashMap k v -> Bool
contains = member

||| Inserts a key and a value, replacing the value if the key is in the map.
export
insert : Hashable k => k -> v -> HashMap k v -> HashMap k v
insert k v (MkHashMap n root) =
  let (d, root') = insertAt topLevel 0 (\new, _ => new) (trieKey k) k v root
  in MkHashMap (n + d) root'

||| Inserts a key and a value and, if the key is in the map, stores
||| `f new old` instead; like `Data.SortedMap.insertWith`.
export
insertWith : Hashable k => (v -> v -> v) -> k -> v -> HashMap k v -> HashMap k v
insertWith f k v (MkHashMap n root) =
  let (d, root') = insertAt topLevel 0 f (trieKey k) k v root
  in MkHashMap (n + d) root'

-- Insert with a trie key that is known.
insertHashedWith : Eq k => (v -> v -> v) -> Int -> k -> v -> HashMap k v ->
                   HashMap k v
insertHashedWith f h k v (MkHashMap n root) =
  let (d, root') = insertAt topLevel 0 f h k v root
  in MkHashMap (n + d) root'

||| Inserts all the entries of a collection, the later ones replacing the earlier.
export
insertFrom : (Foldable f, Hashable k) => f (k, v) -> HashMap k v -> HashMap k v
insertFrom xs m = foldl (\acc, (k, v) => insert k v acc) m xs

||| Inserts all the entries of a collection, combining the value of an entry
||| with the value of an earlier one, or one that is in the map, by `f new old`.
export
insertFromWith : (Foldable f, Hashable k) => (v -> v -> v) -> f (k, v) ->
                 HashMap k v -> HashMap k v
insertFromWith f xs m = foldl (\acc, (k, v) => insertWith f k v acc) m xs

||| Removes a key; the map is unchanged if the key is not in it.
export
delete : Hashable k => k -> HashMap k v -> HashMap k v
delete k m@(MkHashMap n root) =
  case deleteAt Levels 0 (trieKey k) k root of
    Nothing => m
    Just root' => MkHashMap (n - 1) root'

||| Changes, adds or removes the entry of a key: `f` receives the current value
||| and returns the new one, with `Nothing` meaning "no entry".
export
update : Hashable k => (Maybe v -> Maybe v) -> k -> HashMap k v -> HashMap k v
update f k m =
  case f (lookup k m) of
    Nothing => delete k m
    Just v => insert k v m

||| The same as `update`, the name that most hash map libraries use.
export
alter : Hashable k => (Maybe v -> Maybe v) -> k -> HashMap k v -> HashMap k v
alter = update

||| Applies a function to the value of a key if the key is in the map.
export
updateExisting : Hashable k => (v -> v) -> k -> HashMap k v -> HashMap k v
updateExisting f k m =
  case lookup k m of
    Nothing => m
    Just v => insert k (f v) m

||| A map from a list of entries, the later ones replacing the earlier.
export
fromList : Hashable k => List (k, v) -> HashMap k v
fromList = flip insertFrom empty

||| A map from a list of entries; the values of equal keys are combined
||| by `f new old`.
export
fromListWith : Hashable k => (v -> v -> v) -> List (k, v) -> HashMap k v
fromListWith f = flip (insertFromWith f) empty

--------------------------------------------------------------------------------
-- Traversals
--------------------------------------------------------------------------------

||| Right fold over the entries, in the order of the hashes of the keys.
export
foldrWithKey : (k -> v -> b -> b) -> b -> HashMap k v -> b
foldrWithKey f z (MkHashMap _ root) = foldrNode Levels (\_ => f) z root

||| Left fold over the entries, in the order of the hashes of the keys.
export
foldlWithKey : (b -> k -> v -> b) -> b -> HashMap k v -> b
foldlWithKey f z (MkHashMap _ root) = foldlNode Levels (\acc, _ => f acc) z root

||| The entries as a list of pairs, in the order of the hashes of the keys.
export
toList : HashMap k v -> List (k, v)
toList = foldrWithKey (\k, v, acc => (k, v) :: acc) []

||| The same as `toList`, the name `Data.SortedMap` uses.
public export %inline
kvList : HashMap k v -> List (k, v)
kvList = toList

||| The keys, in the order of their hashes.
export
keys : HashMap k v -> List k
keys = foldrWithKey (\k, _, acc => k :: acc) []

||| The values, in the order of the hashes of their keys.  May contain duplicates.
export
values : HashMap k v -> List v
values = foldrWithKey (\_, v, acc => v :: acc) []

||| Applies a function to every value, which also receives its key.
export
mapWithKey : (k -> v -> w) -> HashMap k v -> HashMap k w
mapWithKey f (MkHashMap n root) = MkHashMap n (mapNode Levels f root)

||| Keeps the entries for which the predicate holds.
export
filterWithKey : Eq k => (k -> v -> Bool) -> HashMap k v -> HashMap k v
filterWithKey p m@(MkHashMap n root) =
  let kept = foldrWithKey' (\h, k, v, acc => if p k v then (h, k, v) :: acc else acc) [] m
  in if length kept == cast n
        then m
        else foldl (\acc, (h, k, v) => insertHashedWith (\new, _ => new) h k v acc)
                   empty kept
  where
    foldrWithKey' : (Int -> k -> v -> b -> b) -> b -> HashMap k v -> b
    foldrWithKey' f z (MkHashMap _ root) = foldrNode Levels f z root

||| Keeps the entries whose values satisfy the predicate.
export
filter : Eq k => (v -> Bool) -> HashMap k v -> HashMap k v
filter p = filterWithKey (\_, v => p v)

||| Merges two maps.  When a key is in both, the new value is `f x y`, where
||| `x` is the value in the first map and `y` the one in the second.
export
mergeWith : Eq k => (v -> v -> v) -> HashMap k v -> HashMap k v -> HashMap k v
mergeWith f x (MkHashMap _ root) =
  foldlNode Levels (\acc, h, k, v => insertHashedWith (\new, old => f old new) h k v acc)
            x root

||| Merges two maps, combining the values of keys that are in both with the
||| `Semigroup` operation, the value of the first map on the left.
export
merge : (Eq k, Semigroup v) => HashMap k v -> HashMap k v -> HashMap k v
merge = mergeWith (<+>)

||| Left-biased merge: the value of the first map wins.
export
mergeLeft : Eq k => HashMap k v -> HashMap k v -> HashMap k v
mergeLeft = mergeWith const

||| The union of two maps; for keys in both, the value of the first map is kept.
export
union : Eq k => HashMap k v -> HashMap k v -> HashMap k v
union = mergeLeft

||| The union of two maps, combining the values of keys in both by `f`,
||| the same as `mergeWith`.
export
unionWith : Eq k => (v -> v -> v) -> HashMap k v -> HashMap k v -> HashMap k v
unionWith = mergeWith

--------------------------------------------------------------------------------
-- Interfaces
--------------------------------------------------------------------------------

||| Maps over the values.
export
Functor (HashMap k) where
  map f = mapWithKey (\_ => f)

||| Folds over the values, in the order of the hashes of their keys.
export
Foldable (HashMap k) where
  foldr f z = foldrWithKey (\_ => f) z
  foldl f z = foldlWithKey (\acc, _, v => f acc v) z
  null (MkHashMap n _) = n == 0
  toList = values
  foldMap f = foldrWithKey (\_, v, acc => f v <+> acc) neutral

||| Traverses the values, in the order of the hashes of their keys.
export
Traversable (HashMap k) where
  traverse f (MkHashMap n root) =
    MkHashMap n <$> traverseNode Levels (\_ => f) root

||| Shows a map as `fromList` of its entries, in the order of the hashes of the keys.
export
(Show k, Show v) => Show (HashMap k v) where
  show m = "fromList " ++ show (Data.HashMap.toList m)

||| Two maps are equal when they have the same entries, whatever the history
||| of insertions and deletions that built them.
export
(Hashable k, Eq v) => Eq (HashMap k v) where
  x == y = Data.HashMap.size x == Data.HashMap.size y &&
           foldrWithKey (\k, v, acc => acc && lookup k y == Just v) True x

||| `x <+> y` is `merge x y`: the values of keys in both are combined
||| with `<+>`.
export
(Eq k, Semigroup v) => Semigroup (HashMap k v) where
  (<+>) = merge

||| The neutral element is the empty map.
export
(Eq k, Semigroup v) => Monoid (HashMap k v) where
  neutral = empty
