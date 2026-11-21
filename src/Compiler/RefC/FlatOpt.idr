||| The elements of flat arrays kept out of values (stage C of
||| docs/source/backends/refc-flat-layout.rst), in the programs that use
||| flat arrays (see `flatMode` in Compiler.RefC.RefC).
|||
||| A flat array stores its elements inline (see Data.IOArray.Flat), but
||| `prim__slotGet` gives a value: a `Just` and the record's cell, which the
||| code that reads it takes apart at once, and `prim__slotSet` takes one.
||| This pass rewrites the functions that use flat arrays so that no such
||| value is made where the element is only looked at:
|||
||| * the small functions that make, take apart or access such elements (the
|||   copies of the array functions for a layout, see
|||   Compiler.RefC.FlatClones, the `Res` they give, the functions on the
|||   records) are inlined into the functions that access flat arrays;
||| * a `case` on a constructor that a `let` of the function made is the
|||   branch of that constructor (the `Res` of an access, say);
||| * an element read (`prim__slotGet`, maybe in the branch of a bounds test)
|||   is its presence and its fields, read as C numbers
|||   (`slotPresent`, `slotField`); a `case` on it is a test of the presence,
|||   and the record is made (from the fields) only where it is used as a
|||   value;
||| * a record made by a `case` whose branches all give one (an update in a
|||   branch) is its fields, each one the same `case` (the branches must be
|||   pure: they are copied);
||| * an element written (`prim__slotSet` of a `Just`) is written from the
|||   fields (`slotStore`), or from the record's cell (`slotStoreElem`),
|||   without the `Just`;
||| * the `let`s of pure values that are not used any more are dropped.
|||
||| On the way, the `let`s of a `let` are floated out, a closure that the
||| function makes and applies to its last argument is a call, and the
||| projections of a variable bound outside a read (the array of an
||| `IOArray`) are made once: before its components where they cannot fail,
||| a component of their own otherwise.  This runs in rounds, as a function
||| rewritten can be one to inline in the next.
|||
||| An element read by its fields is first taken whole, its snapshot
||| (`slotSnap`): nothing when the array is read inline, its value otherwise,
||| taken once under the lock of a shared array; the fields are read from it,
||| so that they are those of one write even when another thread writes the
||| element at the same time.  So the element is read once: a value split
||| whose branches read one shares the snapshot between its components, and
||| an element used as a value is made from its components where they are
||| used too.
|||
||| The primitives used are those of the RefC back end only (namespace
||| `_refc_flat`, see prim.h): their accesses are inline when the array has
||| the layout, through values otherwise, so they are right for every array.
module Compiler.RefC.FlatOpt

import Compiler.ANF
import Core.CompileExpr
import Core.FC
import Core.Name
import Core.TT

import Data.List
import Data.SortedMap
import Data.SortedSet
import Data.String
import Data.Vect

%default covering

------------------------------------------------------------------------
-- The primitives

flatNS : Namespace
flatNS = mkNamespace "_refc_flat"

export
flatPrim : String -> Name
flatPrim s = NS flatNS (UN (Basic s))

||| The name of a primitive of this pass, if it is one.
export
flatPrimName : Name -> Maybe String
flatPrimName (NS ns (UN (Basic s))) = if ns == flatNS then Just s else Nothing
flatPrimName _ = Nothing

||| The letter of the C number type of a field (D, I, U).
export
typeLetter : PrimType -> String
typeLetter DoubleType = "D"
typeLetter Bits64Type = "U"
typeLetter _ = "I"

export
letterType : Char -> PrimType
letterType 'D' = DoubleType
letterType 'U' = Bits64Type
letterType _ = IntType

isSlotPrim : Name -> String -> Bool
isSlotPrim (NS _ (UN (Basic p))) s = p == s
isSlotPrim _ _ = False

------------------------------------------------------------------------
-- What is known of the layouts and the records

||| A record that the arrays may hold inline: its constructor, its tag and
||| `ConInfo`, and the C number types of its fields (all raw: see RawLayout
||| in RefC).
public export
record FlatRecord where
  constructor MkFlatRecord
  recTag : Int
  recInfo : ConInfo
  recFields : List PrimType

public export
FlatRecords : Type
FlatRecords = SortedMap Name FlatRecord

||| The layout codes: a record of `n` fields and the tag `t` is
||| 2 + 256 n + 2^24 t; a primitive is 1 + 256 k (see Data.IOArray.Flat).
data ElemShape = ERec Name | EPrim PrimType

-- The element shape of a constant layout, if it is one this pass handles:
-- a record of which there is one constructor with that number of fields and
-- tag, or a primitive stored as 8 bytes (Double, Int, Bits64).
elemShape : SortedMap (Nat, Int) (List Name) -> Bits64 -> Maybe ElemShape
elemShape recs code
    = let kind = code `mod` 256
          rest = code `div` 256 in
          if kind == 1 then case rest of
                              1 => Just (EPrim DoubleType)
                              2 => Just (EPrim IntType)
                              3 => Just (EPrim Bits64Type)
                              _ => Nothing
          else if kind == 2
             then let n = cast {to = Nat} (rest `mod` 65536)
                      t = cast {to = Int} (rest `div` 65536) in
                      case SortedMap.lookup (n, t) recs of
                        Just [c] => Just (ERec c)
                        _ => Nothing
             else Nothing

------------------------------------------------------------------------
-- Variables

-- The largest variable of an expression.
maxVar : ANF -> Int
maxVar (AV _ (ALocal i)) = i
maxVar (AAppName _ _ _ as) = foldl max 0 (map v as)
  where v : AVar -> Int
        v (ALocal i) = i
        v ANull = 0
maxVar (AUnderApp _ _ _ as) = foldl max 0 (map v as)
  where v : AVar -> Int
        v (ALocal i) = i
        v ANull = 0
maxVar (ALet _ x val b) = max x (max (maxVar val) (maxVar b))
maxVar (AConCase _ _ alts def)
    = foldl max (maybe 0 maxVar def) (map (\(MkAConAlt _ _ _ as b) => foldl max (maxVar b) as) alts)
maxVar (AConstCase _ _ alts def)
    = foldl max (maybe 0 maxVar def) (map (\(MkAConstAlt _ b) => maxVar b) alts)
maxVar _ = 0

-- How often each variable is used.
uses : ANF -> SortedMap Int Nat -> SortedMap Int Nat
uses e acc = go e acc
  where
    use : AVar -> SortedMap Int Nat -> SortedMap Int Nat
    use (ALocal i) m = insert i (S (fromMaybe 0 (SortedMap.lookup i m))) m
    use ANull m = m
    useAll : List AVar -> SortedMap Int Nat -> SortedMap Int Nat
    useAll as m = foldl (flip use) m as
    go : ANF -> SortedMap Int Nat -> SortedMap Int Nat
    go (AV _ v) m = use v m
    go (AAppName _ _ _ as) m = useAll as m
    go (AUnderApp _ _ _ as) m = useAll as m
    go (AApp _ _ f a) m = use f (use a m)
    go (ALet _ _ v b) m = go b (go v m)
    go (ACon _ _ _ _ as) m = useAll as m
    go (AOp _ _ _ as) m = useAll (toList as) m
    go (AExtPrim _ _ _ as) m = useAll as m
    go (AConCase _ sc alts def) m
        = foldl (\m', (MkAConAlt _ _ _ _ b) => go b m') (maybe (use sc m) (\d => go d (use sc m)) def) alts
    go (AConstCase _ sc alts def) m
        = foldl (\m', (MkAConstAlt _ b) => go b m') (maybe (use sc m) (\d => go d (use sc m)) def) alts
    go _ m = m

