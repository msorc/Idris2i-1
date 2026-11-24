module Deriving.Common

import Data.SnocList
import Language.Reflection

%default total

------------------------------------------------------------------------------
-- Being free of a variable

||| IsFreeOf is parametrised by
||| @ x  the name of the type variable that the functorial action will change
||| @ ty the type that does not contain any mention of x
export
data IsFreeOf : (x : Name) -> (ty : TTImp) -> Type where
  ||| For now we do not bother keeping precise track of the proof that a type
  ||| is free of x
  TrustMeFO : IsFreeOf a x

||| We may need to manufacture proofs and so we provide the `assert` escape hatch.
export %unsafe
assert_IsFreeOf : IsFreeOf x ty
assert_IsFreeOf = TrustMeFO

||| Testing function deciding whether the given term is free of a particular
||| variable.
export
isFreeOf : (x : Name) -> (ty : TTImp) -> Maybe (IsFreeOf x ty)
isFreeOf x ty
  = do isOk <- flip mapMTTImp ty $ \case
         t@(IVar _ v) => t <$ guard (v /= x)
         t => pure t
       pure TrustMeFO

------------------------------------------------------------------------------
-- Being a (data) type

public export
data TypeParameter
  = MkTPLocal Name
  | MkTPPrim Constant
  | MkTPApp (Name, SnocList (Argument TypeParameter))
  | MkTPIType

export
Show TypeParameter where
  showPrec d (MkTPLocal a) = showCon d "MkTPLocal" $ show a
  showPrec d (MkTPPrim c) = showCon d "MkTPPrim" $ show c
  showPrec d (MkTPApp a) = showCon d "MkTPApp" $ assert_total $ show (map (map unArg) a)
  showPrec d MkTPIType = "MkTPIType"

public export
record IsFamily where
  constructor MkIsFamily
  typeConstructor  : Name
  parameterNames   : List (Argument TypeParameter, Nat)
  dataConstructors : List (Name, TTImp)

wording : NameType -> String
wording Bound = "a bound variable"
wording Func = "a function name"
wording (DataCon tag arity) = "a data constructor"
wording (TyCon tag arity) = "a type constructor"

checkAccessToDefinition : Elaboration m => (given, candidate : Name) -> m Bool
checkAccessToDefinition g c = pure $ isParentOf (getNS g) (getNS c) || !(isPublic g)

normaliseName : Elaboration m => FC -> Name -> m (Maybe TTImp)
normaliseName fc n = do
  [(_, typeFun)] <- getType n
    | _ => failAt fc "\{show n} is ambiguous"

  Just typedFun <- catch $ check {expected = Type} typeFun
    | _ => failAt fc "\{show n} is not a Type declaration"

  Just checkedTy <- catch $ check {expected = typedFun} $ IVar fc n
    | _ => failAt fc "\{show n} has a different type than checked: \{show !(quote typedFun)}"

  normalisedTy <- quote checkedTy

  -- nn is meaning "normalised name"
  let tyq@(_, Just nn) = getHeadName normalisedTy
    | (broken, _) => failAt fc "Failed to extract type name from \{show n} (\{show normalisedTy}) at \{show broken}"

  pure $ if dropNS nn == dropNS n
    then Nothing
    else Just normalisedTy
  where
    getHeadName : TTImp -> (TTImp, Maybe Name)
    getHeadName t@(IVar _ n) = (t, pure n)
    getHeadName (IApp _ n _) = getHeadName n
    getHeadName (INamedApp _ n _ _) = getHeadName n
    getHeadName (IAutoApp _ n _) = getHeadName n
    getHeadName (IWithApp _ n _) = getHeadName n
    getHeadName (IPi _ _ _ _ _ retTy) = getHeadName retTy
    getHeadName (ILam _ _ _ _ _ retTy) = getHeadName retTy
    getHeadName t = (t, Nothing)

isTypeCon : Elaboration m => Name -> FC -> Name -> m (Either TTImp (List (Name, TTImp)))
isTypeCon currentFnName fc ty = do
    [(_, MkNameInfo (TyCon _ _))] <- getInfo ty
      | [(fullName, MkNameInfo Func)] => do
        unless !(checkAccessToDefinition fullName currentFnName) $
          failAt fc "Make sure \{show fullName} has public export visibility"

        Just normalised <- normaliseName fc fullName
          | _ => failAt fc "Unable to normalise \{show ty} to type constructor"

        pure $ Left normalised
      | [] => failAt fc "\{show ty} out of scope"
      | [(_, MkNameInfo nt)] => failAt fc "\{show ty} is \{wording nt} rather than a type constructor"
      | _ => failAt fc "\{show ty} is ambiguous"
    cs <- getCons ty
    res <- for cs $ \ n => do
      [(_, ty)] <- getType n
         | _ => failAt fc "\{show n} is ambiguous"
      pure (n, ty)
    pure $ Right res

