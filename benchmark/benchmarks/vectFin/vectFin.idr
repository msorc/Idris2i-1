||| Vect and Fin operations, each beside its List or Int equivalent.
|||
||| Every line of the input is `CASE SIZE [REPEATS]`; the program runs the
||| cases in order and prints a checksum for each, so the output of two
||| builds can be compared.  The case names starting with `v` work on a
||| `Vect`, with `f` on a `Fin`, with `l` on a `List` and with `i` on an
||| `Int`: `vmap` is to be read beside `lmap`, `fplus` beside `iplus`, and
||| so on.  Running one line at a time measures one case.
module Main

import Data.Fin
import Data.List
import Data.String
import Data.Vect

%default covering

-- Inputs -------------------------------------------------------------------

mkVect : (n : Nat) -> Vect n Int
mkVect Z = []
mkVect (S k) = cast (S k) :: mkVect k

mkList : Nat -> List Int
mkList Z = []
mkList (S k) = cast (S k) :: mkList k

-- A Fin from a counter, in O(1): `restrict` is a `mod` on an Integer.
fin : (m : Nat) -> Nat -> Fin (S m)
fin m k = restrict m (natToInteger k)

sumV : Vect n Int -> Int
sumV = foldl (+) 0

sumL : List Int -> Int
sumL = foldl (+) 0

finSum : List (Fin n) -> Integer
finSum = foldl (\acc, x => acc + finToInteger x) 0

repeat : Nat -> (Nat -> Integer) -> Integer
repeat r f = go r 0
  where
    go : Nat -> Integer -> Integer
    go Z acc = acc
    go (S k) acc = go k (acc + f k)

lindex : Nat -> List Int -> Int
lindex _ [] = 0
lindex Z (x :: _) = x
lindex (S k) (_ :: xs) = lindex k xs

-- Cases --------------------------------------------------------------------

-- `index` at every position: O(n^2) for both.
vindex : Nat -> Nat -> Integer
vindex Z _ = 0
vindex (S m) r
    = let xs = mkVect (S m) in
          repeat r $ \j =>
            cast $ foldl (\acc, k => acc + index (fin m (k + j)) xs) 0 [0 .. m]

lindexC : Nat -> Nat -> Integer
lindexC n r
    = let xs = mkList n in
          repeat r $ \j =>
            cast $ foldl (\acc, k => acc + lindex ((k + j) `mod` n) xs) 0 [0 .. pred n]

vmap : Nat -> Nat -> Integer
vmap n r = let xs = mkVect n in
               repeat r $ \j => cast $ sumV (map (+ cast j) xs)

lmap : Nat -> Nat -> Integer
lmap n r = let xs = mkList n in
               repeat r $ \j => cast $ sumL (map (+ cast j) xs)

vzipWith : Nat -> Nat -> Integer
vzipWith n r = let xs = mkVect n in
                   repeat r $ \j => cast $ sumV (zipWith (\a, b => a * b + cast j) xs xs)

lzipWith : Nat -> Nat -> Integer
lzipWith n r = let xs = mkList n in
                   repeat r $ \j => cast $ sumL (zipWith (\a, b => a * b + cast j) xs xs)

vfoldl : Nat -> Nat -> Integer
vfoldl n r = let xs = mkVect n in
                 repeat r $ \j => cast $ foldl (\acc, x => acc + x * cast j) 0 xs

lfoldl : Nat -> Nat -> Integer
lfoldl n r = let xs = mkList n in
                 repeat r $ \j => cast $ foldl (\acc, x => acc + x * cast j) 0 xs

vfoldr : Nat -> Nat -> Integer
vfoldr n r = let xs = mkVect n in
                 repeat r $ \j => cast $ foldr (\x, acc => acc + x * cast j) 0 xs

lfoldr : Nat -> Nat -> Integer
lfoldr n r = let xs = mkList n in
                 repeat r $ \j => cast $ foldr (\x, acc => acc + x * cast j) 0 xs

vlength : Nat -> Nat -> Integer
vlength n r = let xs = mkVect n in
                  repeat r $ \j => natToInteger (length xs) + natToInteger j

llength : Nat -> Nat -> Integer
llength n r = let xs = mkList n in
                  repeat r $ \j => natToInteger (length xs) + natToInteger j

vappend : Nat -> Nat -> Integer
vappend n r = let xs = mkVect n in
                  repeat r $ \j => cast $ sumV (map (+ cast j) xs ++ xs)

