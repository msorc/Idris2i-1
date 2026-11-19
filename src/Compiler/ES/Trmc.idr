||| Tail recursion modulo cons for the JavaScript backends.
|||
||| A function that returns a constructor with a call of itself in a field,
|||
||| ```idris
||| zipWith f (x :: xs) (y :: ys) = f x y :: zipWith f xs ys
||| ```
|||
||| needs a JavaScript frame per element: a list of some 10^4 elements
||| overflows the stack of the browser (and of the main thread of Node).  Such
||| a function `f` is compiled to a loop instead: the cell is made first, with
||| a hole for the result of the call, and the call becomes a tail call that
||| fills the hole.  `f` becomes
|||
||| ```javascript
||| function f(as) { const h = {}; f$trmc(as, h, 'a1'); return h.a1 }
||| ```
|||
||| where `f$trmc(as, dst, fld)` is the body of `f` that writes what it
||| returns into `dst[fld]`.  A cell `Con(e1, f(bs), e3)` in tail position
||| becomes
|||
||| ```javascript
||| const c = Con(e1, undefined, e3); dst[fld] = c; return f$trmc(bs, c, 'a2')
||| ```
|||
||| a tail call of `f$trmc` to itself, and so a loop (see
||| `Compiler.ES.TailRec`).  A cell in a cell (`x :: y :: f xs`) is made the
||| same way, and a tail call of `f` to itself becomes a tail call of `f$trmc`
||| with the same hole.  Of several fields with a call (`Node (f l) x (f r)`),
||| the last one is made the hole.
|||
||| The fields after the call are computed before it, so they must do nothing
||| but allocate (variables, constants, lambdas, delayed values and
||| constructors of these).  The other tail calls of `f` are no tail calls in
||| `f$trmc` (the result goes into the hole), so `f` is only transformed when
||| it makes no tail call to an unknown function, nor to a function that calls
||| it back by tail calls or that can return a pending call of the trampoline:
||| a loop through such a call would need a frame per round.
module Compiler.ES.Trmc

import Core.CompileExpr
import Core.Context

import Compiler.ES.TailRec

import Data.List
import Data.List1
import Data.SortedMap
import Data.SortedSet
import Data.Vect
import Libraries.Data.Graph

%default covering

||| The external primitive that makes the holder of the result: `{}`.
export
trmcHolder : Name
trmcHolder = UN $ Basic "prim__js_trmcHolder"

||| The external primitive that fills a hole: `dst[fld] = v`.
export
trmcFill : Name
trmcFill = UN $ Basic "prim__js_trmcFill"

||| The external primitive that reads the result out of its holder.
export
trmcResult : Name
trmcResult = UN $ Basic "prim__js_trmcResult"

-- The constructors that are objects with fields `a1`, `a2`, ...
isCell : ConInfo -> Bool
isCell DATACON = True
isCell CONS = True
isCell JUST = True
isCell RECORD = True
isCell _ = False

-- Computing it does nothing but allocate.
safe : NamedCExp -> Bool
safe (NmLocal _ _) = True
safe (NmPrimVal _ _) = True
safe (NmErased _) = True
safe (NmLam _ _ _) = True
safe (NmDelay _ _ _) = True
safe (NmCon _ _ _ _ as) = all safe as
safe _ = False

