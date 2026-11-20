||| Copies of the functions that take the layout of the elements of an array
||| (see Data.IOArray.Flat), for the layouts that they are called with.
|||
||| A function that takes a `Flat` (`readArray`, the methods of
||| Data.Linear.Array) is compiled once, with the layout as a parameter: the
||| accesses to the array in it are then the generic ones, which make a value
||| for the element they read.  Where it is called with a layout that is a
||| constant (the implementation of `Flat` of the type of the elements, a
||| literal after the newtypes are compiled away), it is replaced by a copy
||| that has the constant instead of the parameter, so that its accesses are
||| inline (see idris2_slotGet in prim.h); the copy calls copies in turn.
|||
||| This is done here, on the definitions of the program, rather than by the
||| specialisation of the elaborator (`%spec`, `--spec-interfaces`): a copy
||| made there is elaborated in the module that calls the function, which
||| does not see the modules that the function's body refers to unless they
||| are public imports (the methods of Data.Linear.Array call Data.IOArray,
||| which calls Data.IOArray.Prims, both private imports), and it would cost
||| type checking time.  Here every definition is known, and nothing is
||| type checked.
|||
||| The layout parameters are those that reach the layout argument of a
||| primitive on arrays of slots (`prim__slotGet` ...), directly or through
||| the layout parameters of the functions that they are passed to.  Only
||| layouts other than that of values (0) are worth a copy.
module Compiler.RefC.FlatClones

import Compiler.ANF
import Core.FC
import Core.Name
import Core.TT.Primitive

import Data.List
import Data.SortedMap
import Data.SortedSet
import Data.String
import Data.Vect

%default covering

||| The primitives that take a layout, as their second argument (after the
||| erased type).
layoutPrim : Name -> Bool
layoutPrim (NS _ (UN (Basic p))) = p == "prim__newSlots" || p == "prim__slotGet" || p == "prim__slotSet"
layoutPrim _ = False

-- The elements of a list but those at the positions `ks`.
dropAt : List Nat -> List a -> List a
dropAt ks xs = go 0 xs
  where
    go : Nat -> List a -> List a
    go _ [] = []
    go i (x :: rest) = if i `elem` ks then go (S i) rest else x :: go (S i) rest

LayoutParams : Type
LayoutParams = SortedMap Name (SortedSet Nat)

positions : List AVar -> Int -> List Nat
positions as v = map fst (filter (\(_, a) => a == ALocal v) (zip [0 .. length as] as))

-- The variables that a body passes to a layout position.
layoutUses : LayoutParams -> ANF -> SortedSet Int -> SortedSet Int
layoutUses lp (AExtPrim _ _ p (_ :: ALocal l :: _)) acc
    = if layoutPrim p then insert l acc else acc
layoutUses lp (AAppName _ _ g as) acc
    = case lookup g lp of
           Just ps => foldl (\a, (k, v) => case v of
                                              ALocal i => if contains k ps then insert i a else a
                                              ANull => a) acc (zip [0 .. length as] as)
           Nothing => acc
layoutUses lp (ALet _ _ v b) acc = layoutUses lp b (layoutUses lp v acc)
layoutUses lp (AConCase _ _ alts def) acc
    = foldl (\a, (MkAConAlt _ _ _ _ b) => layoutUses lp b a) (maybe acc (\d => layoutUses lp d acc) def) alts
layoutUses lp (AConstCase _ _ alts def) acc
    = foldl (\a, (MkAConstAlt _ b) => layoutUses lp b a) (maybe acc (\d => layoutUses lp d acc) def) alts
layoutUses _ _ acc = acc

||| The layout parameters of the functions (by position), to a fixpoint.
export
layoutParams : List (Name, ANFDef) -> LayoutParams
layoutParams defs = go 0 empty
  where
    funs : List (Name, List Int, ANF)
    funs = mapMaybe (\(n, d) => case d of
                                     MkAFun args b => Just (n, args, b)
                                     _ => Nothing) defs

    step : LayoutParams -> LayoutParams
    step lp = foldl (\m, (n, args, b) =>
                       let uses = layoutUses lp b empty
                           ps = fromList (map fst (filter (\(_, a) => contains a uses)
                                                          (zip [0 .. length args] args))) in
                           if null (SortedSet.toList ps) then m else insert n ps m)
                    empty funs

    size : LayoutParams -> Nat
    size lp = sum (map (length . SortedSet.toList) (values lp))

    go : Nat -> LayoutParams -> LayoutParams
    go k lp = let lp' = step lp in
                  if size lp' == size lp || k >= 20 then lp' else go (S k) lp'

