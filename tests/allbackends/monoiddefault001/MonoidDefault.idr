-- The default `foldMapListImpl` (so `foldMap`, `concat` and `concatMap` over
-- a list) combines the pieces in a balanced way: a monoid that wraps a list
-- or a string, which copies its left argument, and one that wraps a snoc
-- list, which copies its right argument, both take time linear (up to a
-- logarithm) in the size of the result.  With a left fold the sizes here
-- take minutes, or hours.  The order of the operands must be kept, and the
-- stack depth must not be a limit.
module MonoidDefault

import Data.List1
import Data.SnocList
import Data.Vect

%default covering

nums : Int -> List Int
nums n = go n []
  where
    go : Int -> List Int -> List Int
    go 0 acc = acc
    go k acc = go (k - 1) (k :: acc)

-- A hash of the list in order, so that an order change shows.
hash : List Int -> Int
hash = foldl (\h, x => (h * 31 + x) `mod` 1000003) 7

shash : String -> Int
shash = hash . map ord . unpack

%noinline
gFoldMap : Monoid m => Foldable t => (a -> m) -> t a -> m
gFoldMap = foldMap

%noinline
gConcat : Monoid m => Foldable t => t m -> m
gConcat = concat

-- All of these have the default `foldMapListImpl`.

-- A newtype over a list.
record WList where
  constructor MkWList
  items : List Int

Semigroup WList where
  MkWList xs <+> MkWList ys = MkWList (xs ++ ys)

Monoid WList where
  neutral = MkWList []

-- A newtype over a snoc list, which costs in its right argument.
record WSnoc where
  constructor MkWSnoc
  items : SnocList Int

Semigroup WSnoc where
  MkWSnoc xs <+> MkWSnoc ys = MkWSnoc (xs ++ ys)

Monoid WSnoc where
  neutral = MkWSnoc [<]

-- A record with a string field.
record Log where
  constructor MkLog
  count : Int
  text : String

Semigroup Log where
  MkLog c a <+> MkLog d b = MkLog (c + d) (a ++ b)

Monoid Log where
  neutral = MkLog 0 ""

-- A pair of lists, with a tuple monoid.
record Two where
  constructor MkTwo
  xs : List Int
  ys : List String

Semigroup Two where
  MkTwo a b <+> MkTwo c d = MkTwo (a ++ c) (b ++ d)

Monoid Two where
  neutral = MkTwo [] []

-- A document with a tree inside, as a pretty printer has.
data Doc = Empty | Text String | Cat Doc Doc

Semigroup Doc where
  Empty <+> d = d
  d <+> Empty = d
  d <+> e = Cat d e

Monoid Doc where
  neutral = Empty

render : Doc -> String
render d = fastConcat (go [d] [])
  where
    go : List Doc -> List String -> List String
    go [] acc = reverse acc
    go (Empty :: ds) acc = go ds acc
    go (Text s :: ds) acc = go ds (s :: acc)
    go (Cat a b :: ds) acc = go (a :: b :: ds) acc

-- Not commutative, and cheap: the composition of the affine maps
-- `x => a * x + b` modulo a prime (whose square fits in the 32 bits of `Int`
-- with JavaScript), the one on the right applied first.
record Aff where
  constructor MkAff
  a : Int
  b : Int

Semigroup Aff where
  MkAff a b <+> MkAff c d = MkAff ((a * c) `mod` 32003) ((a * d + b) `mod` 32003)

Monoid Aff where
  neutral = MkAff 1 0

-- A monoid that shows how it was combined (it does not follow the laws).  The
-- nesting is not promised, this is only here to see what it is: a left fold
-- up to 16 pieces, then balanced chunks of 16.
record Shape where
  constructor MkShape
  str : String

Semigroup Shape where
  MkShape a <+> MkShape b = MkShape ("(" ++ a ++ " " ++ b ++ ")")

Monoid Shape where
  neutral = MkShape "e"

showL : String -> List Int -> IO ()
showL name xs = putStrLn (name ++ ": " ++ show (length xs) ++ " " ++ show (hash xs))

showS : String -> String -> IO ()
showS name s = putStrLn (name ++ ": " ++ show (length s) ++ " " ++ show (shash s))

-- At compile time too: through the default method.
0 typeLevel1 : (concat (the (List WList) [])).items = []
typeLevel1 = Refl

0 typeLevel2 : (foldMap (\x => MkWList [x]) (the (List Int) [1, 2, 3, 4, 5, 6, 7])).items = [1, 2, 3, 4, 5, 6, 7]
typeLevel2 = Refl

