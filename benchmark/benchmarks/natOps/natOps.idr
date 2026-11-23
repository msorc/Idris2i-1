||| Nat operations, each beside its Integer equivalent.
|||
||| Every line of the input is `CASE SIZE [REPEATS]`; the program runs the
||| cases in order and prints a checksum for each, so the output of two
||| builds can be compared.  The case names starting with `n` work on `Nat`,
||| with `z` on `Integer`: `nlte` is to be read beside `zlte`, and so on.
||| SIZE bounds the operands, REPEATS is the number of operations.
||| Running one line at a time measures one case.
module Main

import Data.Nat
import Data.String
import Decidable.Equality

%default partial

-- Operands -----------------------------------------------------------------

-- Two operands below `m`, from the counter `j` (a linear congruence).
opA : Integer -> Nat -> Integer
opA m j = (natToInteger j * 1103515245 + 12345) `mod` m

opB : Integer -> Nat -> Integer
opB m j = (natToInteger j * 2654435761 + 7) `mod` m

repeat : Nat -> (Nat -> Integer) -> Integer
repeat r f = go r 0
  where
    go : Nat -> Integer -> Integer
    go Z acc = acc
    go (S k) acc = go k (acc + f k)

bool : Bool -> Integer
bool b = if b then 1 else 0

nat2 : (Nat -> Nat -> Integer) -> Nat -> Nat -> Integer
nat2 f m r = let m' = natToInteger (S m) in
                 repeat r $ \j => f (integerToNat (opA m' j)) (integerToNat (opB m' j))

int2 : (Integer -> Integer -> Integer) -> Nat -> Nat -> Integer
int2 f m r = let m' = natToInteger (S m) in
                 repeat r $ \j => f (opA m' j) (opB m' j)

-- Cases --------------------------------------------------------------------

nlte, zlte, nlt, ngte, ngt, nmin, zmin, nmax, zmax : Nat -> Nat -> Integer
nlte = nat2 (\a, b => bool (lte a b))
zlte = int2 (\a, b => bool (a <= b))
nlt = nat2 (\a, b => bool (lt a b))
ngte = nat2 (\a, b => bool (gte a b))
ngt = nat2 (\a, b => bool (gt a b))
nmin = nat2 (\a, b => natToInteger (minimum a b))
zmin = int2 min
nmax = nat2 (\a, b => natToInteger (maximum a b))
zmax = int2 max

-- `div`/`mod` through `Integral Nat`, and the NZ forms directly.
ndiv, nmod, zdiv, zmod, ndivNZ, nmodNZ, ndivmodNZ, ndivCeil : Nat -> Nat -> Integer
ndiv = nat2 (\a, b => natToInteger (a `div` S b))
nmod = nat2 (\a, b => natToInteger (a `mod` S b))
zdiv = int2 (\a, b => a `div` (b + 1))
zmod = int2 (\a, b => a `mod` (b + 1))
ndivNZ = nat2 (\a, b => natToInteger (divNatNZ a (S b) ItIsSucc))
nmodNZ = nat2 (\a, b => natToInteger (modNatNZ a (S b) ItIsSucc))
ndivmodNZ = nat2 (\a, b => let (q, r) = divmodNatNZ a (S b) ItIsSucc in
                               natToInteger q * 7 + natToInteger r)
ndivCeil = nat2 (\a, b => natToInteger (divCeilNZ a (S b) ItIsSucc))

ngcd, zgcd, nlcm : Nat -> Nat -> Integer
ngcd = nat2 (\a, b => natToInteger (gcd (S a) b))
zgcd = int2 (\a, b => go (a + 1) b)
  where
    go : Integer -> Integer -> Integer
    go a 0 = a
    go a b = go b (a `mod` b)
nlcm = nat2 (\a, b => natToInteger (lcm (S a) (S b)))

-- `power` with a small base and an exponent below SIZE.
npower, zpower : Nat -> Nat -> Integer
npower m r = repeat r $ \j =>
               natToInteger (power (S (j `mod` 3)) (integerToNat (opB (natToInteger (S m)) j))) `mod` 1000003
zpower m r = repeat r $ \j => pow (natToInteger (S (j `mod` 3))) (opB (natToInteger (S m)) j) `mod` 1000003
  where
    pow : Integer -> Integer -> Integer
    pow b 0 = 1
    pow b e = b * pow b (e - 1)

nisLTE, ndecEq, zdecEq : Nat -> Nat -> Integer
nisLTE = nat2 (\a, b => case isLTE a b of
                             Yes _ => 1
                             No _ => 0)
ndecEq = nat2 (\a, b => case decEq a (a + b `mod` 2) of
                             Yes _ => 1
                             No _ => 0)
zdecEq = int2 (\a, b => bool (a == a + b `mod` 2))

cases : List (String, Nat -> Nat -> Integer)
cases =
  [ ("nlte", nlte), ("zlte", zlte), ("nlt", nlt), ("ngte", ngte), ("ngt", ngt)
  , ("nmin", nmin), ("zmin", zmin), ("nmax", nmax), ("zmax", zmax)
  , ("ndiv", ndiv), ("zdiv", zdiv), ("nmod", nmod), ("zmod", zmod)
  , ("ndivNZ", ndivNZ), ("nmodNZ", nmodNZ), ("ndivmodNZ", ndivmodNZ)
  , ("ndivCeil", ndivCeil)
  , ("ngcd", ngcd), ("zgcd", zgcd), ("nlcm", nlcm)
  , ("npower", npower), ("zpower", zpower)
  , ("nisLTE", nisLTE), ("ndecEq", ndecEq), ("zdecEq", zdecEq)
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