toTypeParameter : Elaboration m => TTImp -> m TypeParameter
toTypeParameter (IType _) = pure MkTPIType
toTypeParameter (IPrimVal _ c) = pure (MkTPPrim c)
-- Unqualified: that's a local variable
toTypeParameter (IVar _ nm@(UN (Basic _))) = pure (MkTPLocal nm)
toTypeParameter arg with (appView arg)
  toTypeParameter t | Nothing = failAt (getFC t) "Unexpected a type parameter, got: \{show t}"
  toTypeParameter _ | (Just $ MkAppView (fc, h) args _) = do
    typedArgs <- assert_total $ traverse @{Compose} toTypeParameter args
    pure $ MkTPApp (h, typedArgs)

isFamily' : Elaboration m => Name -> TTImp -> m IsFamily
isFamily' currentFnName = go Z [] where
  go : Nat -> List (Argument TypeParameter, Nat) -> TTImp -> m IsFamily
  go idx acc (IVar fc n) = do
    case !(isTypeCon currentFnName fc n) of
      Right tcons => pure $ MkIsFamily n (map (map (minus idx . S)) acc) tcons
      Left normalised => assert_total $ isFamily' currentFnName normalised
  go idx acc (IApp fc t arg) = go (S idx) ((Arg fc !(toTypeParameter arg), idx) :: acc) t
  go idx acc (INamedApp fc t nm arg) = go (S idx) ((NamedArg fc nm !(toTypeParameter arg), idx) :: acc) t
  go idx acc (IAutoApp fc t arg) = go (S idx) ((AutoArg fc !(toTypeParameter arg), idx) :: acc) t
  go idx acc t = failAt (getFC t) "Expected a type constructor, got: \{show t}"

export
isFamily : Elaboration m => TTImp -> m IsFamily
isFamily t = do
  let (Just currentName) = leftMost !getCurrentFn
  | _ => failAt (getFC t) "Deriving requires a function declaration, not a top level"

  isFamily' currentName t
------------------------------------------------------------------------------
-- Being a (data) constructor with a parameter
-- TODO: generalise?

public export
record ConstructorView where
  constructor MkConstructorView
  params      : SnocList (Name, Nat)
  conArgTypes : List (Count, Argument TTImp)

export
constructorView : TTImp -> Maybe ConstructorView
constructorView (IPi fc rig pinfo x a b) = do
  let Just arg = fromPiInfo fc pinfo x a
    | Nothing => constructorView b -- this better be a boring argument...
  let True = rig /= M1
    | False => constructorView b -- this better be another boring argument...
  { conArgTypes $= ((rig, arg) ::) } <$> constructorView b
constructorView f = do
  MkAppView _ ts _ <- appView f
  let range = [<] <>< [0..minus (length ts) 1]
  let ps = flip mapMaybe (zip ts range) $ \ t => the (Maybe (Name, Nat)) $ case t of
             (Arg _ (IVar _ nm), n) => Just (nm, n)
             _ => Nothing
  pure (MkConstructorView ps [])

------------------------------------------------------------------------------
-- Satisfying an interface
--
-- In order to derive Functor for `data Tree a = Node (List (Tree a))`, we need
-- to make sure that `Functor List` already exists. This is done using the following
-- convenience functions.

export
withParams : FC -> (Nat -> Maybe TTImp) -> List (Argument TypeParameter, Nat) -> TTImp -> TTImp
withParams fc params nms t = go nms where

  addConstraint : Maybe TTImp -> Name -> TTImp -> TTImp
  addConstraint Nothing _ = id
  addConstraint (Just cst) nm =
     let ty = IApp fc cst (IVar fc nm) in
     IPi fc MW AutoImplicit Nothing ty

  go : List (Argument TypeParameter, Nat) -> TTImp
  go [] = t
  go ((arg, pos) :: nms) with (unArg arg)
    go ((arg, pos) :: nms) | MkTPLocal nm =
      IPi fc M0 ImplicitArg (Just nm) (Implicit fc True)
      $ addConstraint (params pos) nm
      $ go nms
    go ((arg, pos) :: nms) | MkTPPrim _ = go nms
    go ((arg, pos) :: nms) | MkTPApp _ = go nms
    go ((arg, pos) :: nms) | MkTPIType  = go nms

