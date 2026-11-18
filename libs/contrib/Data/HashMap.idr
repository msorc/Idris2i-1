||| Persistent hash maps: hash tries with collision buckets.
|||
||| A `HashMap k v` maps keys to values, for keys with a `Hashable` instance
||| (see `Data.Hashable`).  Compared to `Data.SortedMap`, no ordering of the
||| keys is needed, and lookup, insertion and deletion take time that depends
||| on the size of the map only through the depth of the trie, which is about
||| `log8 n` (at most 10) levels, instead of `log n` comparisons of keys.
||| The price is that the entries are not in key order: `toList`, `keys`,
||| `values` and the folds visit the entries in the order of the hashes of
||| the keys, which is deterministic, the same on every back end, but arbitrary.
||| The map does not store its size: `size` takes time in the number of entries
||| (as `length` of a `SortedMap` does), because keeping it would make every
||| insertion and deletion allocate a result for it, 25% slower.
|||
||| The map is a trie on the low 30 bits of the hash of the key, 3 bits per
||| level.  A node is empty, holds one entry, is a bucket of entries whose keys
||| have the same 30 bits of hash, or branches eight ways.  Updates copy the
||| nodes on the path from the root to the changed entry (and nothing else),
||| so old versions of a map stay valid.  Nodes are plain constructors with
||| eight fields rather than arrays of sub-tries: an implementation with 32-way
||| nodes in the immutable arrays of `Data.Linear.Array`, copied in bulk with
||| `thaw` and `copyInto`, takes 11500 instructions per insertion into a map of
||| 100000 `Int` keys with RefC and 7600 with Chez, against 1300 and 2700 for
||| this one, because every update allocates and fills a new array for each
||| level, with a reference count update for each element on RefC (lookups
||| cost about the same with both, 1700 instructions with RefC).
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
trieKey k = prim__and_Int (cast (hash k)) 0x3fffffff

-- The bits of the rest of the trie key that select a child.  The rest of a
-- trie key at a level is the key shifted right by the bits of each level above it.
%inline
chunk : Int -> Int
chunk rest = prim__and_Int rest 7

-- The rest of the trie key for the level below.
%inline
below : Int -> Int
below rest = prim__shr_Int rest 3

-- The rest of the trie key for the level above, for the child at a place.
%inline
above : Int -> Int -> Int
above rest place = prim__or_Int (prim__shl_Int rest 3) place

-- A node whose index is the number of levels of branches that may still be
-- below it.  A node of index Z can only be empty, an entry or a bucket, so
-- all the recursions on nodes are structural on the index and the code needs
-- neither fuel nor assert_total.
--
-- A leaf or a bucket has the rest of the trie key of its entries, for the
-- level where it is: a path from the root to it has used up the other bits,
-- so that two entries are in the same leaf or bucket if their rests are the
-- same, and the full key is not needed.  (At the last level, index Z, the rest
-- is always 0.)
data Node : Nat -> Type -> Type -> Type where
  -- No entries.  Children of a branch are Empty where there is nothing.
  Empty : Node n k v
  -- One entry.
  Leaf : (rest : Int) -> (key : k) -> (val : v) -> Node n k v
  -- Several entries with the same trie key, in no particular order.
  Bucket : (rest : Int) -> List (k, v) -> Node n k v
  -- A branch with the children for the chunks 0 to 7.
  Branch : (c0, c1, c2, c3, c4, c5, c6, c7 : Node n k v) -> Node (S n) k v

-- 30 bits of trie key at 3 bits per level.
public export
Levels : Nat
Levels = 10

-- The index of a node as a value that is there at run time, for the functions
-- that must tell Z from S: it is a chain of constructors, which is cheaper than
-- arithmetic on Nat (a big number on some back ends).  (Putting the shift of
-- each level in the chain, to avoid passing it, was slower.)
data Level : Nat -> Type where
  LZ : Level Z
  LS : Level n -> Level (S n)