0 typeLevel3 : (foldMap (\x => MkLog 1 x) (the (List String) ["a", "b", "c", "d", "e"])).text = "abcde"
typeLevel3 = Refl

0 typeLevel4 : foldMap @{%search} @{Additive} (\x => x) (the (List Nat) [1, 2, 3, 4, 5, 6]) = 21
typeLevel4 = Refl

0 typeLevel5 : (foldMap (\x => MkWList [x]) (the (List Int) [1 .. 40])).items = [1 .. 40]
typeLevel5 = Refl

main : IO ()
main = do
  let n = 200000
  let ints = nums n

  putStrLn "-- Wrapper of a list"
  showL "foldMap" (foldMap (\i => MkWList [i]) ints).items
  showL "foldMap gen" (gFoldMap (\i => MkWList [i, i + 1]) ints).items
  showL "concat gen" (gConcat (map (\i => MkWList [i, i + 1]) ints)).items
  showL "concatMap" (concatMap (\i => MkWList [i]) ints).items
  showL "List1" (foldMap (\i => MkWList [i]) (1 ::: ints)).items
  showL "SnocList" (foldMap (\i => MkWList [i]) ([<] <>< ints)).items
  showL "Vect" (foldMap (\i => MkWList [i]) (fromList (nums 50000))).items

  putStrLn "-- Wrapper of a snoc list"
  showL "foldMap" ((foldMap (\i => MkWSnoc [<i]) ints).items <>> [])
  showL "foldMap gen" ((gFoldMap (\i => MkWSnoc [<i, i + 1]) ints).items <>> [])

  putStrLn "-- Record with a string"
  let lg = foldMap (\i => MkLog 1 (show i ++ ",")) ints
  putStrLn $ show lg.count
  showS "foldMap" lg.text
  let lg' = gFoldMap (\i => MkLog 1 (show i ++ ",")) ints
  putStrLn $ show lg'.count
  showS "foldMap gen" lg'.text

  putStrLn "-- Pair of lists"
  let tw = foldMap (\i => MkTwo [i] [show i]) ints
  showL "xs" tw.xs
  showS "ys" (fastConcat tw.ys)
  let (a, b) = foldMap (\i => (MkWList [i], MkLog 1 (show i))) (nums 100000)
  showL "tuple" a.items
  showS "tuple" b.text

  putStrLn "-- Document"
  showS "doc" (render (foldMap (\i => Text (show i ++ ",")) ints))

  putStrLn "-- Order"
  let af = foldMap (\i => MkAff (i `mod` 1000 + 1) (i `mod` 1000)) ints
  putStrLn $ show af.a ++ " " ++ show af.b
  let af' = foldl (\acc, i => acc <+> MkAff (i `mod` 1000 + 1) (i `mod` 1000)) neutral ints
  putStrLn $ show af'.a ++ " " ++ show af'.b

  putStrLn "-- Lengths"
  for_ ([0 .. 20] ++ [33, 50]) $ \k =>
    putStrLn $ show k ++ " " ++ (foldMap (\i => MkShape (show i)) (nums k)).str
  putStrLn $ show (foldMap (\i => MkWList [i]) (nums 5)).items
  putStrLn $ show (foldMap (\i => MkWList [i]) (the (List Int) [])).items
  putStrLn $ show (foldMap (\i => MkWList [i]) (the (List Int) [7])).items
  let e = concat (the (List Aff) [])
  putStrLn $ show (e.a, e.b)
  putStrLn $ show (foldMap (\i => the (List Int, String) ([i], show i)) (nums 6))
  putStrLn $ show (foldMap (\i => if i > 5 then Just i else Nothing) ints)
  putStrLn $ show (foldMap (\i => if i > 5 then Nothing else Just i) ints)
  putStrLn $ show (foldMap (\i => the (Int -> List Int) (\x => [i + x])) (nums 5) 10)
  putStrLn $ show (concat (the (List Ordering) [EQ, EQ, GT, LT, LT, EQ, EQ]))

  -- The pieces are combined in a different nesting, but in the same order,
  -- so the short-circuiting of `and` and `or` stays (a piece that crashes
  -- is never looked at).
  putStrLn "-- Lazy"
  let crash = the (Lazy Bool) (delay (assert_total (idris_crash "forced")))
  putStrLn $ show (or (delay True :: replicate 100000 crash))
  putStrLn $ show (and (delay False :: replicate 100000 crash))
  putStrLn $ show (or (map (\i => delay (i == 100000)) ints ++ [crash]))
  putStrLn $ show (and (map (\i => delay (i /= 100000)) ints ++ [crash]))
  putStrLn $ show (or (map (\i => delay (i < 0)) ints), and (map (\i => delay (i > 0)) ints))
