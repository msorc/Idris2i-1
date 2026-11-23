||| Deriving `Eq` implementations using reflection
||| You can for instance define:
||| ```
||| data Tree a = Leaf a | Node (Tree a) (Tree a)
||| treeEq : Eq a => Eq (Tree a)
||| treeEq = %runElab derive
||| ```
|||
||| Two values are equal when they are built with the same constructor and
||| their explicit fields are equal, compared from left to right. Erased
||| fields are not compared. A field of the type being defined is compared
||| with a direct recursive call, so the comparison is total when the type is
||| finite; a field which mentions the type inside another type constructor
||| (`List (Tree a)`) needs the implementation being defined as a `%hint`.

module Deriving.Eq

import public Language.Reflection

import public Deriving.Common

import public Data.Maybe

%language ElabReflection
%default total

||| Build an `Eq` implementation from its `(==)`
public export
fromEq : (ty -> ty -> Bool) -> Eq ty
fromEq eq = MkEq eq (\ x, y => not (eq x y))

||| The comparison of two fields, given the function being defined
public export
eqField : (fn : Name) -> (t : Name) -> (mutualWith : List Name) ->
          TTImp -> TTImp -> TTImp -> TTImp
eqField fn t mutualWith ty x y
  = let fc = emptyFC
        eq = apply fc (IVar fc `{Prelude.EqOrd.(==)}) [x, y] in
    case appView ty of
      Just (MkAppView (_, hd) _ _) =>
        if hd == t then apply fc (IVar fc fn) [x, y]
        else if any (\ n => mentions n ty) (t :: mutualWith)
          then IApp fc (IVar fc `{Builtin.assert_total}) eq
          else eq
      Nothing => eq

namespace Eq

  ||| Derive an implementation of Eq for a type constructor.
  ||| This can be used like so:
  ||| ```
  ||| data Tree a = Leaf a | Node (Tree a) (Tree a)
  ||| treeEq : Eq a => Eq (Tree a)
  ||| treeEq = %runElab derive
  ||| ```
  export
  derive : {default Private vis : Visibility} ->
           {default Total treq : TotalReq} ->
           {default [] mutualWith : List Name} ->
           Elab (Eq f)
  derive = do
    mutualWith <- map concat $ for mutualWith $ \ nm => map fst <$> getType nm

    -- The goal should have the shape (Eq t)
    Just (IApp _ (IVar _ eq) t) <- goal
      | _ => fail "Expected a goal of the form `Eq t`"
    when (`{Prelude.EqOrd.Eq} /= eq) $
      logMsg "derive.eq" 1 "Expected to derive Eq but got \{show eq}"
    logMsg "derive.eq" 1 "Deriving Eq for \{showPrec App $ mapTTImp cleanup t}"
    MkIsFamily f params cs <- isFamily t
    cons <- for cs $ \ (cn, ty) => comparableCon "Eq" f cn ty
    pairs <- distinctConPairs f (map fst cs)

    let fc = emptyFC
    let un = UN . Basic
    let fn = un ("eq" ++ show (dropNS f))
    let cls = flip map cons $ \ con =>
          let n = length con.fields
              xs = fieldNames "x" n
              ys = fieldNames "y" n
              cmps = compareFields (eqField fn f mutualWith) con.fields xs ys
              rhs = foldr1' (\ c, r => apply fc (IVar fc `{Prelude.Basics.(&&)}) [c, r])
                            `(True) cmps
          in PatClause fc
               (apply fc (IVar fc fn)
                  [ apply fc (IVar fc con.conName) (map (IBindVar fc) xs)
                  , apply fc (IVar fc con.conName) (map (IBindVar fc) ys) ])
               rhs
    -- Values built with different constructors are different
    let others = if null pairs then [] else
          [ PatClause fc (apply fc (IVar fc fn) [Implicit fc True, Implicit fc True]) `(False) ]
    let empty = if null cons then
          [ ImpossibleClause fc (apply fc (IVar fc fn) [IBindVar fc (un "x"), Implicit fc True]) ]
          else []
    let cls = cls ++ others ++ empty

    let used = nubNat (concatMap usedTypeArgs cons)
    let constraint = constraintOn `{Prelude.EqOrd.Eq} used
    let ty = MkTy fc (NoFC fn) $ withParams fc constraint params
           $ `(~(t) -> ~(t) -> Bool)
    logMsg "derive.eq.clauses" 1 $
      joinLines ("" :: ("  " ++ show (mapITy cleanup ty))
                      :: map (("  " ++) . showClause InDecl . mapClause cleanup) cls)

    check $ ILocal fc
      [ IClaim (MkFCVal fc (MkIClaimData MW vis [Totality treq] ty))
      , IDef fc fn cls
      ] `(fromEq ~(IVar fc fn))

  where
    -- foldr1, with a value for the empty list
    foldr1' : (a -> a -> a) -> a -> List a -> a
    foldr1' f z [] = z
    foldr1' f z [x] = x
    foldr1' f z (x :: xs) = f x (foldr1' f z xs)
