-- `concat`, `concatMap` and `foldMap` over lists must take time linear in the
-- size of the result for the monoids that copy their left argument (`List`,
-- `String`) however they are called: with the types known, through a
-- function with `Foldable` and `Monoid` constraints, partially applied.  With
-- a left fold the sizes here take minutes.  Stack depth must not be a limit
-- either.
module ListConcat

import Data.List1
import Data.SnocList
import Data.String
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
gConcat : Monoid m => Foldable t => t m -> m
gConcat = concat

%noinline
gFoldMap : Monoid m => Foldable t => (a -> m) -> t a -> m
gFoldMap = foldMap

%noinline
gConcatMap : Monoid m => Foldable t => (a -> m) -> t a -> m
gConcatMap = concatMap

%noinline
app1 : (a -> b) -> a -> b
app1 f x = f x

%noinline
app2 : (a -> b -> c) -> a -> b -> c
app2 f x y = f x y

-- A monoid that records the order in which the pieces are combined, to
-- see that the result is the same for every way of folding.  It has the
-- default `foldMapListImpl`, which combines the pieces in a balanced way.
record Trace where
  constructor MkTrace
  items : List Int

Semigroup Trace where
  MkTrace xs <+> MkTrace ys = MkTrace (xs ++ ys)

Monoid Trace where
  neutral = MkTrace []

-- A monoid that depends on the order of the pieces (a rolling hash, with
-- the power of 31 that goes with it to make it associative, and a modulus
-- whose square fits in the 32 bits of `Int` with JavaScript), with the
-- default `foldMapListImpl`.
record Count where
  constructor MkCount
  n : Int
  h : Int
  p : Int

Semigroup Count where
  MkCount a b c <+> MkCount d e f =
    MkCount (a + d) ((b * f + e) `mod` 32003) ((c * f) `mod` 32003)

Monoid Count where
  neutral = MkCount 0 0 1

pieceL : Int -> List Int
pieceL i = [i, i + 1]

pieceS : Int -> String
pieceS i = show i ++ ","

pieceSn : Int -> SnocList Int
pieceSn i = [<i, i + 1]

showL : String -> List Int -> IO ()
showL name xs = putStrLn (name ++ ": " ++ show (length xs) ++ " " ++ show (hash xs))

showS : String -> String -> IO ()
showS name s = putStrLn (name ++ ": " ++ show (length s) ++ " " ++ show (shash s))

showSn : String -> SnocList Int -> IO ()
showSn name xs = showL name (xs <>> [])

main : IO ()
main = do
  let n = 200000
  let ints = nums n

  putStrLn "-- List monoid"
  showL "concat" (concat (map pieceL ints))
  showL "concat gen" (gConcat (map pieceL ints))
  showL "concat par" (app1 concat (map pieceL ints))
  showL "concatMap" (concatMap pieceL ints)
  showL "concatMap gen" (gConcatMap pieceL ints)
  showL "concatMap par" (app2 concatMap pieceL ints)
  showL "foldMap" (foldMap pieceL ints)
  showL "foldMap gen" (gFoldMap pieceL ints)
  showL "foldMap par" (app2 foldMap pieceL ints)

  putStrLn "-- String monoid"
  showS "concat" (concat (map pieceS ints))
  showS "concat gen" (gConcat (map pieceS ints))
  showS "concat par" (app1 concat (map pieceS ints))
  showS "concatMap" (concatMap pieceS ints)
  showS "concatMap gen" (gConcatMap pieceS ints)
  showS "concatMap par" (app2 concatMap pieceS ints)
  showS "foldMap" (foldMap pieceS ints)
  showS "foldMap gen" (gFoldMap pieceS ints)
  showS "foldMap par" (app2 foldMap pieceS ints)
  showS "joinBy" (joinBy ";" (map pieceS ints))
  showS "unwords" (unwords (map pieceS ints))
  showS "unlines" (unlines (map pieceS ints))
  showS "fastConcat" (fastConcat (map pieceS ints))

  putStrLn "-- SnocList monoid"
  showSn "concat" (concat (map pieceSn ints))
  showSn "concat gen" (gConcat (map pieceSn ints))
  showSn "concat par" (app1 concat (map pieceSn ints))
  showSn "concatMap" (concatMap pieceSn ints)
  showSn "concatMap gen" (gConcatMap pieceSn ints)
  showSn "foldMap par" (app2 foldMap pieceSn ints)

  putStrLn "-- Additive Integer"
  let bigs = map (cast {to = Integer}) ints
  putStrLn $ show (concat @{Additive} (map (* 2) bigs))
  putStrLn $ show (gConcat @{Additive} (map (* 2) bigs))
  putStrLn $ show (sum bigs) ++ " " ++ show (product (nums 10))
  putStrLn $ show (foldMap @{%search} @{Additive} (* 3) bigs)

  putStrLn "-- Other monoids"
  let tr = foldMap (\i => MkTrace [i]) ints
  showL "Trace" tr.items
  showL "Trace gen" (gFoldMap (\i => MkTrace [i]) ints).items
  let ct = foldMap (\i => MkCount 1 i 31) ints
  putStrLn $ "Count: " ++ show ct.n ++ " " ++ show ct.h
  let (a, b) = foldMap (\i => (the (List Int) [i], pieceS i)) (nums 1000)
  putStrLn $ show (hash a) ++ " " ++ show (shash b)
  putStrLn $ show (foldMap (\i => if i > 5 then Just i else Nothing) ints)
  putStrLn $ show (concat (the (List Ordering) [LT, EQ, GT])) ++ " " ++ show (concat (the (List Ordering) []))
  putStrLn $ show (concat (the (List String) [])) ++ show (concat (the (List (List Int)) []))

  putStrLn "-- Other Foldables"
  showL "List1" (foldMap pieceL (1 ::: ints))
  showS "List1 String" (foldMap pieceS (1 ::: ints))
  showL "SnocList" (foldMap pieceL ([<] <>< ints))
  showS "SnocList String" (foldMap pieceS ([<] <>< ints))
  showSn "SnocList SnocList" (foldMap pieceSn ([<] <>< ints))
  showL "Vect" (foldMap pieceL (fromList (nums 50000)))
  showS "Vect String" (foldMap pieceS (fromList (nums 50000)))
  putStrLn $ show (foldMap (\i => the (List Int) [i, i]) (Just 3))
  putStrLn $ show (foldMap pieceS (the (Maybe Int) Nothing))
  putStrLn "-- Small"
  putStrLn $ show (concat (the (List (List Int)) [[1,2],[3],[],[4,5]]))
  putStrLn $ show (Prelude.concat (the (List String) ["a", "b", "", "c"]))
  putStrLn $ show (concatMap show (the (List Int) [1, 2, 3]))
  putStrLn $ show (foldMap (\x => the (List Int) [x, x * 10]) (the (List Int) [1, 2, 3]))
  putStrLn $ show (concat (the (List (SnocList Int)) [[<1,2],[<3],[<],[<4,5]]) <>> [])
  putStrLn $ show (foldMap pieceS (the (Vect 3 Int) [1, 2, 3]))
  putStrLn $ show (foldMap pieceL (the (Vect 3 Int) [1, 2, 3]))
  putStrLn $ show (foldMap pieceL ([<] <>< the (List Int) [1, 2, 3]))
  putStrLn $ show (foldMap pieceS (1 ::: the (List Int) [2, 3]))