-- The variables of a body that are bound to layout constants (literals, or
-- calls of the definitions that are literals).
constVars : SortedMap Name Bits64 -> ANF -> SortedMap Int Bits64 -> SortedMap Int Bits64
constVars cs (ALet _ v (APrimVal _ (B64 c)) b) acc = constVars cs b (insert v c acc)
constVars cs (ALet _ v (AAppName _ _ g []) b) acc
    = constVars cs b (maybe acc (\c => insert v c acc) (lookup g cs))
constVars cs (ALet _ _ v b) acc = constVars cs b (constVars cs v acc)
constVars cs (AConCase _ _ alts def) acc
    = foldl (\a, (MkAConAlt _ _ _ _ b) => constVars cs b a) (maybe acc (\d => constVars cs d acc) def) alts
constVars cs (AConstCase _ _ alts def) acc
    = foldl (\a, (MkAConstAlt _ b) => constVars cs b a) (maybe acc (\d => constVars cs d acc) def) alts
constVars _ _ acc = acc

||| The name of the copy of `g` for the constant layouts `cs` (by position).
cloneName : Name -> List (Nat, Bits64) -> Name
cloneName g cs = MN (show g ++ " at layout " ++ concat (intersperse "," (map (\(k, c) => show k ++ "=" ++ show c) cs))) 0

record CloneState where
  constructor MkCloneState
  done : SortedMap Name ANFDef -- the copies made
  todo : List (Name, Name, List (Nat, Bits64)) -- (copy, original, layouts)

