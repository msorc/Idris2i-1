||| Deriving `Ord` implementations using reflection
||| You can for instance define:
||| ```
||| data Tree a = Leaf a | Node (Tree a) (Tree a)
||| %hint
||| treeEq : Eq a => Eq (Tree a)
||| treeEq = %runElab derive
||| treeOrd : Ord a => Ord (Tree a)
||| treeOrd = %runElab derive
||| ```
|||
||| Values built with different constructors are ordered as the constructors
||| are declared; values built with the same constructor are ordered
||| lexicographically by their explicit fields. Erased fields are not
||| compared. `Ord` needs an `Eq` implementation of the same type, which
||| `Deriving.Eq` can derive: it must be consistent with `compare`.

module Deriving.Ord

import public Language.Reflection

import public Deriving.Common

import public Data.Maybe

%language ElabReflection
%default total

||| Build an `Ord` implementation from its `compare`
public export
fromCompare : Eq ty => (ty -> ty -> Ordering) -> Ord ty
fromCompare cmp
  = MkOrd cmp
          (\ x, y => cmp x y == LT)
          (\ x, y => cmp x y == GT)
          (\ x, y => cmp x y /= GT)
          (\ x, y => cmp x y /= LT)
          (\ x, y => if cmp x y == GT then x else y)
          (\ x, y => if cmp x y == LT then x else y)

||| Lexicographic combination: the first comparison, unless it says `EQ`
public export
thenCompare : Ordering -> Lazy Ordering -> Ordering
thenCompare EQ o = o
thenCompare o _ = o

||| The comparison of two fields, given the function being defined
public export
compareField : (fn : Name) -> (t : Name) -> (mutualWith : List Name) ->
               TTImp -> TTImp -> TTImp -> TTImp
compareField fn t mutualWith ty x y
  = let fc = emptyFC
        cmp = apply fc (IVar fc `{Prelude.EqOrd.compare}) [x, y] in
    case appView ty of
      Just (MkAppView (_, hd) _ _) =>
        if hd == t then apply fc (IVar fc fn) [x, y]
        else if any (\ n => mentions n ty) (t :: mutualWith)
          then IApp fc (IVar fc `{Builtin.assert_total}) cmp
          else cmp
      Nothing => cmp

namespace Ord

  ||| Derive an implementation of Ord for a type constructor.
  ||| An implementation of Eq for the same type must be available.
  ||| This can be used like so:
  ||| ```
  ||| data Tree a = Leaf a | Node (Tree a) (Tree a)
  ||| %hint
  ||| treeEq : Eq a => Eq (Tree a)
  ||| treeEq = %runElab derive
  ||| treeOrd : Ord a => Ord (Tree a)
  ||| treeOrd = %runElab derive
  ||| ```
  export
  derive : {default Private vis : Visibility} ->
           {default Total treq : TotalReq} ->
           {default [] mutualWith : List Name} ->
           Elab (Ord f)
  derive = do
    mutualWith <- map concat $ for mutualWith $ \ nm => map fst <$> getType nm

    -- The goal should have the shape (Ord t)
    Just (IApp _ (IVar _ ord) t) <- goal
      | _ => fail "Expected a goal of the form `Ord t`"
    when (`{Prelude.EqOrd.Ord} /= ord) $
      logMsg "derive.ord" 1 "Expected to derive Ord but got \{show ord}"
    logMsg "derive.ord" 1 "Deriving Ord for \{showPrec App $ mapTTImp cleanup t}"
    MkIsFamily f params cs <- isFamily t
    cons <- for cs $ \ (cn, ty) => comparableCon "Ord" f cn ty
    pairs <- distinctConPairs f (map fst cs)

    let fc = emptyFC
    let un = UN . Basic
    let fn = un ("compare" ++ show (dropNS f))
    let idxFn = un ("conIndex" ++ show (dropNS f))
    let cls = flip map cons $ \ con =>
          let n = length con.fields
              xs = fieldNames "x" n
              ys = fieldNames "y" n
              cmps = compareFields (compareField fn f mutualWith) con.fields xs ys
              rhs = foldr1' (\ c, r => apply fc (IVar fc `{Deriving.Ord.thenCompare}) [c, r])
                            `(EQ) cmps
          in PatClause fc
               (apply fc (IVar fc fn)
                  [ apply fc (IVar fc con.conName) (map (IBindVar fc) xs)
                  , apply fc (IVar fc con.conName) (map (IBindVar fc) ys) ])
               rhs
    -- Values built with different constructors are ordered as the
    -- constructors are declared
    let x = un "x"
    let y = un "y"
    let others = if null pairs then [] else
          [ PatClause fc (apply fc (IVar fc fn) [IBindVar fc x, IBindVar fc y])
              (apply fc (IVar fc `{Prelude.EqOrd.compare})
                 [ IApp fc (IVar fc idxFn) (IVar fc x)
                 , IApp fc (IVar fc idxFn) (IVar fc y) ]) ]
    let empty = if null cons then
          [ ImpossibleClause fc (apply fc (IVar fc fn) [IBindVar fc x, Implicit fc True]) ]
          else []
    let cls = cls ++ others ++ empty
    let idxCls = flip map (zip cons [0 .. length cons]) $ \ (con, i) =>
          PatClause fc
            (IApp fc (IVar fc idxFn)
               (apply fc (IVar fc con.conName)
                  (map (const (Implicit fc True)) con.fields)))
            (IPrimVal fc (BI (cast i)))

    let used = nubNat (concatMap usedTypeArgs cons)
    let constraint = constraintOn `{Prelude.EqOrd.Ord} used
    let ty = MkTy fc (NoFC fn) $ withParams fc constraint params
           $ `(~(t) -> ~(t) -> Ordering)
    let idxTy = MkTy fc (NoFC idxFn) $ withParams fc (const Nothing) params
              $ `(~(t) -> Integer)
    logMsg "derive.ord.clauses" 1 $
      joinLines ("" :: ("  " ++ show (mapITy cleanup ty))
                      :: map (("  " ++) . showClause InDecl . mapClause cleanup) cls)

    let idxDecls = if null pairs then [] else
          [ IClaim (MkFCVal fc (MkIClaimData MW vis [Totality treq] idxTy))
          , IDef fc idxFn idxCls ]
    check $ ILocal fc
      (idxDecls ++
      [ IClaim (MkFCVal fc (MkIClaimData MW vis [Totality treq] ty))
      , IDef fc fn cls
      ]) `(fromCompare ~(IVar fc fn))

  where
    -- foldr1, with a value for the empty list
    foldr1' : (a -> a -> a) -> a -> List a -> a
    foldr1' f z [] = z
    foldr1' f z [x] = x
    foldr1' f z (x :: xs) = f x (foldr1' f z xs)