parameters (self : Name) (arity : Nat)

  -- A call of `self` with all of its arguments.
  selfCall : NamedCExp -> Maybe (List NamedCExp)
  selfCall (NmApp _ (NmRef _ g) as)
      = if g == self && length as == arity then Just as else Nothing
  selfCall _ = Nothing

  mutual
    -- A cell with a call of `self` (or a cell with one) in a field: the
    -- position of the last such field after which the fields are safe.
    cellField : NamedCExp -> Maybe Nat
    cellField (NmCon _ _ ci _ as) = if isCell ci then go 0 Nothing as else Nothing
      where
        go : Nat -> Maybe Nat -> List NamedCExp -> Maybe Nat
        go _ found [] = found
        go i found (a :: rest)
            = go (S i) (if hasHole a && all safe rest then Just i else found) rest
    cellField _ = Nothing

    hasHole : NamedCExp -> Bool
    hasHole e = isJust (selfCall e) || isJust (cellField e)

  -- Is there such a cell in tail position?
  hasCell : NamedCExp -> Bool
  hasCell (NmLet _ _ _ b) = hasCell b
  hasCell (NmConCase _ _ alts def)
      = any (\(MkNConAlt _ _ _ _ b) => hasCell b) alts || maybe False hasCell def
  hasCell (NmConstCase _ _ alts def)
      = any (\(MkNConstAlt _ b) => hasCell b) alts || maybe False hasCell def
  hasCell e = isJust (cellField e)

  -- The body of `f$trmc` (`loop`): the result of `e` goes into `dst[fld]`.
  -- (`i` numbers the variables of the cells.)
  toTrmc : (loop : Name) -> (dst, fld : NamedCExp) -> Int -> NamedCExp ->
           (Int, NamedCExp)
  toTrmc loop dst fld i (NmLet fc x v b)
      = let (i', b') = toTrmc loop dst fld i b in (i', NmLet fc x v b')
  toTrmc loop dst fld i (NmConCase fc sc alts def)
      = let (i1, alts') = alternatives i alts
            (i2, def') = dflt i1 def in
            (i2, NmConCase fc sc alts' def')
    where
      alternatives : Int -> List NamedConAlt -> (Int, List NamedConAlt)
      alternatives i [] = (i, [])
      alternatives i (MkNConAlt n ci t as b :: rest)
          = let (i1, b') = toTrmc loop dst fld i b
                (i2, rest') = alternatives i1 rest in
                (i2, MkNConAlt n ci t as b' :: rest')

      dflt : Int -> Maybe NamedCExp -> (Int, Maybe NamedCExp)
      dflt i Nothing = (i, Nothing)
      dflt i (Just d) = let (i', d') = toTrmc loop dst fld i d in (i', Just d')
  toTrmc loop dst fld i (NmConstCase fc sc alts def)
      = let (i1, alts') = alternatives i alts
            (i2, def') = dflt i1 def in
            (i2, NmConstCase fc sc alts' def')
    where
      alternatives : Int -> List NamedConstAlt -> (Int, List NamedConstAlt)
      alternatives i [] = (i, [])
      alternatives i (MkNConstAlt c b :: rest)
          = let (i1, b') = toTrmc loop dst fld i b
                (i2, rest') = alternatives i1 rest in
                (i2, MkNConstAlt c b' :: rest')

      dflt : Int -> Maybe NamedCExp -> (Int, Maybe NamedCExp)
      dflt i Nothing = (i, Nothing)
      dflt i (Just d) = let (i', d') = toTrmc loop dst fld i d in (i', Just d')
  toTrmc loop dst fld i e@(NmCrash _ _) = (i, e)
  toTrmc loop dst fld i e
      = case selfCall e of
             Just as => (i, NmApp EmptyFC (NmRef EmptyFC loop) (as ++ [dst, fld]))
             Nothing => case (e, cellField e) of
                  (NmCon fc cn ci t as, Just k) =>
                    let cell = MN "$trmcCell" i
                        filled = MN "$trmcFilled" i
                        as' = replaceAt k (NmErased fc) as
                        inner = fromMaybe (NmErased fc) (getAt k as)
                        (i', rest) = toTrmc loop (NmLocal fc cell)
                                       (NmPrimVal fc (Str ("a" ++ show (S k))))
                                       (i + 1) inner in
                        (i', NmLet fc cell (NmCon fc cn ci t as')
                               (NmLet fc filled (fill dst fld (NmLocal fc cell)) rest))
                  _ => (i, fill dst fld e)
    where
      fill : NamedCExp -> NamedCExp -> NamedCExp -> NamedCExp
      fill d f v = NmExtPrim EmptyFC trmcFill [d, f, v]

      replaceAt : Nat -> a -> List a -> List a
      replaceAt _ _ [] = []
      replaceAt Z y (_ :: xs) = y :: xs
      replaceAt (S k) y (x :: xs) = x :: replaceAt k y xs

-- The function as a loop: `f` and `f$trmc` (named `loop`).
transform : (f : Name) -> (loop : Name) -> FC -> List Name -> NamedCExp ->
            List (Name, FC, NamedDef)
transform f loop fc args body
    = let dst = MN "$trmcDst" 0
          fld = MN "$trmcField" 0
          holder = MN "$trmcHolder" 0
          done = MN "$trmcDone" 0
          body' = snd $ toTrmc f (length args) loop (NmLocal fc dst) (NmLocal fc fld) 0 body
          wrapper = NmLet fc holder (NmExtPrim fc trmcHolder [])
                      (NmLet fc done
                         (NmApp fc (NmRef fc loop)
                            (map (NmLocal fc) args
                               ++ [NmLocal fc holder, NmPrimVal fc (Str "a1")]))
                         (NmExtPrim fc trmcResult [NmLocal fc holder]))
       in [ (f, fc, MkNmFun args wrapper)
          , (loop, fc, MkNmFun (args ++ [dst, fld]) body') ]

||| Compiles the functions with tail recursion modulo cons to loops (see the
||| top of this module); the other definitions stay as they are.
export
trmcDefs : List (Name, FC, NamedDef) -> List (Name, FC, NamedDef)
trmcDefs defs =
  let funs = mapMaybe fun defs
      graph : SortedMap Name (SortedSet Name)
      graph = fromList $ map (\(n, _, _, b) => (n, fromList (catMaybes (tailCallees b)))) funs
      -- the functions that are in a group of several that call each other
      -- by tail calls
      grouped = SortedSet.fromList $ concatMap forget $ filter (\g => length g > 1) $ tarjan graph
      bouncing = bouncingFunctions $ map (\(n, _, as, b) => MkFunction n as b False) funs
      ok : Name -> Nat -> NamedCExp -> Bool
      ok f k b = k > 0 && not (contains f grouped) && hasCell f k b
                 && all (maybe False (\g => g == f || not (contains g bouncing)))
                        (tailCallees b)
   in go ok 0 defs
  where
    fun : (Name, FC, NamedDef) -> Maybe (Name, FC, List Name, NamedCExp)
    fun (n, fc, MkNmFun as b) = Just (n, fc, as, b)
    fun _ = Nothing

    go : (Name -> Nat -> NamedCExp -> Bool) -> Int -> List (Name, FC, NamedDef) ->
         List (Name, FC, NamedDef)
    go ok i [] = []
    go ok i (d@(n, fc, MkNmFun as b) :: rest)
        = if ok n (length as) b
             then transform n (MN "$trmc" i) fc as b ++ go ok (i + 1) rest
             else d :: go ok i rest
    go ok i (d :: rest) = d :: go ok i rest