-- Rename the variables of an expression (`ren`, the others unchanged).
renameVar : SortedMap Int AVar -> AVar -> AVar
renameVar ren v@(ALocal i) = fromMaybe v (SortedMap.lookup i ren)
renameVar _ ANull = ANull

renameBinder : SortedMap Int AVar -> Int -> Int
renameBinder ren i = case SortedMap.lookup i ren of
                          Just (ALocal j) => j
                          _ => i

rename : SortedMap Int AVar -> ANF -> ANF
rename ren (AV fc v) = AV fc (renameVar ren v)
rename ren (AAppName fc lz n as) = AAppName fc lz n (map (renameVar ren) as)
rename ren (AUnderApp fc n m as) = AUnderApp fc n m (map (renameVar ren) as)
rename ren (AApp fc lz f a) = AApp fc lz (renameVar ren f) (renameVar ren a)
rename ren (ALet fc x v b) = ALet fc (renameBinder ren x) (rename ren v) (rename ren b)
rename ren (ACon fc n ci t as) = ACon fc n ci t (map (renameVar ren) as)
rename ren (AOp fc lz op as) = AOp fc lz op (map (renameVar ren) as)
rename ren (AExtPrim fc lz p as) = AExtPrim fc lz p (map (renameVar ren) as)
rename ren (AConCase fc sc alts def)
    = AConCase fc (renameVar ren sc)
               (map (\(MkAConAlt n ci t as b) => MkAConAlt n ci t (map (renameBinder ren) as) (rename ren b)) alts)
               (map (rename ren) def)
rename ren (AConstCase fc sc alts def)
    = AConstCase fc (renameVar ren sc) (map (\(MkAConstAlt c b) => MkAConstAlt c (rename ren b)) alts)
                 (map (rename ren) def)
rename _ e = e

-- The binders of an expression.
binders : ANF -> List Int
binders (ALet _ x v b) = x :: binders v ++ binders b
binders (AConCase _ _ alts def)
    = concatMap (\(MkAConAlt _ _ _ as b) => as ++ binders b) alts ++ maybe [] binders def
binders (AConstCase _ _ alts def)
    = concatMap (\(MkAConstAlt _ b) => binders b) alts ++ maybe [] binders def
binders _ = []

------------------------------------------------------------------------
-- Purity

||| May the expression be copied, or dropped when its value is not used?
||| (It has no effect: a pure primitive, a constructor, a read of an array
||| by this pass, a closure made.)
pure : ANF -> Bool
pure (AV _ _) = True
pure (APrimVal _ _) = True
pure (ACon _ _ _ _ _) = True
pure (AUnderApp _ _ _ _) = True
pure (AOp _ _ Crash _) = False
pure (AOp _ _ _ _) = True
pure (AExtPrim _ _ p _) = case flatPrimName p of
                               Just s => isPrefixOf "slotField" s || s == "slotPresent" || s == "slotSnap"
                               -- (a read, which makes a value, but has no effect)
                               Nothing => isSlotPrim p "prim__slotGet"
pure (ALet _ _ v b) = pure v && pure b
pure (AConCase _ _ alts def) = all (\(MkAConAlt _ _ _ _ b) => pure b) alts && maybe True pure def
pure (AConstCase _ _ alts def) = all (\(MkAConstAlt _ b) => pure b) alts && maybe True pure def
pure (AErased _) = True
pure _ = False

