||| Branches that build again the value they matched.
|||
|||   case x of
|||     Left e => Left e    -- in the bind of a monad of `Either`, say
|||
||| builds a cell equal to `x`: the same constructor, with the same fields in
||| the same order.  The types of the two may differ (`Either e a` and
||| `Either e b`), but the values are the same at run time, so the branch can
||| give `x` itself.  The code generator would otherwise make the branch take
||| over the cell of `x` when it is unique, and copy it (a new cell, a
||| reference to each field, a reference less to `x`) when it is not; with
||| `x` as the result, neither path does anything but give `x`.  In the
||| compiler, the error branch of every step of a `do` block in `Core` is one
||| of these (it is the bind of `Core.Core` inlined).
|||
||| The constructors are the same when their names, their information and
||| their tags are: the layout of the fields in the cell (the raw fields, see
||| `RawLayout` in Compiler.RefC.RefC; the flat records, see
||| Compiler.RefC.FlatOpt) is chosen by the name, and an intrinsic constructor
||| (`_builtin.CONS`, see Compiler.Opts.Constructor) stands for constructors
||| whose fields are all laid out the same.  The fields must be the variables
||| that the branch bound, in order: an erased field (`ANull`) is not taken
||| for one, and a constructor without fields is not changed (it is a static
||| value already).
|||
||| It is only done where it is less work on every path: when the branch
||| uses neither the fields nor `x` anywhere else, and the constructor is the
||| result of the branch or the value of one of the `let`s that lead to it
||| (not inside a `case` of the branch).  Otherwise `x` would stay alive
||| through the branch: every field that the branch uses would need a
||| reference of its own, and the other paths, which drop `x`, could not take
||| its cell over for a constructor of theirs.  In the merge of two lists,
|||
|||   merge (x :: xs) (y :: ys) = if x < y then x :: merge xs (y :: ys) else ...
|||
||| `y :: ys` is the second list again, but giving it would cost the cells
||| that both paths take over now.
|||
||| The rewrite is done before the analyses of the back end (borrowing,
||| unboxing, the reuse of cells), which see a branch that returns its
||| scrutinee.  Variables are bound once in a function in ANF (see
||| Compiler.ANF), so a variable means the same thing wherever it is in scope.
|||
||| `--directive refc-no-exact-rebuild` turns it off.
module Compiler.RefC.Rebuild

import Compiler.ANF
import Core.CompileExpr
import Core.FC
import Core.Name

import Data.List
import Data.Vect

%default covering

occursVar : Int -> AVar -> Bool
occursVar v (ALocal i) = i == v
occursVar _ ANull = False

-- Does the variable occur in the expression?
occurs : Int -> ANF -> Bool
occurs v (AV _ x) = occursVar v x
occurs v (AAppName _ _ _ as) = any (occursVar v) as
occurs v (AUnderApp _ _ _ as) = any (occursVar v) as
occurs v (AApp _ _ f a) = occursVar v f || occursVar v a
occurs v (ALet _ _ val body) = occurs v val || occurs v body
occurs v (ACon _ _ _ _ as) = any (occursVar v) as
occurs v (AOp _ _ _ as) = any (occursVar v) (toList as)
occurs v (AExtPrim _ _ _ as) = any (occursVar v) as
occurs v (AConCase _ sc alts def)
    = occursVar v sc || any (\(MkAConAlt _ _ _ _ b) => occurs v b) alts
      || maybe False (occurs v) def
occurs v (AConstCase _ sc alts def)
    = occursVar v sc || any (\(MkAConstAlt _ b) => occurs v b) alts
      || maybe False (occurs v) def
occurs _ _ = False

parameters (x : Int) (n : Name) (ci : ConInfo) (tag : Maybe Int) (fields : List Int)
  -- Is it the cell that the branch matched?
  same : ANF -> Bool
  same (ACon _ n' ci' tag' args)
      = n' == n && ci' == ci && tag' == tag && args == map ALocal fields
  same _ = False

  -- The body of the branch with the first rebuilt cell on its spine of
  -- `let`s replaced by `x`.
  spine : ANF -> Maybe ANF
  spine e@(ACon fc _ _ _ _) = if same e then Just (AV fc (ALocal x)) else Nothing
  spine (ALet fc v val rest)
      = if same val then Just (ALet fc v (AV fc (ALocal x)) rest)
           else ALet fc v val <$> spine rest
  spine _ = Nothing

mutual
  -- The expression with the rebuilt cells replaced by the scrutinees, and how
  -- many were.
  go : ANF -> (Nat, ANF)
  go (ALet fc v val body)
      = let (k, val') = go val
            (k', body') = go body in
            (k + k', ALet fc v val' body')
  go (AConCase fc sc alts def)
      = let alts' = map (goAlt sc) alts
            def' = map go def in
            (sum (map fst alts') + maybe 0 fst def',
             AConCase fc sc (map snd alts') (map snd def'))
  go (AConstCase fc sc alts def)
      = let alts' = map (\(MkAConstAlt c b) =>
                           let (k, b') = go b in (k, MkAConstAlt c b')) alts
            def' = map go def in
            (sum (map fst alts') + maybe 0 fst def',
             AConstCase fc sc (map snd alts') (map snd def'))
  go e = (0, e)

  goAlt : AVar -> AConAlt -> (Nat, AConAlt)
  goAlt sc (MkAConAlt n ci tag fs b)
      = let (k, b') = go b in
            case (sc, fs) of
              (ALocal x, _ :: _) =>
                case spine x n ci tag fs b' of
                  Just b'' =>
                    if occurs x b' || any (\f => occurs f b'') fs
                       then (k, MkAConAlt n ci tag fs b')
                       else (S k, MkAConAlt n ci tag fs b'')
                  Nothing => (k, MkAConAlt n ci tag fs b')
              _ => (k, MkAConAlt n ci tag fs b')

||| The definition with the branches that build again the cell they matched
||| giving the cell itself, where that is less work (see above), and how many
||| such branches there were.
export
exactRebuilds : ANFDef -> (Nat, ANFDef)
exactRebuilds (MkAFun args body)
    = let (k, body') = go body in (k, MkAFun args body')
exactRebuilds d = (0, d)