topLevel : Level Levels
topLevel = LS (LS (LS (LS (LS (LS (LS (LS (LS (LS LZ)))))))))

||| A persistent map from keys to values, with hashing.
export
data HashMap : Type -> Type -> Type where
  MkHashMap : Node Levels k v -> HashMap k v

--------------------------------------------------------------------------------
-- Lookup
--------------------------------------------------------------------------------

%spec eq
findEntry : {auto eq : Eq k} -> k -> List (k, v) -> Maybe v
findEntry _ [] = Nothing
findEntry k ((k', v) :: es) = if k == k' then Just v else findEntry k es

%spec eq
lookupAt : {auto eq : Eq k} -> (0 lvl : Nat) -> (rest : Int) -> k ->
           Node lvl k v -> Maybe v
lookupAt _ _ _ Empty = Nothing
lookupAt _ rest k (Leaf rest' k' v) =
  if rest == rest' && k == k' then Just v else Nothing
lookupAt _ rest k (Bucket rest' es) =
  if rest == rest' then findEntry k es else Nothing
lookupAt (S m) rest k (Branch c0 c1 c2 c3 c4 c5 c6 c7) =
  case chunk rest of
    0 => lookupAt m (below rest) k c0
    1 => lookupAt m (below rest) k c1
    2 => lookupAt m (below rest) k c2
    3 => lookupAt m (below rest) k c3
    4 => lookupAt m (below rest) k c4
    5 => lookupAt m (below rest) k c5
    6 => lookupAt m (below rest) k c6
    _ => lookupAt m (below rest) k c7

--------------------------------------------------------------------------------
-- Insertion
--------------------------------------------------------------------------------

-- A node for entries that all have the same rest of the trie key.
fromEntries : Int -> List (k, v) -> Node n k v
fromEntries _ [] = Empty
fromEntries rest [(k, v)] = Leaf rest k v
fromEntries rest es = Bucket rest es

-- A branch with one child.
single : Int -> Node n k v -> Node (S n) k v
single 0 x = Branch x Empty Empty Empty Empty Empty Empty Empty
single 1 x = Branch Empty x Empty Empty Empty Empty Empty Empty
single 2 x = Branch Empty Empty x Empty Empty Empty Empty Empty
single 3 x = Branch Empty Empty Empty x Empty Empty Empty Empty
single 4 x = Branch Empty Empty Empty Empty x Empty Empty Empty
single 5 x = Branch Empty Empty Empty Empty Empty x Empty Empty
single 6 x = Branch Empty Empty Empty Empty Empty Empty x Empty
single _ x = Branch Empty Empty Empty Empty Empty Empty Empty x

-- Put a child into an empty slot of a branch.
fill : Int -> Node n k v -> Node (S n) k v -> Node (S n) k v
fill 0 x (Branch _ c1 c2 c3 c4 c5 c6 c7) = Branch x c1 c2 c3 c4 c5 c6 c7
fill 1 x (Branch c0 _ c2 c3 c4 c5 c6 c7) = Branch c0 x c2 c3 c4 c5 c6 c7
fill 2 x (Branch c0 c1 _ c3 c4 c5 c6 c7) = Branch c0 c1 x c3 c4 c5 c6 c7
fill 3 x (Branch c0 c1 c2 _ c4 c5 c6 c7) = Branch c0 c1 c2 x c4 c5 c6 c7
fill 4 x (Branch c0 c1 c2 c3 _ c5 c6 c7) = Branch c0 c1 c2 c3 x c5 c6 c7
fill 5 x (Branch c0 c1 c2 c3 c4 _ c6 c7) = Branch c0 c1 c2 c3 c4 x c6 c7
fill 6 x (Branch c0 c1 c2 c3 c4 c5 _ c7) = Branch c0 c1 c2 c3 c4 c5 x c7
fill _ x (Branch c0 c1 c2 c3 c4 c5 c6 _) = Branch c0 c1 c2 c3 c4 c5 c6 x
fill _ _ other = other -- cannot happen: only called on branches

-- Put two groups of entries with different rests of the trie key into a node at
-- some level.  At the last level (index Z) all the entries go into one bucket
-- (the rests are 0 there, so this is not reached for different rests).
merge2 : Level lvl -> (ra : Int) -> List (k, v) -> (rb : Int) -> List (k, v) ->
         Node lvl k v
merge2 LZ ra as _ bs = Bucket ra (as ++ bs)
merge2 (LS m) ra as rb bs =
  let ca = chunk ra
      cb = chunk rb
  in if ca == cb
        then single ca (merge2 m (below ra) as (below rb) bs)
        else fill cb (fromEntries (below rb) bs) (single ca (fromEntries (below ra) as))

-- Add or combine an entry in a bucket.
%spec eq
insertBucket : {auto eq : Eq k} -> (v -> v -> v) -> k -> v -> List (k, v) ->
               List (k, v)
insertBucket f k v [] = [(k, v)]
insertBucket f k v (e@(k', v') :: es) =
  if k == k' then (k, f v v') :: es else e :: insertBucket f k v es

-- Insert, combining with `f new old` if the key is present.
%spec eq
insertAt : {auto eq : Eq k} -> (0 lvl : Nat) -> Level lvl -> (rest : Int) ->
           (v -> v -> v) -> k -> v -> Node lvl k v -> Node lvl k v
insertAt _ _ rest _ k v Empty = Leaf rest k v
insertAt _ lvl rest f k v (Leaf rest' k' v') =
  if rest == rest'
     then if k == k'
             then Leaf rest k (f v v')
             else Bucket rest [(k, v), (k', v')]
     else merge2 lvl rest [(k, v)] rest' [(k', v')]
insertAt _ lvl rest f k v (Bucket rest' es) =
  if rest == rest'
     then Bucket rest (insertBucket f k v es)
     else merge2 lvl rest [(k, v)] rest' es
insertAt (S n) (LS m) rest f k v (Branch c0 c1 c2 c3 c4 c5 c6 c7) =
  case chunk rest of
    0 => Branch (insertAt n m (below rest) f k v c0) c1 c2 c3 c4 c5 c6 c7
    1 => Branch c0 (insertAt n m (below rest) f k v c1) c2 c3 c4 c5 c6 c7
    2 => Branch c0 c1 (insertAt n m (below rest) f k v c2) c3 c4 c5 c6 c7
    3 => Branch c0 c1 c2 (insertAt n m (below rest) f k v c3) c4 c5 c6 c7
    4 => Branch c0 c1 c2 c3 (insertAt n m (below rest) f k v c4) c5 c6 c7
    5 => Branch c0 c1 c2 c3 c4 (insertAt n m (below rest) f k v c5) c6 c7
    6 => Branch c0 c1 c2 c3 c4 c5 (insertAt n m (below rest) f k v c6) c7
    _ => Branch c0 c1 c2 c3 c4 c5 c6 (insertAt n m (below rest) f k v c7)

--------------------------------------------------------------------------------
-- Deletion
--------------------------------------------------------------------------------

%spec eq
deleteBucket : {auto eq : Eq k} -> k -> List (k, v) -> Maybe (List (k, v))
deleteBucket _ [] = Nothing
deleteBucket k (e@(k', v') :: es) =
  if k == k' then Just es else map (e ::) (deleteBucket k es)

-- A branch that has only a leaf or a bucket as a child is replaced by that
-- child, which goes up a level (its rest gets the place that it had); this keeps
-- the trie in the same shape whatever the order of the operations that led to
-- it.  (The clauses are written out so that the match is a few switches on the
-- constructors, without allocation.)
tidy : (c0, c1, c2, c3, c4, c5, c6, c7 : Node n k v) -> Node (S n) k v
tidy Empty Empty Empty Empty Empty Empty Empty Empty = Empty
tidy (Leaf r k v) Empty Empty Empty Empty Empty Empty Empty = Leaf (above r 0) k v
tidy (Bucket r es) Empty Empty Empty Empty Empty Empty Empty = Bucket (above r 0) es
tidy Empty (Leaf r k v) Empty Empty Empty Empty Empty Empty = Leaf (above r 1) k v
tidy Empty (Bucket r es) Empty Empty Empty Empty Empty Empty = Bucket (above r 1) es
tidy Empty Empty (Leaf r k v) Empty Empty Empty Empty Empty = Leaf (above r 2) k v
tidy Empty Empty (Bucket r es) Empty Empty Empty Empty Empty = Bucket (above r 2) es
tidy Empty Empty Empty (Leaf r k v) Empty Empty Empty Empty = Leaf (above r 3) k v
tidy Empty Empty Empty (Bucket r es) Empty Empty Empty Empty = Bucket (above r 3) es
tidy Empty Empty Empty Empty (Leaf r k v) Empty Empty Empty = Leaf (above r 4) k v
tidy Empty Empty Empty Empty (Bucket r es) Empty Empty Empty = Bucket (above r 4) es
tidy Empty Empty Empty Empty Empty (Leaf r k v) Empty Empty = Leaf (above r 5) k v
tidy Empty Empty Empty Empty Empty (Bucket r es) Empty Empty = Bucket (above r 5) es
tidy Empty Empty Empty Empty Empty Empty (Leaf r k v) Empty = Leaf (above r 6) k v
tidy Empty Empty Empty Empty Empty Empty (Bucket r es) Empty = Bucket (above r 6) es
tidy Empty Empty Empty Empty Empty Empty Empty (Leaf r k v) = Leaf (above r 7) k v
tidy Empty Empty Empty Empty Empty Empty Empty (Bucket r es) = Bucket (above r 7) es
tidy c0 c1 c2 c3 c4 c5 c6 c7 = Branch c0 c1 c2 c3 c4 c5 c6 c7

-- The branch above a child that has changed by a deletion, one function for
-- each of the places of the child.  If the child is a branch the branch above
-- it has not become simpler; otherwise it may have.
settle0 : Node n k v -> (c1, c2, c3, c4, c5, c6, c7 : Node n k v) -> Node (S n) k v
settle0 c@(Branch _ _ _ _ _ _ _ _) c1 c2 c3 c4 c5 c6 c7 = Branch c c1 c2 c3 c4 c5 c6 c7
settle0 c c1 c2 c3 c4 c5 c6 c7 = tidy c c1 c2 c3 c4 c5 c6 c7

settle1 : (c0 : Node n k v) -> Node n k v -> (c2, c3, c4, c5, c6, c7 : Node n k v) -> Node (S n) k v
settle1 c0 c@(Branch _ _ _ _ _ _ _ _) c2 c3 c4 c5 c6 c7 = Branch c0 c c2 c3 c4 c5 c6 c7
settle1 c0 c c2 c3 c4 c5 c6 c7 = tidy c0 c c2 c3 c4 c5 c6 c7

settle2 : (c0, c1 : Node n k v) -> Node n k v -> (c3, c4, c5, c6, c7 : Node n k v) -> Node (S n) k v
settle2 c0 c1 c@(Branch _ _ _ _ _ _ _ _) c3 c4 c5 c6 c7 = Branch c0 c1 c c3 c4 c5 c6 c7
settle2 c0 c1 c c3 c4 c5 c6 c7 = tidy c0 c1 c c3 c4 c5 c6 c7

settle3 : (c0, c1, c2 : Node n k v) -> Node n k v -> (c4, c5, c6, c7 : Node n k v) -> Node (S n) k v
settle3 c0 c1 c2 c@(Branch _ _ _ _ _ _ _ _) c4 c5 c6 c7 = Branch c0 c1 c2 c c4 c5 c6 c7
settle3 c0 c1 c2 c c4 c5 c6 c7 = tidy c0 c1 c2 c c4 c5 c6 c7

settle4 : (c0, c1, c2, c3 : Node n k v) -> Node n k v -> (c5, c6, c7 : Node n k v) -> Node (S n) k v
settle4 c0 c1 c2 c3 c@(Branch _ _ _ _ _ _ _ _) c5 c6 c7 = Branch c0 c1 c2 c3 c c5 c6 c7
settle4 c0 c1 c2 c3 c c5 c6 c7 = tidy c0 c1 c2 c3 c c5 c6 c7

settle5 : (c0, c1, c2, c3, c4 : Node n k v) -> Node n k v -> (c6, c7 : Node n k v) -> Node (S n) k v
settle5 c0 c1 c2 c3 c4 c@(Branch _ _ _ _ _ _ _ _) c6 c7 = Branch c0 c1 c2 c3 c4 c c6 c7
settle5 c0 c1 c2 c3 c4 c c6 c7 = tidy c0 c1 c2 c3 c4 c c6 c7

settle6 : (c0, c1, c2, c3, c4, c5 : Node n k v) -> Node n k v -> (c7 : Node n k v) -> Node (S n) k v
settle6 c0 c1 c2 c3 c4 c5 c@(Branch _ _ _ _ _ _ _ _) c7 = Branch c0 c1 c2 c3 c4 c5 c c7
settle6 c0 c1 c2 c3 c4 c5 c c7 = tidy c0 c1 c2 c3 c4 c5 c c7

settle7 : (c0, c1, c2, c3, c4, c5, c6 : Node n k v) -> Node n k v -> Node (S n) k v
settle7 c0 c1 c2 c3 c4 c5 c6 c@(Branch _ _ _ _ _ _ _ _) = Branch c0 c1 c2 c3 c4 c5 c6 c
settle7 c0 c1 c2 c3 c4 c5 c6 c = tidy c0 c1 c2 c3 c4 c5 c6 c

-- Delete a key.  (If the key is not in the node, the result is the same node,
-- rebuilt.  The alternative, to give a sign of that and keep the node, would
-- make the caller keep the node too, and the nodes of the path could not be
-- reused in place: deleting would copy the path.)
%spec eq
deleteAt : {auto eq : Eq k} -> (0 lvl : Nat) -> (rest : Int) -> k ->
           Node lvl k v -> Node lvl k v
deleteAt _ _ _ Empty = Empty
deleteAt _ rest k (Leaf rest' k' v) =
  if rest == rest' && k == k' then Empty else Leaf rest' k' v
deleteAt _ rest k (Bucket rest' es) =
  if rest == rest'
     then case deleteBucket k es of
            Nothing => Bucket rest' es
            Just es' => fromEntries rest es'
     else Bucket rest' es
deleteAt (S n) rest k (Branch c0 c1 c2 c3 c4 c5 c6 c7) =
  case chunk rest of
    0 => settle0 (deleteAt n (below rest) k c0) c1 c2 c3 c4 c5 c6 c7
    1 => settle1 c0 (deleteAt n (below rest) k c1) c2 c3 c4 c5 c6 c7
    2 => settle2 c0 c1 (deleteAt n (below rest) k c2) c3 c4 c5 c6 c7
    3 => settle3 c0 c1 c2 (deleteAt n (below rest) k c3) c4 c5 c6 c7
    4 => settle4 c0 c1 c2 c3 (deleteAt n (below rest) k c4) c5 c6 c7
    5 => settle5 c0 c1 c2 c3 c4 (deleteAt n (below rest) k c5) c6 c7
    6 => settle6 c0 c1 c2 c3 c4 c5 (deleteAt n (below rest) k c6) c7
    _ => settle7 c0 c1 c2 c3 c4 c5 c6 (deleteAt n (below rest) k c7)

--------------------------------------------------------------------------------
-- Folds and maps
--------------------------------------------------------------------------------

foldrNode : (0 lvl : Nat) -> (k -> v -> b -> b) -> b -> Node lvl k v -> b
foldrNode _ f z Empty = z
foldrNode _ f z (Leaf _ k v) = f k v z
foldrNode _ f z (Bucket _ es) = foldr (\(k, v), acc => f k v acc) z es
foldrNode (S m) f z (Branch c0 c1 c2 c3 c4 c5 c6 c7) =
  foldrNode m f (foldrNode m f (foldrNode m f (foldrNode m f (foldrNode m f (foldrNode m f (foldrNode m f (foldrNode m f z c7) c6) c5) c4) c3) c2) c1) c0

foldlNode : (0 lvl : Nat) -> (b -> k -> v -> b) -> b -> Node lvl k v -> b
foldlNode _ f z Empty = z
foldlNode _ f z (Leaf _ k v) = f z k v
foldlNode _ f z (Bucket _ es) = foldl (\acc, (k, v) => f acc k v) z es
foldlNode (S m) f z (Branch c0 c1 c2 c3 c4 c5 c6 c7) =
  foldlNode m f (foldlNode m f (foldlNode m f (foldlNode m f (foldlNode m f (foldlNode m f (foldlNode m f (foldlNode m f z c0) c1) c2) c3) c4) c5) c6) c7

mapNode : (0 lvl : Nat) -> (k -> v -> w) -> Node lvl k v -> Node lvl k w
mapNode _ f Empty = Empty
mapNode _ f (Leaf rest k v) = Leaf rest k (f k v)
mapNode _ f (Bucket rest es) = Bucket rest (map (\(k, v) => (k, f k v)) es)
mapNode (S m) f (Branch c0 c1 c2 c3 c4 c5 c6 c7) =
  Branch (mapNode m f c0) (mapNode m f c1) (mapNode m f c2) (mapNode m f c3) (mapNode m f c4) (mapNode m f c5) (mapNode m f c6) (mapNode m f c7)

traverseNode : Applicative f => (0 lvl : Nat) -> (k -> v -> f w) ->
               Node lvl k v -> f (Node lvl k w)
traverseNode _ g Empty = pure Empty
traverseNode _ g (Leaf rest k v) = Leaf rest k <$> g k v
traverseNode _ g (Bucket rest es) =
  Bucket rest <$> traverse (\(k, v) => (\w => (k, w)) <$> g k v) es
traverseNode (S m) g (Branch c0 c1 c2 c3 c4 c5 c6 c7) =
  Branch <$> traverseNode m g c0 <*> traverseNode m g c1 <*> traverseNode m g c2 <*> traverseNode m g c3 <*> traverseNode m g c4 <*> traverseNode m g c5 <*> traverseNode m g c6 <*> traverseNode m g c7

isEmpty : Node n k v -> Bool
isEmpty Empty = True
isEmpty _ = False

-- Keep the entries for which a predicate holds.
filterNode : (0 lvl : Nat) -> (k -> v -> Bool) -> Node lvl k v -> Node lvl k v
filterNode _ p Empty = Empty
filterNode _ p (Leaf rest k v) = if p k v then Leaf rest k v else Empty
filterNode _ p (Bucket rest es) = fromEntries rest (filter (\(k, v) => p k v) es)
filterNode (S m) p (Branch c0 c1 c2 c3 c4 c5 c6 c7) =
  tidy (filterNode m p c0) (filterNode m p c1) (filterNode m p c2) (filterNode m p c3) (filterNode m p c4) (filterNode m p c5) (filterNode m p c6) (filterNode m p c7)

--------------------------------------------------------------------------------
-- Construction and queries
--------------------------------------------------------------------------------

||| The map with no entries.
export
empty : HashMap k v
empty = MkHashMap Empty

||| The map with one entry.
export
%spec h
singleton : {auto h : Hashable k} -> k -> v -> HashMap k v
singleton k v = MkHashMap (Leaf (trieKey k) k v)

||| Looks up the value of a key.
export
%spec h
lookup : {auto h : Hashable k} -> k -> HashMap k v -> Maybe v
lookup k (MkHashMap root) = lookupAt Levels (trieKey k) k root

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
%spec h
insert : {auto h : Hashable k} -> k -> v -> HashMap k v -> HashMap k v
insert k v (MkHashMap root) =
  MkHashMap (insertAt Levels topLevel (trieKey k) (\new, _ => new) k v root)

||| Inserts a key and a value and, if the key is in the map, stores
||| `f new old` instead; like `Data.SortedMap.insertWith`.
export
%spec h
insertWith : {auto h : Hashable k} -> (v -> v -> v) -> k -> v -> HashMap k v -> HashMap k v
insertWith f k v (MkHashMap root) =
  MkHashMap (insertAt Levels topLevel (trieKey k) f k v root)

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
%spec h
delete : {auto h : Hashable k} -> k -> HashMap k v -> HashMap k v
delete k (MkHashMap root) = MkHashMap (deleteAt Levels (trieKey k) k root)

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
foldrWithKey f z (MkHashMap root) = foldrNode Levels f z root

||| Left fold over the entries, in the order of the hashes of the keys.
export
foldlWithKey : (b -> k -> v -> b) -> b -> HashMap k v -> b
foldlWithKey f z (MkHashMap root) = foldlNode Levels f z root

||| The number of entries.  The map does not store it: this takes time in the
||| size of the map (as `length` of a `SortedMap` does), which is what made
||| an insertion with a count of the entries 25% slower.
export
size : HashMap k v -> Nat
size = foldlWithKey (\n, _, _ => S n) 0

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
mapWithKey f (MkHashMap root) = MkHashMap (mapNode Levels f root)

||| Keeps the entries for which the predicate holds.
export
filterWithKey : (k -> v -> Bool) -> HashMap k v -> HashMap k v
filterWithKey p (MkHashMap root) = MkHashMap (filterNode Levels p root)

||| Keeps the entries whose values satisfy the predicate.
export
filter : (v -> Bool) -> HashMap k v -> HashMap k v
filter p = filterWithKey (\_, v => p v)

||| Merges two maps.  When a key is in both, the new value is `f x y`, where
||| `x` is the value in the first map and `y` the one in the second.
export
mergeWith : Hashable k => (v -> v -> v) -> HashMap k v -> HashMap k v -> HashMap k v
mergeWith f x y =
  foldlWithKey (\acc, k, v => insertWith (\new, old => f old new) k v acc) x y

||| Merges two maps, combining the values of keys that are in both with the
||| `Semigroup` operation, the value of the first map on the left.
export
merge : (Hashable k, Semigroup v) => HashMap k v -> HashMap k v -> HashMap k v
merge = mergeWith (<+>)

||| Left-biased merge: the value of the first map wins.
export
mergeLeft : Hashable k => HashMap k v -> HashMap k v -> HashMap k v
mergeLeft = mergeWith const

||| The union of two maps; for keys in both, the value of the first map is kept.
export
union : Hashable k => HashMap k v -> HashMap k v -> HashMap k v
union = mergeLeft

||| The union of two maps, combining the values of keys in both by `f`,
||| the same as `mergeWith`.
export
unionWith : Hashable k => (v -> v -> v) -> HashMap k v -> HashMap k v -> HashMap k v
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
  null (MkHashMap root) = isEmpty root
  toList = values
  foldMap f = foldrWithKey (\_, v, acc => f v <+> acc) neutral

||| Traverses the values, in the order of the hashes of their keys.
export
Traversable (HashMap k) where
  traverse f (MkHashMap root) =
    MkHashMap <$> traverseNode Levels (\_ => f) root

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
(Hashable k, Semigroup v) => Semigroup (HashMap k v) where
  (<+>) = merge

||| The neutral element is the empty map.
export
(Hashable k, Semigroup v) => Monoid (HashMap k v) where
  neutral = empty