||| Type of proofs that something has a given type
export
data HasType : (nm : Name) -> (ty : TTImp) -> Type where
  TrustMeHT : HasType nm ty

export
hasType : Elaboration m => (nm : Name) ->
          m (Maybe (ty : TTImp ** HasType nm ty))
hasType nm = catch $ do
  [(_, ty)] <- getType nm
    | _ => fail "Ambiguous name"
  pure (ty ** TrustMeHT)

||| Type of proofs that a type is inhabited
export
data IsProvable : (ty : TTImp) -> Type where
  TrustMeIP : IsProvable ty

export
isProvable : Elaboration m => (ty : TTImp) ->
             m (Maybe (IsProvable ty))
isProvable ty = catch $ do
  ty <- check {expected = Type} ty
  ignore $ check {expected = ty} `(%search)
  pure TrustMeIP

||| Type of proofs that a type satisfies a constraint.
||| Internally it's vacuous. We don't export the constructor so
||| that users cannot manufacture buggy proofs.
export
data HasImplementation : (intf : a -> Type) -> TTImp -> Type where
  TrustMeHI : HasImplementation intf t

||| We may need to manufacture proofs and so we provide the `assert` escape hatch.
export %unsafe
assert_hasImplementation : HasImplementation intf t
assert_hasImplementation = TrustMeHI

||| Given
||| @ intf an interface (e.g. `Functor`, or `Bifunctor`)
||| @ t    a term corresponding to a (possibly partially applied) type constructor
||| check whether Idris2i-1 can find a proof that t satisfies the interface.
export
hasImplementation : Elaboration m => (intf : a -> Type) -> (t : TTImp) ->
                    m (Maybe (HasImplementation intf t))
hasImplementation c t = do
  Just prf <- catch $ isFamily t
    | _ => Nothing <$ logMsg "derive.common.hasImplementation" 100
                         "\{show t} is not a Type"
  Just intf <- catch $ quote c
    | _ => Nothing <$ logMsg "derive.common.hasImplementation" 100
                         "Could not quote constraint"
  Just ty <- catch $ check {expected = Type} $
               withParams emptyFC (const Nothing) prf.parameterNames `(~(intf) ~(t))
    | _ => Nothing <$ logMsg "derive.common.hasImplementation" 100
                         "\{show (`(~(intf) ~(t)))} is not a Type"

  Just _ <- catch $ check {expected = ty} `(%search)
    | _ => Nothing <$ logMsg "derive.common.hasImplementation" 100
                         "Could not find an implementation of \{show (`(~(intf) ~(t)))}"
  pure (Just TrustMeHI)

------------------------------------------------------------------------------
-- Utils

||| Optionally eta-expand if there is no argument available
export
optionallyEta : FC -> Maybe TTImp -> (TTImp -> TTImp) -> TTImp
optionallyEta fc (Just t) f = f t
optionallyEta fc Nothing f =
  let tnm = UN $ Basic "t" in
  ILam fc MW ExplicitArg (Just tnm) (Implicit fc False) $
  f (IVar fc tnm)

||| We often apply multiple arguments, this makes things simpler
export
apply : FC -> TTImp -> List TTImp -> TTImp
apply fc t ts = apply t (map (Arg fc) ts)

||| Use unqualified names (useful for more compact printing)
export
cleanup : TTImp -> TTImp
cleanup = \case
  IVar fc n => IVar fc (dropNS n)
  t => t

||| Create fresh names
export
freshName : List TypeParameter -> String -> String
freshName ns a = assert_total $ go (basicNames $ concatMap typeParameterNames ns) Nothing where
  typeParameterNames : TypeParameter -> List Name
  typeParameterNames (MkTPLocal a) = [a]
  typeParameterNames (MkTPPrim c) = []
  typeParameterNames (MkTPApp (n, tp)) = assert_total
    $ n :: concatMap (typeParameterNames . unArg) tp
  typeParameterNames MkTPIType = []

  basicNames : List Name -> List String
  basicNames names = mapMaybe (toBasic . dropNS) names where
    toBasic : Name -> Maybe String
    toBasic (UN (Basic str)) = Just str
    toBasic _ = Nothing

  covering
  go : List String -> Maybe Nat -> String
  go names counter =
    let name = a ++ maybe "" show counter in
    if name `elem` names
      then go names (Just $ maybe 0 S counter)
      else name

------------------------------------------------------------------------------
-- Being a data constructor whose values can be compared field by field
--
-- Deriving a comparison (`Eq`, `Ord`, `DecEq`) matches two values of one type
-- against the same constructor, then compares their explicit fields pairwise.
-- That needs the type of every field to be the same on both sides, which
-- holds when the indices of the constructor's type are made of constructors
-- and variables only (as in `Vect (S n) a`), and when every implicit argument
-- the fields depend on occurs in them.

