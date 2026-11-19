-- The default `foldMapListImpl` must not overflow the small stack of a
-- browser (or of the main thread of Node) on a million pieces, and must be
-- linear for monoids that wrap lists and strings, and snoc lists.
module MonoidDefault

import Data.SnocList

%default covering

n : Int
n = 1000000

ints : List Int
ints = [1 .. n]

record WList where
  constructor MkWList
  items : List Int

Semigroup WList where
  MkWList xs <+> MkWList ys = MkWList (xs ++ ys)

Monoid WList where
  neutral = MkWList []

record WSnoc where
  constructor MkWSnoc
  items : SnocList Int

Semigroup WSnoc where
  MkWSnoc xs <+> MkWSnoc ys = MkWSnoc (xs ++ ys)

Monoid WSnoc where
  neutral = MkWSnoc [<]

record Log where
  constructor MkLog
  count : Int
  text : String

Semigroup Log where
  MkLog c a <+> MkLog d b = MkLog (c + d) (a ++ b)

Monoid Log where
  neutral = MkLog 0 ""

record Sum where
  constructor MkSum
  value : Int

Semigroup Sum where
  MkSum a <+> MkSum b = MkSum ((a + b) `mod` 1000003)

Monoid Sum where
  neutral = MkSum 0

%noinline
gFoldMap : Monoid m => Foldable t => (a -> m) -> t a -> m
gFoldMap = foldMap

-- The sum of the list, to see the order and the length.
total' : List Int -> Int
total' = foldl (\h, x => (h * 31 + x) `mod` 1000003) 7

main : IO ()
main = do
  let w = (gFoldMap (\i => MkWList [i]) ints).items
  printLn (length w, total' w)
  let s = (gFoldMap (\i => MkWSnoc [<i, i]) ints).items <>> []
  printLn (length s, total' s)
  let l = gFoldMap (\i => MkLog 1 (show i)) ints
  printLn (l.count, length l.text)
  printLn (gFoldMap (\i => MkSum i) ints).value
  printLn (length (foldMap (\i => MkWList [i]) ([<] <>< ints)).items)
  printLn (or (map (\i => delay (i < 0)) ints), and (map (\i => delay (i > 0)) ints))
