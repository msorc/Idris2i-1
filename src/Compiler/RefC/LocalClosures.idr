||| Applications of closures that are made in the same function.
|||
|||   let c = f a b   -- a partial application of f, which takes 3 arguments
|||   ...
|||   c x
|||
||| allocates a closure for `f a b`, only to apply it: when `c` has no other
||| use, the application is the call `f a b x` (or, when `f` takes more
||| arguments, the partial application `f a b x`), and no closure is made for
||| `c`.  The closure is made later than in the original code, where it is
||| applied (in one branch of a `case` only, say): making a closure has no
||| effect but the allocation, and the variables that it refers to are alive
||| until then anyway.  (Variables are bound once in ANF, so they are the same
||| at the application.)
|||
||| This runs before the other analyses of the RefC backend (see
||| Compiler.RefC.Unbox and Compiler.RefC.Borrow), which see the calls.
module Compiler.RefC.LocalClosures

import Compiler.ANF
import Core.FC
import Core.Name

import Data.SortedMap
import Data.Vect

%default covering

-- How often a variable is used, and how often as the closure of an
-- application.
record Uses where
  constructor MkUses
  all : SortedMap Int Nat
  applied : SortedMap Int Nat

bump : Int -> SortedMap Int Nat -> SortedMap Int Nat
bump i m = insert i (S (fromMaybe 0 (SortedMap.lookup i m))) m

useVar : AVar -> Uses -> Uses
useVar (ALocal i) u = { all $= bump i } u
useVar ANull u = u

useVars : List AVar -> Uses -> Uses
useVars vs u = foldl (flip useVar) u vs

uses : ANF -> Uses -> Uses
uses (AV _ v) u = useVar v u
uses (AAppName _ _ _ args) u = useVars args u
uses (AUnderApp _ _ _ args) u = useVars args u
uses (AApp _ _ c@(ALocal i) a) u = useVar a ({ applied $= bump i } (useVar c u))
uses (AApp _ _ c a) u = useVar a (useVar c u)
uses (ALet _ _ v b) u = uses b (uses v u)
uses (ACon _ _ _ _ args) u = useVars args u
uses (AOp _ _ _ args) u = useVars (toList args) u
uses (AExtPrim _ _ _ args) u = useVars args u
uses (AConCase _ sc alts def) u
    = let u' = foldl (\acc, (MkAConAlt _ _ _ _ b) => uses b acc) (useVar sc u) alts in
          maybe u' (\d => uses d u') def
uses (AConstCase _ sc alts def) u
    = let u' = foldl (\acc, (MkAConstAlt _ b) => uses b acc) (useVar sc u) alts in
          maybe u' (\d => uses d u') def
uses _ u = u

-- The closures not made yet: the function, the number of missing arguments
-- and the arguments.
Pending : Type
Pending = SortedMap Int (Name, Nat, List AVar)

-- The lets that a value starts with, and what it gives after them.
--
-- An application to one more argument is `let w = a in c @ w`, so when a
-- closure is applied to its arguments one at a time, the value of each step
-- is such a let:
--
--   let c2 = (let w = a in c1 @ w) in ... c2 @ b ...
--
-- Once `c1 @ w` is the partial application `f x w`, the let of `c2` can be
-- `let w = a in let c2 = f x w in ...`, where `c2` is pending as well.  The
-- two are the same: `a` is evaluated before the rest either way, and `w` is
-- not used outside of the value, as variables are bound once in ANF.  The
-- let of `w` encloses the application of `c2` then, which refers to `w`.
splitLets : ANF -> (List (FC, Int, ANF), ANF)
splitLets (ALet fc w a x)
    = let (lets, res) = splitLets x in ((fc, w, a) :: lets, res)
splitLets anf = ([], anf)

wrapLets : List (FC, Int, ANF) -> ANF -> ANF
wrapLets lets body = foldr (\(fc, w, a), acc => ALet fc w a acc) body lets

mutual
  rewriteANF : Uses -> Pending -> ANF -> ANF
  rewriteANF u ps (AApp fc lz c@(ALocal i) a)
      = case SortedMap.lookup i ps of
             Just (f, S Z, args) => AAppName fc lz f (args ++ [a])
             Just (f, S (S k), args) => AUnderApp fc f (S k) (args ++ [a])
             _ => AApp fc lz c a
  rewriteANF u ps (ALet fc v val body)
      = let val' = rewriteANF u ps val
            (lets, res) = splitLets val' in
            case res of
                 AUnderApp _ f m@(S _) args =>
                   if SortedMap.lookup v u.all == Just 1 && SortedMap.lookup v u.applied == Just 1
                      then wrapLets lets (rewriteANF u (insert v (f, m, args) ps) body)
                      else ALet fc v val' (rewriteANF u ps body)
                 _ => ALet fc v val' (rewriteANF u ps body)
  rewriteANF u ps (AConCase fc sc alts def)
      = AConCase fc sc (map (rewriteConAlt u ps) alts) (map (rewriteANF u ps) def)
  rewriteANF u ps (AConstCase fc sc alts def)
      = AConstCase fc sc (map (rewriteConstAlt u ps) alts) (map (rewriteANF u ps) def)
  rewriteANF _ _ anf = anf

  rewriteConAlt : Uses -> Pending -> AConAlt -> AConAlt
  rewriteConAlt u ps (MkAConAlt n ci t args b) = MkAConAlt n ci t args (rewriteANF u ps b)

  rewriteConstAlt : Uses -> Pending -> AConstAlt -> AConstAlt
  rewriteConstAlt u ps (MkAConstAlt c b) = MkAConstAlt c (rewriteANF u ps b)

||| The definition with the closures that are only applied once, where they
||| are made, made at their application instead.
export
applyLocalClosures : ANFDef -> ANFDef
applyLocalClosures (MkAFun args body)
    = MkAFun args (rewriteANF (uses body (MkUses SortedMap.empty SortedMap.empty)) SortedMap.empty body)
applyLocalClosures d = d