||| An explicit field of a data constructor
public export
record ConField where
  constructor MkConField
  ||| The quantity of the field
  rig  : Count
  ||| The type of the field, normalised
  type : TTImp

||| A data constructor whose values can be compared field by field
public export
record ComparableCon where
  constructor MkComparableCon
  ||| The fully qualified name of the constructor
  conName : Name
  ||| Its explicit fields, in order
  fields : List ConField
  ||| The positions of the arguments of the type constructor which are a
  ||| variable of type `Type` in this constructor's type and which a field
  ||| with a non-zero quantity mentions: their values need the interface too
  usedTypeArgs : List Nat

||| Join lines with newlines
public export
joinLines : List String -> String
joinLines [] = ""
joinLines [l] = l
joinLines (l :: ls) = l ++ "\n" ++ joinLines ls

||| Remove the duplicates of a list
public export
nubNat : List Nat -> List Nat
nubNat = go []
  where
    go : List Nat -> List Nat -> List Nat
    go seen [] = reverse seen
    go seen (x :: xs) = go (if x `elem` seen then seen else x :: seen) xs

||| Does a type mention a name? Only the forms which occur in the types of
||| fields are inspected: variables, applications, binders and laziness.
public export
mentions : Name -> TTImp -> Bool
mentions n (IVar _ v) = v == n
mentions n (IApp _ f a) = mentions n f || mentions n a
mentions n (INamedApp _ f _ a) = mentions n f || mentions n a
mentions n (IAutoApp _ f a) = mentions n f || mentions n a
mentions n (IWithApp _ f a) = mentions n f || mentions n a
mentions n (IPi _ _ _ _ a b) = mentions n a || mentions n b
mentions n (ILam _ _ _ _ a b) = mentions n a || mentions n b
mentions n (IDelayed _ _ a) = mentions n a
mentions n (IDelay _ a) = mentions n a
mentions n (IForce _ a) = mentions n a
mentions n _ = False

-- The binders of a Pi type, and its codomain
public export
telescope : TTImp -> (List (Count, PiInfo TTImp, Maybe Name, TTImp), TTImp)
telescope (IPi _ rig pinfo n a b)
  = let (bs, ret) = telescope b in ((rig, pinfo, n, a) :: bs, ret)
telescope t = ([], t)

public export
isConName : Elaboration m => Name -> m Bool
isConName n = pure $ case !(getInfo n) of
  [(_, MkNameInfo (DataCon _ _))] => True
  [(_, MkNameInfo (TyCon _ _))] => True
  _ => False

-- Made of constructors, primitive values and the variables `bs`
public export
isConForm : Elaboration m => (bs : List Name) -> TTImp -> m Bool
isConForm bs (IVar _ n) = if n `elem` bs then pure True else isConName n
isConForm bs (IPrimVal _ _) = pure True
isConForm bs (IType _) = pure True
isConForm bs (Implicit _ _) = pure True
isConForm bs t = case appView t of
  Just (MkAppView (_, hd) args _) =>
    if !(isConName hd)
       -- the arguments are subterms of t
       then allM (\ a => assert_total (isConForm bs (unArg a))) (args <>> [])
       else pure False
  Nothing => pure False
  where
    allM : (a -> m Bool) -> List a -> m Bool
    allM p [] = pure True
    allM p (x :: xs) = if !(p x) then allM p xs else pure False

||| Check that the values of a data constructor can be compared field by
||| field, for deriving the interface `intf` (only used in messages).
||| @ t  the name of the type constructor
||| @ cn the name of the data constructor
||| @ ty the type of the data constructor
public export
comparableCon : Elaboration m => (intf : String) -> (t, cn : Name) -> (ty : TTImp) ->
                m ComparableCon
