||| Deriving `DecEq` implementations using reflection
||| You can for instance define:
||| ```
||| data Tree a = Leaf a | Node (Tree a) (Tree a)
||| treeDecEq : DecEq a => DecEq (Tree a)
||| treeDecEq = %runElab derive
||| ```
|||
||| The derived `decEq` compares the explicit fields of two values built with
||| the same constructor from left to right, and refutes the equality of
||| values built with different constructors. It is total, without
||| assertions, for a type whose fields mention it only directly (a field of
||| type `Tree a`); a field which mentions it inside another type constructor
||| (`List (Tree a)`) needs the implementation being defined as a `%hint`,
||| and is compared under `assert_total`.
|||
||| An indexed family is supported when the indices of the types of its
||| constructors are made of constructors and variables (`Vect (S n) a`, but
||| not `Tree (l + r)`), and the implicit arguments its fields depend on occur
||| in them. Erased fields cannot be compared, so a constructor with an
||| explicit erased field makes the derivation fail.

module Deriving.DecEq

import public Decidable.Equality
import public Language.Reflection

import public Deriving.Common

import public Data.Maybe

%language ElabReflection
%default total

public export
[FromDecEq] (dec : (x1, x2 : t) -> Dec (x1 = x2)) => DecEq t where
  decEq = dec

||| Build a `DecEq` implementation from its `decEq`
public export
fromDecEq : ((x1, x2 : t) -> Dec (x1 = x2)) -> DecEq t
fromDecEq dec = FromDecEq @{dec}

||| The decision of the equality of two fields, given the function being defined
public export
decEqField : (fn : Name) -> (t : Name) -> (mutualWith : List Name) ->
             TTImp -> TTImp -> TTImp -> TTImp
decEqField fn t mutualWith ty x y
  = let fc = emptyFC
        dec = apply fc (IVar fc `{Decidable.Equality.Core.decEq}) [x, y] in
    case appView ty of
      Just (MkAppView (_, hd) _ _) =>
        if hd == t then apply fc (IVar fc fn) [x, y]
        else if any (\ n => mentions n ty) (t :: mutualWith)
          then IApp fc (IVar fc `{Builtin.assert_total}) dec
          else dec
      Nothing => dec

namespace DecEq

  ||| Derive an implementation of DecEq for a type constructor.
  ||| This can be used like so:
  ||| ```
  ||| data Tree a = Leaf a | Node (Tree a) (Tree a)
  ||| treeDecEq : DecEq a => DecEq (Tree a)
  ||| treeDecEq = %runElab derive
  ||| ```
  export
  derive : {default Private vis : Visibility} ->
           {default Total treq : TotalReq} ->
           {default [] mutualWith : List Name} ->
           Elab (DecEq f)
  derive = do
    mutualWith <- map concat $ for mutualWith $ \ nm => map fst <$> getType nm

    -- The goal should have the shape (DecEq t)
    Just (IApp _ (IVar _ deq) t) <- goal
      | _ => fail "Expected a goal of the form `DecEq t`"
    when (`{Decidable.Equality.Core.DecEq} /= deq) $
      logMsg "derive.deceq" 1 "Expected to derive DecEq but got \{show deq}"
    logMsg "derive.deceq" 1 "Deriving DecEq for \{showPrec App $ mapTTImp cleanup t}"
    MkIsFamily f params cs <- isFamily t
    cons <- for cs $ \ (cn, ty) => comparableCon "DecEq" f cn ty
    for_ cons $ \ con =>
      when (any ((== M0) . rig) con.fields) $
        fail $ "Can't derive DecEq for \{show (dropNS f)}: the constructor "
            ++ "\{show (dropNS con.conName)} has an erased field, whose value "
            ++ "cannot be compared"
    pairs <- distinctConPairs f (map fst cs)

    let fc = emptyFC
    let un = UN . Basic
    let fn = un ("decEq" ++ show (dropNS f))
    let h = un "h"
    -- \ h => case h of Refl => contra Refl
    let refute = \ contra =>
          IApp fc (IVar fc `{Prelude.Types.No}) $
            ILam fc MW ExplicitArg (Just h) (Implicit fc False) $
              ICase fc [] (IVar fc h) (Implicit fc False)
                [ PatClause fc (IVar fc `{Builtin.Refl})
                    (IApp fc (IVar fc contra) (IVar fc `{Builtin.Refl})) ]
    -- Decide the fields from left to right: once a pair is known to be
    -- equal, the types of the next ones agree
    let decide : List (TTImp, Name, Name) -> TTImp
        decide [] = IApp fc (IVar fc `{Prelude.Types.Yes}) (IVar fc `{Builtin.Refl})
        decide ((ty, x, y) :: rest)
          = let contra = un ("contra" ++ show (length rest)) in
            ICase fc [] (decEqField fn f mutualWith ty (IVar fc x) (IVar fc y))
                  (Implicit fc False)
              [ PatClause fc (IApp fc (IVar fc `{Prelude.Types.Yes}) (IVar fc `{Builtin.Refl}))
                  (decide rest)
              , PatClause fc (IApp fc (IVar fc `{Prelude.Types.No}) (IBindVar fc contra))
                  (refute contra)
              ]
    let same = flip map cons $ \ con =>
          let n = length con.fields
              xs = fieldNames "x" n
              ys = fieldNames "y" n
          in PatClause fc
               (apply fc (IVar fc fn)
                  [ apply fc (IVar fc con.conName) (map (IBindVar fc) xs)
                  , apply fc (IVar fc con.conName) (map (IBindVar fc) ys) ])
               (decide (zip (map type con.fields) (zip xs ys)))
    -- Values built with different constructors are different
    let arity = \ cn => maybe 0 (length . fields) (find ((== cn) . conName) cons)
    let different = flip map pairs $ \ (c1, c2) =>
          PatClause fc
            (apply fc (IVar fc fn)
               [ apply fc (IVar fc c1) (replicate (arity c1) (Implicit fc True))
               , apply fc (IVar fc c2) (replicate (arity c2) (Implicit fc True)) ])
            (IApp fc (IVar fc `{Prelude.Types.No}) $
               ILam fc MW ExplicitArg (Just h) (Implicit fc False) $
                 ICase fc [] (IVar fc h) (Implicit fc False)
                   [ ImpossibleClause fc (IVar fc `{Builtin.Refl}) ])
    let empty = if null cons then
          [ ImpossibleClause fc (apply fc (IVar fc fn) [IBindVar fc (un "x"), Implicit fc True]) ]
          else []
    let cls = same ++ different ++ empty

    let used = nubNat (concatMap usedTypeArgs cons)
    let constraint = constraintOn `{Decidable.Equality.Core.DecEq} used
    let x1 = un "x1"
    let x2 = un "x2"
    let ty = MkTy fc (NoFC fn) $ withParams fc constraint params
           $ IPi fc MW ExplicitArg (Just x1) t
           $ IPi fc MW ExplicitArg (Just x2) t
           $ IApp fc (IVar fc `{Prelude.Types.Dec})
               (apply fc (IVar fc `{Builtin.Equal}) [IVar fc x1, IVar fc x2])
    logMsg "derive.deceq.clauses" 1 $
      joinLines ("" :: ("  " ++ show (mapITy cleanup ty))
                      :: map (("  " ++) . showClause InDecl . mapClause cleanup) cls)

    check $ ILocal fc
      [ IClaim (MkFCVal fc (MkIClaimData MW vis [Totality treq] ty))
      , IDef fc fn cls
      ] `(fromDecEq ~(IVar fc fn))