-- Drop the `let`s of the values that are not used, of those that `droppable`
-- tells (pure values).
dceWith : (ANF -> Bool) -> ANF -> ANF
dceWith droppable e = fst (go e)
  where
    -- the expression, and the variables it uses
    go : ANF -> (ANF, SortedSet Int)
    goAlts : List AConAlt -> (List AConAlt, SortedSet Int)
    goConstAlts : List AConstAlt -> (List AConstAlt, SortedSet Int)
    var : AVar -> SortedSet Int
    var (ALocal i) = singleton i
    var ANull = SortedSet.empty
    vars : List AVar -> SortedSet Int
    vars as = foldl (\s, v => union s (var v)) SortedSet.empty as

    go (ALet fc x v b)
        = let (b', ub) = go b in
              if not (contains x ub) && droppable v
                 then (b', ub)
                 else let (v', uv) = go v in (ALet fc x v' b', union uv (delete x ub))
    go (AConCase fc sc alts def)
        = let (alts', ua) = goAlts alts
              (def', ud) = maybe (Nothing, SortedSet.empty) (\d => let (d', u) = go d in (Just d', u)) def in
              (AConCase fc sc alts' def', union (var sc) (union ua ud))
    go (AConstCase fc sc alts def)
        = let (alts', ua) = goConstAlts alts
              (def', ud) = maybe (Nothing, SortedSet.empty) (\d => let (d', u) = go d in (Just d', u)) def in
              (AConstCase fc sc alts' def', union (var sc) (union ua ud))
    go e@(AV _ v) = (e, var v)
    go e@(AAppName _ _ _ as) = (e, vars as)
    go e@(AUnderApp _ _ _ as) = (e, vars as)
    go e@(AApp _ _ f a) = (e, union (var f) (var a))
    go e@(ACon _ _ _ _ as) = (e, vars as)
    go e@(AOp _ _ _ as) = (e, vars (toList as))
    go e@(AExtPrim _ _ _ as) = (e, vars as)
    go e = (e, SortedSet.empty)

    goAlts [] = ([], SortedSet.empty)
    goAlts (MkAConAlt n ci t as b :: rest)
        = let (b', ub) = go b
              (rest', ur) = goAlts rest in
              (MkAConAlt n ci t as b' :: rest', union (foldl (flip delete) ub as) ur)
    goConstAlts [] = ([], SortedSet.empty)
    goConstAlts (MkAConstAlt c b :: rest)
        = let (b', ub) = go b
              (rest', ur) = goConstAlts rest in
              (MkAConstAlt c b' :: rest', union ub ur)

-- Drop the `let`s of pure values that are not used.
dce : ANF -> ANF
dce = dceWith pure

------------------------------------------------------------------------
-- Inlining

-- The size of an expression.
size : ANF -> Nat
size (ALet _ _ v b) = 1 + size v + size b
size (AConCase _ _ alts def)
    = 1 + sum (map (\(MkAConAlt _ _ _ _ b) => size b) alts) + maybe 0 size def
size (AConstCase _ _ alts def)
    = 1 + sum (map (\(MkAConstAlt _ b) => size b) alts) + maybe 0 size def
size _ = 1

-- Does the expression touch the elements of flat arrays: access an array of
-- slots, or make or take apart a flat record?
touches : FlatRecords -> ANF -> Bool
touches recs (AExtPrim _ _ p _)
    = isSlotPrim p "prim__slotGet" || isSlotPrim p "prim__slotSet" || isSlotPrim p "prim__newSlots"
      || isJust (flatPrimName p)
touches recs (ACon _ n _ _ _) = isJust (SortedMap.lookup n recs)
touches recs (ALet _ _ v b) = touches recs v || touches recs b
touches recs (AConCase _ _ alts def)
    = any (\(MkAConAlt n _ _ _ b) => isJust (SortedMap.lookup n recs) || touches recs b) alts || maybe False (touches recs) def
touches recs (AConstCase _ _ alts def)
    = any (\(MkAConstAlt _ b) => touches recs b) alts || maybe False (touches recs) def
touches _ _ = False

accesses : ANF -> Bool
accesses (AExtPrim _ _ p _) = isSlotPrim p "prim__slotGet" || isSlotPrim p "prim__slotSet"
                              || flatPrimName p == Just "slotStoreElem"
accesses (ALet _ _ v b) = accesses v || accesses b
accesses (AConCase _ _ alts def) = any (\(MkAConAlt _ _ _ _ b) => accesses b) alts || maybe False accesses def
accesses (AConstCase _ _ alts def) = any (\(MkAConstAlt _ b) => accesses b) alts || maybe False accesses def
accesses _ = False

-- Does the expression access the elements of a flat array by their fields
-- (the primitives of this pass)?
usesFlat : ANF -> Bool
usesFlat (AExtPrim _ _ p _) = isJust (flatPrimName p)
usesFlat (ALet _ _ v b) = usesFlat v || usesFlat b
usesFlat (AConCase _ _ alts def) = any (\(MkAConAlt _ _ _ _ b) => usesFlat b) alts || maybe False usesFlat def
usesFlat (AConstCase _ _ alts def) = any (\(MkAConstAlt _ b) => usesFlat b) alts || maybe False usesFlat def
usesFlat _ = False

calls : Name -> ANF -> Bool
calls f (AAppName _ _ g _) = f == g
calls f (AUnderApp _ g _ _) = f == g
calls f (ALet _ _ v b) = calls f v || calls f b
calls f (AConCase _ _ alts def) = any (\(MkAConAlt _ _ _ _ b) => calls f b) alts || maybe False (calls f) def
calls f (AConstCase _ _ alts def) = any (\(MkAConstAlt _ b) => calls f b) alts || maybe False (calls f) def
calls _ _ = False

-- Does the expression call one of the functions of `inl`?
callsAny : SortedMap Name a -> ANF -> Bool
callsAny inl (AAppName _ Nothing g _) = isJust (SortedMap.lookup g inl)
callsAny inl (ALet _ _ v b) = callsAny inl v || callsAny inl b
callsAny inl (AConCase _ _ alts def)
    = any (\(MkAConAlt _ _ _ _ b) => callsAny inl b) alts || maybe False (callsAny inl) def
callsAny inl (AConstCase _ _ alts def)
    = any (\(MkAConstAlt _ b) => callsAny inl b) alts || maybe False (callsAny inl) def
callsAny _ _ = False

-- The largest function inlined.
inlineLimit : Nat
inlineLimit = 800

-- Inline, in the body of `f`, the calls of the functions of `inl` (but those
-- of `path`, the functions being inlined there already: a call of `f` in
-- the body of a function inlined into `f` stays a call), at most `depth`
-- deep.  `next` is the next free variable.
inlineMaybe : SortedMap Name (List Int, ANF) -> List Name -> Nat -> Int -> Maybe ANF -> (Maybe ANF, Int)
inlineIn : SortedMap Name (List Int, ANF) -> List Name -> Nat -> Int -> ANF -> (ANF, Int)
inlineIn inl path depth next e@(AAppName fc Nothing g as)
    = case SortedMap.lookup g inl of
        Just (params, body) =>
          if depth == 0 || elem g path || length params /= length as then (e, next) else
            let bs = nub (binders body)
                ren = fromList (zip params as ++ zipWith (\b, k => (b, ALocal (next + k))) bs [0 .. cast (length bs)])
                next' = next + cast (length bs) + 1
                body' = rename ren body in
                inlineIn inl (g :: path) (pred depth) next' body'
        Nothing => (e, next)
inlineIn inl path depth next (ALet fc x v b)
    = let (v', n1) = inlineIn inl path depth next v
          (b', n2) = inlineIn inl path depth n1 b in
          (ALet fc x v' b', n2)
inlineIn inl path depth next (AConCase fc sc alts def)
    = let (alts', n1) = foldl (\(acc, n), (MkAConAlt c ci t as b) =>
                                 let (b', n') = inlineIn inl path depth n b in (acc :< MkAConAlt c ci t as b', n'))
                              ([<], next) alts
          (def', n2) = inlineMaybe inl path depth n1 def
          in (AConCase fc sc (alts' <>> []) def', n2)
inlineIn inl path depth next (AConstCase fc sc alts def)
    = let (alts', n1) = foldl (\(acc, n), (MkAConstAlt c b) =>
                                 let (b', n') = inlineIn inl path depth n b in (acc :< MkAConstAlt c b', n'))
                              ([<], next) alts
          (def', n2) = inlineMaybe inl path depth n1 def
          in (AConstCase fc sc (alts' <>> []) def', n2)
inlineIn _ _ _ next e = (e, next)

inlineMaybe inl path depth next Nothing = (Nothing, next)
inlineMaybe inl path depth next (Just d) = let (d', n) = inlineIn inl path depth next d in (Just d', n)

------------------------------------------------------------------------
-- The simplification

data Known
  = ||| made by this constructor, with these arguments
    KCon Name ConInfo (List AVar)
  | ||| a closure of the function, with these arguments, missing one
    KPart Name (List AVar)
  | ||| a `Maybe` of an element: its presence (a C integer) and its fields
    ||| (C numbers), for the record `c` or the primitive (Nothing)
    KOpt AVar (Maybe Name) (List AVar)

record St where
  constructor MkSt
  next : Int
  known : SortedMap Int Known
  ren : SortedMap Int AVar
  lits : SortedMap Int Bits64
  recs : FlatRecords
  byShape : SortedMap (Nat, Int) (List Name)
  ||| the variables made by a constructor where the code is: in a branch of
  ||| a case on the variable, or after a projection of one of its fields
  ||| (see `hoist`).  The other fields are about the binders of the
  ||| function, which are distinct, and hold wherever these are in scope;
  ||| this one is about variables bound before a branch, and is kept in the
  ||| branch only.
  cons : SortedMap Int Name

zeroOf : PrimType -> Constant
zeroOf DoubleType = Db 0.0
zeroOf Bits64Type = B64 0
zeroOf _ = I64 0

fresh : St -> (Int, St)
fresh st = (st.next, { next $= (+ 1) } st)

-- What a value splits into: a record (its fields), a `Maybe` of a record or
-- of a primitive (the presence, then the fields), `Nothing` (of either), or
-- anything (a crash).
data Kind = KRec Name | KOptR Name | KOptP PrimType | KNothing | KAny

Eq Kind where
  KRec a == KRec b = a == b
  KOptR a == KOptR b = a == b
  KOptP a == KOptP b = a == b
  KNothing == KNothing = True
  KAny == KAny = True
  _ == _ = False

merge : Kind -> Kind -> Maybe Kind
merge KAny k = Just k
merge k KAny = Just k
merge KNothing (KOptR c) = Just (KOptR c)
merge KNothing (KOptP t) = Just (KOptP t)
merge (KOptR c) KNothing = Just (KOptR c)
merge (KOptP t) KNothing = Just (KOptP t)
merge a b = if a == b then Just a else Nothing

fieldTypes : St -> Kind -> List PrimType
fieldTypes st (KRec c) = maybe [] recFields (SortedMap.lookup c st.recs)
fieldTypes st (KOptR c) = IntType :: maybe [] recFields (SortedMap.lookup c st.recs)
fieldTypes st (KOptP t) = [IntType, t]
fieldTypes _ _ = []

var : St -> AVar -> AVar
var st v = renameVar st.ren v

-- The constructors of `Maybe` (see Compiler.Opts.Constructor).
nothingName : Name
nothingName = NS (mkNamespace "_builtin") (UN (Basic "NOTHING"))

justName : Name
justName = NS (mkNamespace "_builtin") (UN (Basic "JUST"))

isNothingCon : ConInfo -> Bool
isNothingCon NOTHING = True
isNothingCon _ = False

isJustCon : ConInfo -> Bool
isJustCon JUST = True
isJustCon _ = False

-- A `Maybe` made from a presence and fields (by `fromComps` in `split`, a
-- test of the presence giving Nothing or the Just of a record or of a
-- primitive): what is known of it, so that it is not split again.
compsOf : St -> ANF -> Maybe Known
compsOf st (AConstCase _ p [MkAConstAlt (I64 0) (ACon _ _ NOTHING _ [])] (Just j))
    = case j of
        ALet _ y (ACon _ c _ _ fs) (ACon _ _ JUST _ [ALocal y']) =>
          if y == y' && isJust (SortedMap.lookup c st.recs) then Just (KOpt p (Just c) fs) else Nothing
        ACon _ _ JUST _ [f] => Just (KOpt p Nothing [f])
        _ => Nothing
compsOf _ _ = Nothing

-- The layout of a variable bound to a literal.
litOf : St -> AVar -> Maybe Bits64
litOf st v = case var st v of
                  ALocal i => SortedMap.lookup i st.lits
                  ANull => Nothing

mutual
  -- The kind of the value of an expression (already simplified).
  kindOf : St -> ANF -> Maybe Kind
  kindOf st (ACon _ n ci _ as)
      = if isJust (SortedMap.lookup n st.recs) then Just (KRec n)
        else if isNothingCon ci then Just KNothing
        else if isJustCon ci
          then case as of
                 [ALocal y] => case SortedMap.lookup y st.known of
                                 Just (KCon c _ _) => if isJust (SortedMap.lookup c st.recs) then Just (KOptR c) else Nothing
                                 _ => Nothing
                 _ => Nothing
        else Nothing
  kindOf st (AV _ (ALocal v))
      = case SortedMap.lookup v st.known of
          Just (KCon c _ _) => if isJust (SortedMap.lookup c st.recs) then Just (KRec c) else Nothing
          Just (KOpt _ (Just c) _) => Just (KOptR c)
          Just (KOpt _ Nothing [_, f]) => Nothing
          _ => Nothing
  kindOf st (AExtPrim _ _ p (_ :: l :: _))
      = if isSlotPrim p "prim__slotGet"
           then case the (Maybe ElemShape) (litOf st l >>= elemShape st.byShape) of
                  Just (ERec c) => Just (KOptR c)
                  Just (EPrim t) => Just (KOptP t)
                  Nothing => Nothing
           else Nothing
  kindOf st (ALet _ _ v b) = if pure v then kindOf st b else Nothing
  kindOf st (AConCase _ _ alts def)
      = kinds st (map (\(MkAConAlt _ _ _ _ b) => b) alts ++ toList def)
  kindOf st (AConstCase _ _ alts def)
      = kinds st (map (\(MkAConstAlt _ b) => b) alts ++ toList def)
  kindOf st (ACrash _ _) = Just KAny
  kindOf _ _ = Nothing

  kinds : St -> List ANF -> Maybe Kind
  kinds st [] = Just KAny
  kinds st (b :: bs) = do k <- kindOf st b
                          r <- kinds st bs
                          merge k r

-- What a projection (see `hoist`), or a case of one alternative without a
-- default, makes known of the variable that it takes apart, for the code
-- after it.
madeBy : ANF -> SortedMap Int Name -> SortedMap Int Name
madeBy (AConCase _ (ALocal sc) [MkAConAlt c _ _ _ _] Nothing) cons = insert sc c cons
madeBy _ cons = cons

-- The projections of a field of a variable bound outside the expression
-- (not one of `inner`) that the expression makes, taken out of it where they
-- cannot fail: they can then be made before it, as they are pure.  A
-- projection (`case v of C ... => f`, without a default) cannot fail where
-- `v` is known to be made by `C` (`cons`, or an earlier projection made
-- unconditionally), or where the expression makes it unconditionally
-- (`guarded` is False: not in a branch).  In a branch, that it has a single
-- alternative only means that the other constructors are impossible there:
-- the type of `v` may depend on what the branch tests (`V b` with `b`
-- True, say), and taken out of it the projection would read the fields of
-- whatever `v` is.
hoist : SortedMap Int Name -> List Int -> Bool -> ANF -> (List (Int, ANF), ANF)
hoist cons inner guarded (ALet fc x v@(AConCase _ (ALocal sc) [MkAConAlt c _ _ as (AV _ (ALocal f))] Nothing) b)
    = if not (elem sc inner) && elem f as && (not guarded || SortedMap.lookup sc cons == Just c)
         then let (ps, b') = hoist (insert sc c cons) inner guarded b in ((x, v) :: ps, b')
         else let (ps, b') = hoist cons inner guarded b in (ps, ALet fc x v b')
hoist cons inner guarded (ALet fc x v b)
    = let (pv, v') = hoist cons inner guarded v
          (pb, b') = hoist (if guarded then cons else madeBy v cons) inner guarded b in
          (pv ++ pb, ALet fc x v' b')
hoist cons inner _ (AConCase fc sc alts def)
    = let rs = map (\(MkAConAlt n ci tg as b) => let (ps, b') = hoist cons inner True b in (ps, MkAConAlt n ci tg as b')) alts
          rd = map (hoist cons inner True) def in
          (concatMap fst rs ++ maybe [] fst rd, AConCase fc sc (map snd rs) (map snd rd))
hoist cons inner _ (AConstCase fc sc alts def)
    = let rs = map (\(MkAConstAlt c b) => let (ps, b') = hoist cons inner True b in (ps, MkAConstAlt c b')) alts
          rd = map (hoist cons inner True) def in
          (concatMap fst rs ++ maybe [] fst rd, AConstCase fc sc (map snd rs) (map snd rd))
hoist _ _ _ e = ([], e)

-- The component `k` (of the types `ts`) of an expression of the kind
-- `kind` (see `kindOf`).
comp : AVar -> St -> Kind -> Nat -> PrimType -> ANF -> ANF
comp sn st kind k t e@(ACon fc n ci _ as)
    = if isNothingCon ci then APrimVal fc (zeroOf t)
      else case kind of
             KRec _ => maybe (ACrash fc "flat: field") (AV fc) (getAt k as)
             _ => -- a Just of a known record
                  if k == 0 then APrimVal fc (I64 1) else
                    case as of
                      [ALocal y] => case SortedMap.lookup y st.known of
                                      Just (KCon _ _ fs) => maybe (ACrash fc "flat: field") (AV fc) (getAt (pred k) fs)
                                      _ => ACrash fc "flat: field"
                      _ => ACrash fc "flat: field"
comp sn st kind k t (AV fc (ALocal v))
    = case SortedMap.lookup v st.known of
        Just (KCon _ _ fs) => maybe (ACrash fc "flat: field") (AV fc) (getAt k fs)
        Just (KOpt p _ fs) => if k == 0 then AV fc p else maybe (ACrash fc "flat: field") (AV fc) (getAt (pred k) fs)
        _ => ACrash fc "flat: field"
comp sn st kind k t (AExtPrim fc lz p (_ :: l :: arr :: i :: _))
    = if k == 0 then AExtPrim fc lz (flatPrim "slotPresent") [l, arr, i, sn]
         else AExtPrim fc lz (flatPrim ("slotField" ++ typeLetter t ++ show (pred k))) [l, arr, i, sn]
comp sn st kind k t (ALet fc x v b) = ALet fc x v (comp sn st kind k t b)
comp sn st kind k t (AConCase fc sc alts def)
    = AConCase fc sc (map (\(MkAConAlt n ci tg as b) => MkAConAlt n ci tg as (comp sn st kind k t b)) alts)
               (map (comp sn st kind k t) def)
comp sn st kind k t (AConstCase fc sc alts def)
    = AConstCase fc sc (map (\(MkAConstAlt c b) => MkAConstAlt c (comp sn st kind k t b)) alts)
                 (map (comp sn st kind k t) def)
comp sn st kind k t e = e

-- The snapshot of the element that an expression reads (see `split`): at
-- the read, `slotSnap`, nothing (NULL) elsewhere.
snapOf : ANF -> ANF
snapOf (AExtPrim fc lz p (_ :: l :: arr :: i :: _))
    = if isSlotPrim p "prim__slotGet" then AExtPrim fc lz (flatPrim "slotSnap") [l, arr, i]
         else AV fc ANull
snapOf (ALet fc x v b) = ALet fc x v (snapOf b)
snapOf (AConCase fc sc alts def)
    = AConCase fc sc (map (\(MkAConAlt n ci tg as b) => MkAConAlt n ci tg as (snapOf b)) alts) (map snapOf def)
snapOf (AConstCase fc sc alts def)
    = AConstCase fc sc (map (\(MkAConstAlt c b) => MkAConstAlt c (snapOf b)) alts) (map snapOf def)
snapOf (ACrash fc m) = ACrash fc m
snapOf e = AV EmptyFC ANull

-- Does the expression read an element (in tail position)?
readsSlot : ANF -> Bool
readsSlot (AExtPrim _ _ p _) = isSlotPrim p "prim__slotGet"
readsSlot (ALet _ _ _ b) = readsSlot b
readsSlot (AConCase _ _ alts def) = any (\(MkAConAlt _ _ _ _ b) => readsSlot b) alts || maybe False readsSlot def
readsSlot (AConstCase _ _ alts def) = any (\(MkAConstAlt _ b) => readsSlot b) alts || maybe False readsSlot def
readsSlot _ = False

-- An expression with all its binders made fresh.
refresh : St -> ANF -> (ANF, St)
refresh st e
    = let bs = nub (binders e)
          ren = fromList (zipWith (\b, k => (b, ALocal (st.next + k))) bs [0 .. cast (length bs)]) in
          (rename ren e, { next $= (+ (cast (length bs) + 1)) } st)

-- How often the variable `y` occurs in an expression: in all, and as the
-- array of an access to the slots of an array.
occurrences : Int -> ANF -> (Nat, Nat)
occurrences y e = go e (0, 0)
  where
    isY : AVar -> Bool
    isY (ALocal i) = i == y
    isY ANull = False
    count : List AVar -> Nat
    count as = length (filter isY as)
    -- (the position of the array among the arguments of an access)
    arrayAt : Name -> Maybe Nat
    arrayAt p = if isSlotPrim p "prim__slotGet" || isSlotPrim p "prim__slotSet" then Just 2
                else if isJust (flatPrimName p) then Just 1
                else Nothing
    go : ANF -> (Nat, Nat) -> (Nat, Nat)
    go (AV _ v) (n, a) = (n + count [v], a)
    go (AAppName _ _ _ as) (n, a) = (n + count as, a)
    go (AUnderApp _ _ _ as) (n, a) = (n + count as, a)
    go (AApp _ _ f x) (n, a) = (n + count [f, x], a)
    go (ACon _ _ _ _ as) (n, a) = (n + count as, a)
    go (AOp _ _ _ as) (n, a) = (n + count (toList as), a)
    go (AExtPrim _ _ p as) (n, a)
        = (n + count as, a + maybe 0 (\k => maybe 0 (\v => count [v]) (getAt k as)) (arrayAt p))
    go (ALet _ _ v b) acc = go b (go v acc)
    go (AConCase _ (ALocal s) alts def) (n, a)
        = foldl (\acc, (MkAConAlt _ _ _ _ b) => go b acc)
                (maybe id go def (if s == y then S n else n, a)) alts
    go (AConCase _ ANull alts def) acc
        = foldl (\acc', (MkAConAlt _ _ _ _ b) => go b acc') (maybe id go def acc) alts
    go (AConstCase _ (ALocal s) alts def) (n, a)
        = foldl (\acc, (MkAConstAlt _ b) => go b acc)
                (maybe id go def (if s == y then S n else n, a)) alts
    go (AConstCase _ ANull alts def) acc
        = foldl (\acc', (MkAConstAlt _ b) => go b acc') (maybe id go def acc) alts
    go _ acc = acc

-- Does the expression read an element (anywhere)?
readsElem : ANF -> Bool
readsElem (AExtPrim _ _ p _) = isSlotPrim p "prim__slotGet" || flatPrimName p == Just "slotSnap"
readsElem (ALet _ _ v b) = readsElem v || readsElem b
readsElem (AConCase _ _ alts def) = any (\(MkAConAlt _ _ _ _ b) => readsElem b) alts || maybe False readsElem def
readsElem (AConstCase _ _ alts def) = any (\(MkAConstAlt _ b) => readsElem b) alts || maybe False readsElem def
readsElem _ = False

-- Is the expression a snapshot of an element (see `snapOf`): `slotSnap` in
-- the branches that read the element, nothing (NULL) in the others?
isSnap : ANF -> Bool
isSnap (AExtPrim _ _ p _) = flatPrimName p == Just "slotSnap"
isSnap (AV _ ANull) = True
isSnap (ACrash _ _) = True
isSnap (ALet _ _ v b) = not (readsElem v) && isSnap b
isSnap (AConCase _ _ alts def) = all (\(MkAConAlt _ _ _ _ b) => isSnap b) alts && maybe True isSnap def
isSnap (AConstCase _ _ alts def) = all (\(MkAConstAlt _ b) => isSnap b) alts && maybe True isSnap def
isSnap _ = False

-- The `let`s of an expression (of a value split, see `split`) that its
-- components share: those on its spine (not in the values of other
-- `let`s) of a snapshot of an element (see `snapOf`: an element read in a
-- branch of the value, by its fields), and of an array that it accesses
-- (used only as such, so a value: the array of an `IOArray`, projected in
-- the branch of a bounds test, say).  Each is made once, a component
-- itself, in the branches where the value makes it, rather than in every
-- component: the components of a value read from a shared array read its
-- fields from one snapshot, so that they are those of one write; an array
-- is projected once.  (They cannot be made before the value, in every
-- branch, as a projection that is made in a branch only may fail in the
-- others, see `hoist`, and so may an element read out of bounds.)  Nothing
-- when another `let` reads an element (a read of a layout that is not
-- known, say): copied in every component, it would read it again.
sharedLets : ANF -> ANF -> Maybe (List Int)
sharedLets whole (ALet _ y v b)
    = do rest <- sharedLets whole b
         if readsElem v
            then if isSnap v then Just (y :: rest) else Nothing
            else let (n, a) = occurrences y whole in
                     Just (if n > 0 && n == a then y :: rest else rest)
sharedLets whole (AConCase _ _ alts def)
    = do as <- traverse (\(MkAConAlt _ _ _ _ b) => sharedLets whole b) alts
         d <- maybe (Just []) (sharedLets whole) def
         Just (concat as ++ d)
sharedLets whole (AConstCase _ _ alts def)
    = do as <- traverse (\(MkAConstAlt _ b) => sharedLets whole b) alts
         d <- maybe (Just []) (sharedLets whole) def
         Just (concat as ++ d)
sharedLets _ _ = Just []

-- The component of the shared `let` of `r` (see `sharedLets`) of an
-- expression: `r`, in the branches where the expression binds it, nothing
-- (NULL) in the others.
sharedComp : Int -> ANF -> ANF
sharedComp r (ALet fc y v b)
    = if y == r then ALet fc y v (AV fc (ALocal y)) else ALet fc y v (sharedComp r b)
sharedComp r (AConCase fc sc alts def)
    = AConCase fc sc (map (\(MkAConAlt n ci tg as b) => MkAConAlt n ci tg as (sharedComp r b)) alts)
               (map (sharedComp r) def)
sharedComp r (AConstCase fc sc alts def)
    = AConstCase fc sc (map (\(MkAConstAlt c b) => MkAConstAlt c (sharedComp r b)) alts)
                 (map (sharedComp r) def)
sharedComp _ (ACrash fc m) = ACrash fc m
sharedComp _ _ = AV EmptyFC ANull

-- An expression with the `let`s of `sub` (shared, see `sharedLets`)
-- dropped, and their variables those of `sub` (their components).
unshare : SortedMap Int AVar -> ANF -> ANF
unshare sub e = rename sub (dropLets e)
  where
    dropLets : ANF -> ANF
    dropLets (ALet fc y v b) = if isJust (SortedMap.lookup y sub) then dropLets b else ALet fc y v (dropLets b)
    dropLets (AConCase fc sc alts def)
        = AConCase fc sc (map (\(MkAConAlt n ci tg as b) => MkAConAlt n ci tg as (dropLets b)) alts) (map dropLets def)
    dropLets (AConstCase fc sc alts def)
        = AConstCase fc sc (map (\(MkAConstAlt c b) => MkAConstAlt c (dropLets b)) alts) (map dropLets def)
    dropLets e = e

mutual
  simp : St -> ANF -> (ANF, St)
  simp st (AV fc v) = (AV fc (var st v), st)
  simp st (AAppName fc lz n as) = (AAppName fc lz n (map (var st) as), st)
  simp st (AUnderApp fc n m as) = (AUnderApp fc n m (map (var st) as), st)
  -- (a closure made in the function, applied to its last argument: the call)
  simp st (AApp fc lz f a)
      = case var st f of
          ALocal fv => case SortedMap.lookup fv st.known of
            Just (KPart g as) => (AAppName fc lz g (as ++ [var st a]), st)
            _ => (AApp fc lz (var st f) (var st a), st)
          ANull => (AApp fc lz (var st f) (var st a), st)
  simp st (ACon fc n ci t as) = (ACon fc n ci t (map (var st) as), st)
  simp st (AOp fc lz op as) = (AOp fc lz op (map (var st) as), st)
  simp st (AExtPrim fc lz p as)
      = let as' = map (var st) as in (write st fc lz p as', st)
  -- (the lets of a let are floated out, so that what it binds is seen: the
  -- binders are distinct in a function)
  simp st (ALet fc x (ALet fc' y v1 b1) b) = simp st (ALet fc' y v1 (ALet fc x b1 b))
  simp st (ALet fc x v b)
      = let (v', st1) = simp st v
            st2 = remember ({ cons $= madeBy v' } st1) x v' in
            -- (a constructor, or a variable, is known already: not split)
            if isCon v' then let (b', st3) = simp st2 b in (ALet fc x v' b', st3) else
            -- (nor is an element made from its components, see `fromComps`)
            case compsOf st2 v' of
              Just kn => let (b', st3) = simp ({ known $= insert x kn } st2) b in (ALet fc x v' b', st3)
              Nothing =>
                case kindOf st2 v' of
                  Just kind@(KRec _) => split st2 fc x v' kind b
                  Just kind@(KOptR _) => split st2 fc x v' kind b
                  Just kind@(KOptP _) => split st2 fc x v' kind b
                  _ => let (b', st3) = simp st2 b in (ALet fc x v' b', st3)
  simp st (AConCase fc sc alts def)
      = let sc' = var st sc in
            case sc' of
              ALocal s => case SortedMap.lookup s st.known of
                Just (KCon n _ as) => known st fc sc' n as alts def
                Just (KOpt p mc fs) => option st fc sc' p mc fs alts def
                _ => plainCase st fc sc' alts def
              ANull => plainCase st fc sc' alts def
  simp st (AConstCase fc sc alts def)
      = let sc' = var st sc
            (alts', st1) = simpConstAlts st alts
            (def', st2) = simpMaybe st1 def in
            (AConstCase fc sc' alts' def', st2)
  simp st e = (e, st)

  -- A branch of a case, simplified with `st`: what it makes known of the
  -- constructors of the variables (`cons`) holds there only, and is as
  -- `outer` had it after it.
  branch : St -> St -> ANF -> (ANF, St)
  branch outer st b = let (b', st') = simp st b in (b', { cons := outer.cons } st')

  simpMaybe : St -> Maybe ANF -> (Maybe ANF, St)
  simpMaybe st Nothing = (Nothing, st)
  simpMaybe st (Just e) = let (e', st') = branch st st e in (Just e', st')

  simpConstAlts : St -> List AConstAlt -> (List AConstAlt, St)
  simpConstAlts st [] = ([], st)
  simpConstAlts st (MkAConstAlt c b :: rest)
      = let (b', st1) = branch st st b
            (rest', st2) = simpConstAlts st1 rest in
            (MkAConstAlt c b' :: rest', st2)

  -- (in the branch of a constructor, the scrutinee is made by it)
  simpAlts : St -> AVar -> List AConAlt -> (List AConAlt, St)
  simpAlts st sc [] = ([], st)
  simpAlts st sc (MkAConAlt n ci t as b :: rest)
      = let inB = case sc of
                    ALocal s => { cons $= insert s n } st
                    ANull => st
            (b', st1) = branch st inB b
            (rest', st2) = simpAlts st1 sc rest in
            (MkAConAlt n ci t as b' :: rest', st2)

  plainCase : St -> FC -> AVar -> List AConAlt -> Maybe ANF -> (ANF, St)
  plainCase st fc sc alts def
      = let (alts', st1) = simpAlts st sc alts
            (def', st2) = simpMaybe st1 def in
            (AConCase fc sc alts' def', st2)

  -- A case on a constructor made in the function: its branch.
  known : St -> FC -> AVar -> Name -> List AVar -> List AConAlt -> Maybe ANF -> (ANF, St)
  known st fc sc n as alts def
      = case find (\(MkAConAlt n' _ _ _ _) => n' == n) alts of
          Just (MkAConAlt _ _ _ bs b) =>
            if length bs /= length as then plainCase st fc sc alts def else
              simp ({ ren $= \r => foldl (\m, (bv, a) => insert bv a m) r (zip bs as) } st) b
          Nothing => case def of
                       Just d => simp st d
                       Nothing => (ACrash fc "flat: no branch", st)

  -- A case on a `Maybe` of an element read (`sc`, of the presence `p`): a
  -- test of its presence.
  option : St -> FC -> AVar -> AVar -> Maybe Name -> List AVar -> List AConAlt -> Maybe ANF -> (ANF, St)
  option st fc sc p mc fs alts def
      = let nothingAlt = find (\(MkAConAlt _ ci _ _ _) => isNothingCon ci) alts
            nothingB = case nothingAlt of
                         Just (MkAConAlt _ _ _ _ b) => Just b
                         Nothing => def
            justAlt = find (\(MkAConAlt _ ci _ _ _) => isJustCon ci) alts in
            case justAlt of
              Nothing => case the (Maybe AConAlt, Maybe ANF) (nothingAlt, def) of
                           -- (a `Just` takes the default)
                           (Just (MkAConAlt _ _ _ _ b), Just d) =>
                             let (b', st1) = branch st st b
                                 (d', st2) = branch st st1 d in
                                 (AConstCase fc p [MkAConstAlt (I64 0) b'] (Just d'), st2)
                           -- (one branch for every element: the default,
                           -- or Nothing's when the case has no other one)
                           _ => case the (Maybe ANF) nothingB of
                                  Just b => simp st b
                                  Nothing => (ACrash fc "flat: no branch", st)
              Just (MkAConAlt _ _ _ [y] jb) =>
                let (nb', st1) = simpMaybe st nothingB
                    (jb', st2) = justBody st1 y mc fs jb
                    st3 = { cons := st.cons } st2 in
                    (AConstCase fc p [MkAConstAlt (I64 0) (fromMaybe (ACrash fc "flat: no branch") nb')] (Just jb'), st3)
              -- (a case on the value itself, not on its presence)
              Just _ => plainCase st fc sc alts def

  -- The branch of a `Just` of an element: the element `y` is the record
  -- made from the fields (made only if it is used as a value, see `dce`),
  -- or the primitive.
  justBody : St -> Int -> Maybe Name -> List AVar -> ANF -> (ANF, St)
  justBody st y (Just c) fs b
      = case SortedMap.lookup c st.recs of
          Just r => let st1 = { known $= insert y (KCon c r.recInfo fs) } st
                        (b', st2) = simp st1 b in
                        (ALet emptyFC y (ACon emptyFC c r.recInfo (Just r.recTag) fs) b', st2)
          Nothing => simp st b
  justBody st y Nothing [f] b = simp ({ ren $= insert y f } st) b
  justBody st y Nothing _ b = simp st b

  -- Split the value of `x` into its components.
  split : St -> FC -> Int -> ANF -> Kind -> ANF -> (ANF, St)
  split st fc x v0 kind b
      = let -- (the projections in the value that cannot fail, of the
            -- array of an `IOArray` say, are made once, before the
            -- components; the reads of elements not used, the value of an
            -- element read by its fields say, are dropped first.  The
            -- other `let`s are kept: what is known of a variable may be
            -- one of them, a field of a record split, say)
            (projs, v1) = hoist st.cons (binders v0) False (dceWith (\v => pure v && readsElem v) v0) in
            case sharedLets v1 v1 of
              Nothing => let (b', st') = simp st b in (ALet fc x v0 b', st')
              Just shared => splitWith st fc x projs v1 shared kind b

  -- (see `split`)
  splitWith : St -> FC -> Int -> List (Int, ANF) -> ANF -> List Int -> Kind -> ANF -> (ANF, St)
  splitWith st fc x projs v1 shared kind b
      = let -- (the `let`s that the components share, a snapshot or the
            -- array of an `IOArray` projected in the branch of a bounds
            -- test say, are components, made once)
            (shs, sub, stS) = foldl (\(acc, sub, s), r =>
                                       let (c, s') = refresh s (dce (sharedComp r (unshare sub v1)))
                                           (cv, s'') = fresh s' in
                                           (acc :< (cv, c), insert r (ALocal cv) sub, s''))
                                    (the (SnocList (Int, ANF)) [<], the (SortedMap Int AVar) empty, st)
                                    shared
            v = unshare sub v1
            ts = fieldTypes st kind
            -- (an element read is first taken whole, its snapshot: nothing
            -- when the array is accessed inline, else its value, read once
            -- under the lock of a shared array, so that its fields are those
            -- of one write)
            (snap, st0) = the (List (Int, ANF), St) $
                            if readsSlot v
                               then let (c, s') = refresh stS (snapOf v)
                                        (sv, s'') = fresh s' in
                                        ([(sv, c)], s'')
                               else ([], stS)
            sn = maybe ANull (ALocal . fst) (head' snap)
            -- (the components, with their binders made fresh)
            (cs0, st1) = foldl (\(acc, s), (k, t) =>
                                  let (c, s') = refresh s (comp sn s kind k t v)
                                      (cv, s'') = fresh s' in
                                      (acc :< (cv, c), s''))
                              ([<], st0) (zip [0 .. length ts] ts)
            cvs = map (ALocal . fst) (cs0 <>> [])
            cs = the (SnocList (Int, ANF)) (shs <>< (snap ++ (cs0 <>> [])))
            kn = case kind of
                   KRec c => KCon c (maybe DATACON recInfo (SortedMap.lookup c st.recs)) cvs
                   KOptR c => KOpt (fromMaybe ANull (head' cvs)) (Just c) (drop 1 cvs)
                   KOptP _ => KOpt (fromMaybe ANull (head' cvs)) Nothing (drop 1 cvs)
                   _ => KCon (UN (Basic "?")) DATACON []
            -- (the projections taken out are made before the code after)
            (b', st2) = simp ({ known $= insert x kn,
                                cons $= \m => foldl (\m', (_, p) => madeBy p m') m projs } st1) b
            -- (the value itself, where it is used as such, is made from the
            -- components when it reads an element and the code after uses
            -- them too: read again, it could be another write's)
            used = uses b' empty
            (whole, st3) = the (ANF, St) $
                             if readsSlot v && any (\cv => case cv of
                                                              ALocal i => isJust (SortedMap.lookup i used)
                                                              ANull => False) cvs
                                then fromComps st2 fc kind cvs else (v, st2) in
            (foldr (\(px, pv), acc => ALet fc px pv acc)
                   (foldr (\(cv, c), acc => ALet fc cv c acc) (ALet fc x whole b') (cs <>> []))
                   projs, st3)

  -- A `Maybe` of an element made from its components (see `split`): its
  -- presence and its fields.  (See `compsOf` for what is known of it.)
  fromComps : St -> FC -> Kind -> List AVar -> (ANF, St)
  fromComps st fc (KOptR c) (p :: fs)
      = case SortedMap.lookup c st.recs of
          Just r => let (y, st') = fresh st in
                        (AConstCase fc p [MkAConstAlt (I64 0) (ACon fc nothingName NOTHING (Just 0) [])]
                                    (Just (ALet fc y (ACon fc c r.recInfo (Just r.recTag) fs)
                                                (ACon fc justName JUST (Just 1) [ALocal y]))), st')
          Nothing => (ACrash fc "flat: no record", st)
  fromComps st fc (KOptP _) [p, f]
      = (AConstCase fc p [MkAConstAlt (I64 0) (ACon fc nothingName NOTHING (Just 0) [])]
                    (Just (ACon fc justName JUST (Just 1) [f])), st)
  fromComps st fc _ _ = (ACrash fc "flat: no element", st)

  isCon : ANF -> Bool
  isCon (ACon _ _ _ _ _) = True
  isCon (AV _ _) = True
  isCon _ = False

  -- What a `let` makes known of its variable.
  remember : St -> Int -> ANF -> St
  remember st x (ACon _ n ci _ as) = { known $= insert x (KCon n ci as) } st
  remember st x (AUnderApp _ g 1 as) = { known $= insert x (KPart g as) } st
  remember st x (APrimVal _ (B64 c)) = { lits $= insert x c } st
  remember st x (AV _ y) = { ren $= insert x y } st
  remember st _ _ = st

  -- A write of a `Just` of a record or of a primitive known here: from the
  -- fields, or the record's cell, without the `Just`.
  write : St -> FC -> Maybe LazyReason -> Name -> List AVar -> ANF
  write st fc lz p as@[ty, l, arr, i, ALocal x, w]
      = if not (isSlotPrim p "prim__slotSet") then AExtPrim fc lz p as else
          case the (Maybe Known, Maybe ElemShape) (SortedMap.lookup x st.known, litOf st l >>= elemShape st.byShape) of
            (Just (KCon _ JUST [y]), Just (ERec c)) =>
              case y of
                ALocal yv => case SortedMap.lookup yv st.known of
                  Just (KCon c' _ fs) =>
                    if c' == c
                       then let ts = maybe [] recFields (SortedMap.lookup c st.recs) in
                                AExtPrim fc lz (flatPrim ("slotStore" ++ concatMap typeLetter ts)) ([l, arr, i] ++ fs)
                       else AExtPrim fc lz p as
                  _ => AExtPrim fc lz (flatPrim "slotStoreElem") [l, arr, i, y]
                ANull => AExtPrim fc lz p as
            (Just (KCon _ JUST [y]), Just (EPrim t)) =>
              AExtPrim fc lz (flatPrim ("slotStore" ++ typeLetter t)) [l, arr, i, y]
            _ => AExtPrim fc lz p as
  -- (a write of an element inlined, of a record known here: from its fields)
  write st fc lz p as@[l, arr, i, ALocal y]
      = if flatPrimName p /= Just "slotStoreElem" then AExtPrim fc lz p as else
          case the (Maybe Known, Maybe ElemShape) (SortedMap.lookup y st.known, litOf st l >>= elemShape st.byShape) of
            (Just (KCon c' _ fs), Just (ERec c)) =>
              if c' == c
                 then let ts = maybe [] recFields (SortedMap.lookup c st.recs) in
                          AExtPrim fc lz (flatPrim ("slotStore" ++ concatMap typeLetter ts)) ([l, arr, i] ++ fs)
                 else AExtPrim fc lz p as
            _ => AExtPrim fc lz p as
  write st fc lz p as = AExtPrim fc lz p as

------------------------------------------------------------------------
-- The pass

||| The definitions with the elements of flat arrays kept out of values (see
||| above): the functions that touch them are rewritten.  `recs` are the
||| records that the arrays may hold.
export
flatOpt : FlatRecords -> List (Name, ANFDef) -> List (Name, ANFDef)
flatOpt recs defs = zipWith keep defs (rounds 3 defs)
  where
    byShape : SortedMap (Nat, Int) (List Name)
    byShape = foldl (\m, (c, r) => let k = (length r.recFields, r.recTag) in
                                       insert k (c :: fromMaybe [] (SortedMap.lookup k m)) m)
                    empty (SortedMap.toList recs)

    rewriteDef : SortedMap Name (List Int, ANF) -> SortedMap (Nat, Int) (List Name) -> Name -> ANFDef -> ANFDef
    rewriteDef inl byShape n d@(MkAFun args b)
        = if not (touches recs b || callsAny inl b) then d else
            let next0 = 1 + max (foldl max 0 args) (maxVar b)
                (b1, next1) = inlineIn inl [n] 4 next0 b
                -- (the simplification makes calls of the closures that the
                -- function applies, which are inlined in turn)
                (b2, st2) = simp (MkSt next1 empty empty empty recs byShape empty) b1
                (b3, next3) = inlineIn inl [n] 4 st2.next (dce b2) in
                if not (accesses b3) then MkAFun args b3 else
                  let (b4, _) = simp (MkSt next3 empty empty empty recs byShape empty) b3 in
                      MkAFun args (dce b4)
    rewriteDef _ _ _ d = d

    -- A function that does not access the elements of flat arrays by their
    -- fields in the end is kept as it was, though its rewritten body is what
    -- is inlined: inlining in the functions that only use arrays of values,
    -- or records, is not this pass's job (with them, the compiler's C grows
    -- by 13%, by 40% with the functions on records too).
    keep : (Name, ANFDef) -> (Name, ANFDef) -> (Name, ANFDef)
    keep d (n, r@(MkAFun _ b)) = if usesFlat b then (n, r) else d
    keep d _ = d

    -- (in rounds: a function rewritten may be one to inline in the next,
    -- the copy of an access that applied a closure, say)
    rounds : Nat -> List (Name, ANFDef) -> List (Name, ANFDef)
    rounds Z ds = ds
    rounds (S k) ds
        = let funs : List (Name, (List Int, ANF))
                   = mapMaybe (\(n, d) => case d of
                                  MkAFun args b => Just (n, (args, b))
                                  _ => Nothing) ds
              -- the functions to inline: small, not recursive, touching
              -- flat elements
              inl = fromList (filter (\(n, (_, b)) => size b <= inlineLimit && not (calls n b) && touches recs b) funs) in
              if null (keys inl) then ds else
                rounds k (map (\(n, d) => (n, rewriteDef inl byShape n d)) ds)

||| The `ConInfo` of the constructors, as their applications and matches have
||| it.
export
conInfos : List (Name, ANFDef) -> SortedMap Name ConInfo
conInfos defs = foldl (\m, (_, d) => case d of
                                        MkAFun _ b => go b m
                                        _ => m) empty defs
  where
    go : ANF -> SortedMap Name ConInfo -> SortedMap Name ConInfo
    go (ACon _ n ci _ _) m = insert n ci m
    go (ALet _ _ v b) m = go b (go v m)
    go (AConCase _ _ alts def) m
        = foldl (\m', (MkAConAlt n ci _ _ b) => go b (insert n ci m')) (maybe m (\d => go d m) def) alts
    go (AConstCase _ _ alts def) m
        = foldl (\m', (MkAConstAlt _ b) => go b m') (maybe m (\d => go d m) def) alts
    go _ m = m
