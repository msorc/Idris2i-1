module Main

import Data.Nat
import Data.Vect

-- Implementations found by search in a scope with lets.  The solution of a
-- search is made under the binders of the scope; the lets of a `rewrite`
-- (its predicate and its rule) are not used by the implementations found
-- under them, and are dropped from the solutions.  An implementation that is
-- a variable of the scope stays one.

data Bar = MkBar

viaLocal : Nat -> String
viaLocal n
    = let unused = n + 1
          local = the (Show Bar) (MkShow (\_ => "local \{show n}") (\_, _ => "local"))
      in show MkBar ++ " " ++ show unused

underRewrite : (n : Nat) -> Vect n Nat -> (String, Vect (n + 0) Nat)
underRewrite n xs
    = rewrite plusZeroRightNeutral n in
        (show (sum xs) ++ " " ++ show (map (* 2) xs), reverse xs)

underRewrites : (m, n : Nat) -> Vect (m + n) Nat -> Vect ((n + m) + 0) String
underRewrites m n xs
    = rewrite plusZeroRightNeutral (n + m) in
      rewrite plusCommutative n m in
        map (\x => show (x * 10 + m)) xs

main : IO ()
main = do putStrLn (viaLocal 3)
          printLn (underRewrite 3 [1, 2, 3])
          printLn (underRewrites 1 2 [4, 5, 6])