comparableCon intf t cn ty0 = do
  -- Reduce the type first, so that literals and type synonyms are seen
  -- through. Binders then have unique names: messages use the original ones.
  ty <- try (normaliseTerm False ty0) (pure ty0)
  let (bs, ret) = telescope ty
  let renaming = zip (map binderName bs) (map binderName (fst (telescope ty0)))
  let display = \ n => case lookup (Just n) renaming of
                         Just (Just n') => n'
                         _ => n
  let Just (MkAppView _ targs _) = appView ret
    | _ => failAt (getFC ty) "\{cannot}: confusing return type \{show (mapTTImp cleanup ret)}"
  let indices = map unArg (targs <>> [])
  let bound = mapMaybe (\ (_, _, n, _) => n) bs
  for_ indices $ \ ix =>
    unless !(isConForm bound ix) $
      failAt (getFC ty) $ unlines'
        [ "\{cannot}: the type of the constructor \{show (dropNS cn)} has the index"
        , "\{show (mapTTImp (rename display) ix)}, which is not made of constructors and variables,"
        , "so two values of one type cannot be compared field by field"
        ]
  let fields = mapMaybe (\ (rig, pinfo, _, a) => case pinfo of
                             ExplicitArg => Just (MkConField rig a)
                             _ => Nothing) bs
  let relevant = map type (filter ((/= M0) . rig) fields)
  -- An implicit argument which a field depends on must be determined by
  -- the type, or the two fields may have different types
  for_ bs $ \case
    (_, ExplicitArg, _, _) => pure ()
    (_, _, Nothing, _) => pure ()
    (_, _, Just n, _) =>
      when (any (mentions n) relevant && not (any (mentions n) indices)) $
        failAt (getFC ty) $ unlines'
          [ "\{cannot}: the fields of the constructor \{show (dropNS cn)} depend on its"
          , "implicit argument \{show (dropNS (display n))}, which its type does not determine,"
          , "so two values of one type cannot be compared field by field"
          ]
  let typeVars = mapMaybe (\case (_, _, Just n, IType _) => Just n; _ => Nothing) bs
  let used = mapMaybe (\case
                         (IVar _ v, pos) =>
                           pos <$ guard (elem v typeVars && any (mentions v) relevant)
                         _ => Nothing)
                      (zip indices [0 .. length indices])
  pure (MkComparableCon cn fields used)
  where
    rename : (Name -> Name) -> TTImp -> TTImp
    rename f (IVar fc n) = IVar fc (dropNS (f n))
    rename f t = t

    binderName : (Count, PiInfo TTImp, Maybe Name, TTImp) -> Maybe Name
    binderName (_, _, n, _) = n

    cannot : String
    cannot = "Can't derive \{intf} for \{show (dropNS t)}"

    unlines' : List String -> String
    unlines' = joinLines

||| The pairs of distinct data constructors of a type constructor which can
||| build values of the same type, so that a comparison must have a clause
||| for them. When it cannot tell, it errs on the side of including a pair.
public export
distinctConPairs : Elaboration m => (t : Name) -> (cons : List Name) -> m (List (Name, Name))
distinctConPairs t cons = do
  [(_, tty)] <- getType t
    | _ => failAt EmptyFC "\{show t} is ambiguous"
  tyv <- check {expected = Type} tty
  tcon <- check {expected = tyv} (IVar EmptyFC t)
  (_, pairs) <- getDecEqConPairs tcon
  pure (mapMaybe distinct pairs)
  where
    -- as the compiler's `nameRoot`, which `getDecEqConPairs` uses
    root : Name -> String
    root (NS _ n) = root n
    root (UN (Basic s)) = s
    root (UN (Field s)) = s
    root (MN s _) = s
    root (DN _ n) = root n
    root n = show n

    byRoot : String -> Maybe Name
    byRoot s = case filter ((== s) . root) cons of
                 (n :: _) => Just n
                 [] => Nothing

    distinct : (String, String) -> Maybe (Name, Name)
    distinct (x, y) = if x == y then Nothing else [| (byRoot x, byRoot y) |]

||| Names for the fields of a constructor: `x0`, `x1`, ...
public export
fieldNames : (stem : String) -> (n : Nat) -> List Name
fieldNames stem n = go 0 n
  where
    go : Nat -> Nat -> List Name
    go i Z = []
    go i (S k) = UN (Basic (stem ++ show i)) :: go (S i) k

||| Compare the fields of two values built with one constructor, given the
||| comparison of two fields of a type, and the names bound to the fields.
||| Erased fields are skipped.
public export
compareFields : (cmp : TTImp -> TTImp -> TTImp -> TTImp) ->
                List ConField -> (xs, ys : List Name) -> List TTImp
compareFields cmp (fld :: flds) (x :: xs) (y :: ys)
  = let rest = compareFields cmp flds xs ys in
    if fld.rig == M0 then rest
      else cmp fld.type (IVar EmptyFC x) (IVar EmptyFC y) :: rest
compareFields _ _ _ _ = []

||| The constraint `intf` on the arguments of a type constructor whose
||| positions are listed, for `withParams`
public export
constraintOn : (intf : Name) -> (positions : List Nat) -> Nat -> Maybe TTImp
constraintOn intf positions pos
  = if pos `elem` positions then Just (IVar EmptyFC intf) else Nothing