||| The definitions, with the calls with constant layouts made calls of
||| copies, and the copies.  At most `limit` copies.
export
flatClones : (limit : Nat) -> List (Name, ANFDef) -> List (Name, ANFDef)
flatClones limit defs
    = let lp = layoutParams defs in
          if null (keys lp) then defs else
            let byName = fromList defs
                -- (the definitions that are a layout, other than that of values)
                cs = fromList (mapMaybe (\(n, d) => case d of
                                           MkAFun [] (APrimVal _ (B64 c)) => if c == 0 then Nothing else Just (n, c)
                                           _ => Nothing) defs)
                st0 = MkCloneState empty []
                (defs', st1) = rewriteAll lp cs defs st0
                st2 = loop lp cs byName limit st1 in
                defs' ++ SortedMap.toList st2.done
  where
    redirectOpt : LayoutParams -> SortedMap Name Bits64 -> SortedMap Int Bits64 -> CloneState -> Maybe ANF -> (Maybe ANF, CloneState)
    redirectAlts : LayoutParams -> SortedMap Name Bits64 -> SortedMap Int Bits64 -> CloneState -> List AConAlt -> (List AConAlt, CloneState)
    redirectConstAlts : LayoutParams -> SortedMap Name Bits64 -> SortedMap Int Bits64 -> CloneState -> List AConstAlt -> (List AConstAlt, CloneState)
    redirect : LayoutParams -> SortedMap Name Bits64 -> SortedMap Int Bits64 -> CloneState -> ANF -> (ANF, CloneState)
    redirect lp cs kv st e@(AAppName fc lz g as)
        = case lookup g lp of
            Nothing => (e, st)
            Just ps =>
              let consts = mapMaybe (\(k, a) => case a of
                                        ALocal i => if contains k ps then map (k,) (lookup i kv) else Nothing
                                        ANull => Nothing) (zip [0 .. length as] as) in
                  if null consts then (e, st) else
                    let cn = cloneName g consts
                        as' = dropAt (map fst consts) as
                        st' = if isJust (lookup cn st.done) || any (\(c, _, _) => c == cn) st.todo
                                 then st else { todo $= ((cn, g, consts) ::) } st in
                        (AAppName fc lz cn as', st')
    -- (a constant layout, from its definition, which is then a C constant)
    redirect lp cs kv st (ALet fc v (AAppName fc' lz g []) b)
        = let (b', st') = redirect lp cs kv st b in
              case lookup g cs of
                Just c => (ALet fc v (APrimVal fc' (B64 c)) b', st')
                Nothing => (ALet fc v (AAppName fc' lz g []) b', st')
    redirect lp cs kv st (ALet fc v val b)
        = let (val', st1) = redirect lp cs kv st val
              (b', st2) = redirect lp cs kv st1 b in
              (ALet fc v val' b', st2)
    redirect lp cs kv st (AConCase fc sc alts def)
        = let (alts', st1) = redirectAlts lp cs kv st alts
              (def', st2) = redirectOpt lp cs kv st1 def in
              (AConCase fc sc alts' def', st2)
    redirect lp cs kv st (AConstCase fc sc alts def)
        = let (alts', st1) = redirectConstAlts lp cs kv st alts
              (def', st2) = redirectOpt lp cs kv st1 def in
              (AConstCase fc sc alts' def', st2)
    redirect _ _ _ st e = (e, st)

    redirectOpt lp cs kv st Nothing = (Nothing, st)
    redirectOpt lp cs kv st (Just d) = let (d', st') = redirect lp cs kv st d in (Just d', st')

    redirectAlts lp cs kv st [] = ([], st)
    redirectAlts lp cs kv st (MkAConAlt n ci t as b :: alts)
        = let (b', st1) = redirect lp cs kv st b
              (alts', st2) = redirectAlts lp cs kv st1 alts in
              (MkAConAlt n ci t as b' :: alts', st2)

    redirectConstAlts lp cs kv st [] = ([], st)
    redirectConstAlts lp cs kv st (MkAConstAlt c b :: alts)
        = let (b', st1) = redirect lp cs kv st b
              (alts', st2) = redirectConstAlts lp cs kv st1 alts in
              (MkAConstAlt c b' :: alts', st2)

    rewriteDef : LayoutParams -> SortedMap Name Bits64 -> CloneState -> ANFDef -> (ANFDef, CloneState)
    rewriteDef lp cs st (MkAFun args b)
        = let kv = constVars cs b empty in
              if null (keys kv) then (MkAFun args b, st) else
                let (b', st') = redirect lp cs kv st b in (MkAFun args b', st')
    rewriteDef _ _ st d = (d, st)

    rewriteAll : LayoutParams -> SortedMap Name Bits64 -> List (Name, ANFDef) -> CloneState
              -> (List (Name, ANFDef), CloneState)
    rewriteAll lp cs [] st = ([], st)
    rewriteAll lp cs ((n, d) :: ds) st
        = let (d', st1) = rewriteDef lp cs st d
              (ds', st2) = rewriteAll lp cs ds st1 in
              ((n, d') :: ds', st2)

    -- The copy of `g` for the layouts: the parameters are let-bound to them.
    copyOf : SortedMap Name ANFDef -> Name -> List (Nat, Bits64) -> Maybe ANFDef
    copyOf byName g consts
        = case lookup g byName of
            Just (MkAFun args b) =>
              let kept = dropAt (map fst consts) args
                  bound = mapMaybe (\(k, c) => map (,c) (getAt k args)) consts
                  b' = foldr (\(v, c), acc => ALet emptyFC v (APrimVal emptyFC (B64 c)) acc) b bound in
                  Just (MkAFun kept b')
            _ => Nothing

    loop : LayoutParams -> SortedMap Name Bits64 -> SortedMap Name ANFDef -> Nat -> CloneState -> CloneState
    -- (past the limit, the copies still to make are made, without the
    -- copies of the functions that they call: each call already made a
    -- call of a copy has one)
    loop lp cs byName Z st
        = foldl (\s, (cn, g, consts) =>
                   if isJust (lookup cn s.done) then s
                      else case copyOf byName g consts of
                             Just d => the CloneState ({ done $= insert cn d } s)
                             Nothing => s)
                ({ todo := [] } st) st.todo
    loop lp cs byName (S k) st
        = case st.todo of
            [] => st
            ((cn, g, consts) :: rest) =>
              let st1 = { todo := rest } st in
              if isJust (lookup cn st1.done) then loop lp cs byName (S k) st1 else
                case copyOf byName g consts of
                  Nothing => loop lp cs byName (S k) st1
                  Just d =>
                    -- (a placeholder first, so that a recursive call finds it)
                    let st2 = { done $= insert cn d } st1
                        (d', st3) = rewriteDef lp cs st2 d in
                        loop lp cs byName k ({ done $= insert cn d' } st3)