lappend : Nat -> Nat -> Integer
lappend n r = let xs = mkList n in
                  repeat r $ \j => cast $ sumL (map (+ cast j) xs ++ xs)

vtoList : Nat -> Nat -> Integer
vtoList n r = let xs = mkVect n in
                  repeat r $ \j => cast $ sumL (toList (map (+ cast j) xs))

-- `tabulate` composes `f . FS` at each level: O(n^2) before the transform.
vtabulate : Nat -> Nat -> Integer
vtabulate n r = repeat r $ \j =>
                  cast $ sumV (tabulate {len = n} (\i => cast (finToNat i + j)))

ltabulate : Nat -> Nat -> Integer
ltabulate n r = repeat r $ \j =>
                  cast $ sumL (map (\i => cast (i + j)) (take n [0 .. n]))

vrange : Nat -> Nat -> Integer
vrange n r = repeat r $ \j => finSum (toList (range {len = n})) + cast j

vallFins : Nat -> Nat -> Integer
vallFins n r = repeat r $ \j => finSum (toList (Vect.allFins n)) + cast j

lallFins : Nat -> Nat -> Integer
lallFins n r = repeat r $ \j => finSum (List.allFins n) + cast j

-- Fin arithmetic on Fin (S m): `+` through `finS` and `strengthen`.
fplus : Nat -> Nat -> Integer
fplus m r = repeat r $ \j => finToInteger (fin m j + fin m (j * 7 + 3))

iplus : Nat -> Nat -> Integer
iplus m r = let n = the Int (cast (S m)) in
                repeat r $ \j => cast $ (cast j `mod` n + (cast j * 7 + 3) `mod` n) `mod` n

fmult : Nat -> Nat -> Integer
fmult m r = repeat r $ \j => finToInteger (fin m j * fin m (j * 7 + 3))

imult : Nat -> Nat -> Integer
imult m r = let n = the Int (cast (S m)) in
                repeat r $ \j => cast $ ((cast j `mod` n) * ((cast j * 7 + 3) `mod` n)) `mod` n

fsucc : Nat -> Nat -> Integer
fsucc m r = repeat r $ \j => finToInteger (finS (fin m j))

fstrengthen : Nat -> Nat -> Integer
fstrengthen m r = repeat r $ \j => maybe 0 finToInteger (strengthen (fin m j))

fcomplement : Nat -> Nat -> Integer
fcomplement m r = repeat r $ \j => finToInteger (complement (fin m j))

fnatToFin : Nat -> Nat -> Integer
fnatToFin m r = repeat r $ \j => maybe 0 finToInteger (natToFin (j `mod` (m + 5)) m)

-- These are identities already (Compiler.Opts.Identity): the check that
-- they stay so.
fconvert : Nat -> Nat -> Integer
fconvert m r = repeat r $ \j =>
                 let x = fin m j in
                     natToInteger (finToNat (weaken x)) + finToInteger (FS x)

cases : List (String, Nat -> Nat -> Integer)
cases =
  [ ("vindex", vindex), ("lindex", lindexC)
  , ("vmap", vmap), ("lmap", lmap)
  , ("vzipWith", vzipWith), ("lzipWith", lzipWith)
  , ("vfoldl", vfoldl), ("lfoldl", lfoldl)
  , ("vfoldr", vfoldr), ("lfoldr", lfoldr)
  , ("vlength", vlength), ("llength", llength)
  , ("vappend", vappend), ("lappend", lappend)
  , ("vtoList", vtoList)
  , ("vtabulate", vtabulate), ("ltabulate", ltabulate)
  , ("vrange", vrange)
  , ("vallFins", vallFins), ("lallFins", lallFins)
  , ("fplus", fplus), ("iplus", iplus)
  , ("fmult", fmult), ("imult", imult)
  , ("fsucc", fsucc), ("fstrengthen", fstrengthen)
  , ("fcomplement", fcomplement), ("fnatToFin", fnatToFin)
  , ("fconvert", fconvert)
  ]

runLine : String -> IO ()
runLine l
    = case words l of
           [c, n] => go c n "1"
           [c, n, r] => go c n r
           _ => pure ()
  where
    go : String -> String -> String -> IO ()
    go c n r
        = case lookup c cases of
               Nothing => putStrLn "unknown case \{c}"
               Just f => putStrLn "\{c} \{show (f (stringToNatOrZ n) (stringToNatOrZ r))}"

main : IO ()
main = loop
  where
    loop : IO ()
    loop = do l <- getLine
              if l == ""
                 then pure ()
                 else do runLine l; loop
