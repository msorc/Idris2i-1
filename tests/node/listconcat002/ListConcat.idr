module ListConcat

import Data.List1
import Data.SnocList

-- `concat`, `concatMap` and `foldMap` over long lists must not overflow the
-- small stack of a browser (or of the main thread of Node), and must be
-- linear for `List` and `String`, however they are called.

n : Int
n = 100000

ints : List Int
ints = [1 .. n]

%noinline
gFoldMap : Monoid m => Foldable t => (a -> m) -> t a -> m
gFoldMap = foldMap

%noinline
app : (a -> b) -> a -> b
app f x = f x

main : IO ()
main = do
  printLn (length (concatMap (\i => [i, i]) ints))
  printLn (length (gFoldMap (\i => [i, i]) ints))
  printLn (length (app concat (map (\i => [i, i]) ints)))
  printLn (length (concatMap show ints))
  printLn (length (gFoldMap show ints))
  printLn (length (app concat (map show ints)))
  printLn (length (gFoldMap (\i => [<i, i]) ints <>> []))
  printLn (length (foldMap (\i => [i]) ([<] <>< ints)))
  printLn (length (foldMap show ([<] <>< ints)))
  printLn (length (foldMap (\i => [i]) (1 ::: ints)))
  printLn (the Integer (gFoldMap @{Additive} (cast {to = Integer}) ints))
  printLn (any (> n) ints, all (> 0) ints)
