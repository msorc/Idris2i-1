module TTImp.Elab.Check
-- Interface (or, rather, type declaration) for the main checker function,
-- used by the checkers for each construct. Also some utility functions for
-- reading and writing elaboration state

import Core.Env
import Core.Metadata
import Core.Unify
import Core.Value

import Idris.REPL.Opts
import Idris.Syntax

import TTImp.TTImp

import Data.Either
import Data.List
import Libraries.Data.IntMap
import Libraries.Data.NameMap
import Libraries.Data.UserNameMap
import Libraries.Data.WithDefault

import Libraries.Data.List.SizeOf

import Libraries.Data.VarSet

%default covering

public export
data ElabMode = InType | InLHS RigCount | InExpr | InTransform

export
isLHS : ElabMode -> Maybe RigCount
isLHS (InLHS w) = Just w
isLHS _ = Nothing

export
Show ElabMode where
  show InType = "InType"
  show (InLHS c) = "InLHS " ++ show c
  show InExpr = "InExpr"
  show InTransform = "InTransform"

public export
data ElabOpt
  = HolesOkay
  | InCase
  | InPartialEval
  | InTrans

public export
Eq ElabOpt where
  HolesOkay == HolesOkay = True
  InCase == InCase = True
  InPartialEval == InPartialEval = True
  InTrans == InTrans = True
  _ == _ = False

-- Descriptions of implicit name bindings. They're either just the name,
-- or a binding of an @-pattern which has an associated pattern.
public export
data ImplBinding : Scope -> Type where
     NameBinding : {vars : _} ->
                   FC -> RigCount -> PiInfo (Term vars) ->
                   (elabAs : Term vars) -> (expTy : Term vars) ->
                   ImplBinding vars
     AsBinding : {vars : _} ->
                 RigCount -> PiInfo (Term vars) -> (elabAs : Term vars) -> (expTy : Term vars) ->
                 (pat : Term vars) ->
                 ImplBinding vars

export
covering
Show (ImplBinding vars) where
  show (NameBinding _ c p tm ty) = show (tm, ty)
  show (AsBinding c p tm ty pat) = show (tm, ty) ++ "@" ++ show tm

export
bindingMetas : ImplBinding vars -> NameMap Bool
bindingMetas (NameBinding _ c p tm ty) = getMetas ty
bindingMetas (AsBinding c p tm ty pat)
    = insertAll (toList (getMetas ty)) (getMetas pat)
  where
    insertAll : List (Name, Bool) -> NameMap Bool -> NameMap Bool
    insertAll [] ns = ns
    insertAll ((k, v) :: ks) ns = insert k v (insertAll ks ns)

-- Get the type of an implicit name binding
export
bindingType : ImplBinding vars -> Term vars
bindingType (NameBinding _ _ _ _ ty) = ty
bindingType (AsBinding _ _ _ ty _) = ty

-- Get the term (that is, the expanded thing it elaborates to, of the name
-- applied to the context) from an implicit binding
export
bindingTerm : ImplBinding vars -> Term vars
bindingTerm (NameBinding _ _ _ tm _) = tm
bindingTerm (AsBinding _ _ tm _ _) = tm

export
bindingRig : ImplBinding vars -> RigCount
bindingRig (NameBinding _ c _ _ _) = c
bindingRig (AsBinding c _ _ _ _) = c

export
bindingPiInfo : ImplBinding vars -> PiInfo (Term vars)
bindingPiInfo (NameBinding _ _ p _ _) = p
bindingPiInfo (AsBinding _ p _ _ _) = p

-- Current elaboration state (preserved/updated throughout elaboration)
public export
record EState (vars : Scope) where
  constructor MkEState
  {outer : Scope}
  -- The function/constructor name we're currently working on (resolved id)
  defining : Int
  -- The outer environment in which we're running the elaborator. Things here should
  -- be considered parametric as far as case expression elaboration goes, and are
  -- the only things that unbound implicits can depend on
  outerEnv : Env Term outer
  subEnv : Thin outer vars
  boundNames : List (Name, ImplBinding vars)
                  -- implicit pattern/type variable bindings and the
                  -- term/type they elaborated to
  toBind : List (Name, ImplBinding vars)
                  -- implicit pattern/type variables which haven't been
                  -- bound yet. Record how they're bound (auto-implicit bound
                  -- pattern vars need to be dealt with in with-application on
                  -- the RHS)
  bindIfUnsolved : List (Name, FC, RigCount,
                          (vars' ** (Env Term vars', PiInfo (Term vars'),
                                     Term vars', Term vars', Thin outer vars')))
                  -- names to add as unbound implicits if they are still holes
                  -- when unbound implicits are added
  lhsPatVars : List Name
                  -- names which we've bound in elab mode InLHS (i.e. not
                  -- in a dot pattern). We keep track of this because every
                  -- occurrence other than the first needs to be dotted
  allPatVars : List Name
                  -- Holes standing for pattern variables, which we'll delete
                  -- once we're done elaborating
  polyMetavars : List (FC, Env Term vars, Term vars, Term vars)
                  -- Metavars which need to be a polymorphic type at the end
                  -- of elaboration. If they aren't, it means we're trying to
                  -- pattern match on a type that we don't have available.
  delayDepth : Nat -- if it gets too deep, it gets slow, so fail quicker
  linearUsed : VarSet vars
  saveHoles : NameMap () -- things we'll need to save to TTC, even if solved

  unambiguousNames : UserNameMap (Name, Int, GlobalDef)
                  -- Mapping from userNameRoot to fully resolved names.
                  -- For names in this mapping, we don't run disambiguation.
                  -- Used in with-expressions.

export
data EST : Type where

export
initEStateSub : {outer : _} ->
                Int -> Env Term outer -> Thin outer vars -> EState vars
initEStateSub n env sub = MkEState
    { defining = n
    , outerEnv = env
    , subEnv = sub
    , boundNames = []
    , toBind = []
    , bindIfUnsolved = []
    , lhsPatVars = []
    , allPatVars = []
    , polyMetavars = []
    , delayDepth = Z
    , linearUsed = VarSet.empty
    , saveHoles = empty
    , unambiguousNames = empty
    }

export
initEState : {vars : _} ->
             Int -> Env Term vars -> EState vars
initEState n env = initEStateSub n env Refl

export
saveHole : {auto e : Ref EST (EState vars)} ->
           Name -> Core ()
saveHole n = update EST { saveHoles $= insert n () }

weakenedEState : {n, vars : _} ->
                 {auto e : Ref EST (EState vars)} ->
                 Core (Ref EST (EState (n :: vars)))
weakenedEState {e}
    = do est <- get EST
         eref <- newRef EST $
                   { subEnv $= Drop
                   , boundNames $= map wknTms
                   , toBind $= map wknTms
                   , linearUsed $= weaken {tm = VarSet}
                   , polyMetavars := [] -- no binders on LHS
                   } est
         pure eref
  where
    wknTms : (Name, ImplBinding vs) ->
             (Name, ImplBinding (n :: vs))
    wknTms (f, NameBinding fc c p x y)
        = (f, NameBinding fc c (map weaken p) (weaken x) (weaken y))
    wknTms (f, AsBinding c p x y z)
        = (f, AsBinding c (map weaken p) (weaken x) (weaken y) (weaken z))

strengthenedEState : {n, vars : _} ->
                     Ref Ctxt Defs ->
                     Ref EST (EState (n :: vars)) ->
                     FC -> Env Term (n :: vars) ->
                     Core (EState vars)
strengthenedEState {n} {vars} c e fc env
    = do est <- get EST
         defs <- get Ctxt
         svs <- dropSub (subEnv est)
         bns <- traverse (strTms defs) (boundNames est)
         todo <- traverse (strTms defs) (toBind est)
         pure $ { subEnv := svs
                , boundNames := bns
                , toBind := todo
                , linearUsed $= VarSet.dropFirst
                , polyMetavars := [] -- no binders on LHS
                } est

  where
    dropSub : Thin xs (y :: ys) -> Core (Thin xs ys)
    dropSub (Drop sub) = pure sub
    dropSub _ = throw (InternalError "Badly formed weakened environment")

    -- Remove any instance of the top level local variable from an
    -- application. Fail if it turns out to be necessary.
    -- NOTE: While this isn't strictly correct given the type of the hole
    -- which stands for the unbound implicits, it's harmless because we
    -- never actualy *use* that hole - this process is only to ensure that the
    -- unbound implicit doesn't depend on any variables it doesn't have
    -- in scope.
    removeArgVars : List (Term (n :: vs)) -> Maybe (List (Term vs))
    removeArgVars [] = pure []
    removeArgVars (Local fc r (S k) p :: args)
        = do args' <- removeArgVars args
             pure (Local fc r _ (dropLater p) :: args')
    removeArgVars (Local fc r Z p :: args)
        = removeArgVars args
    removeArgVars (a :: args)
        = do a' <- shrink a (Drop Refl)
             args' <- removeArgVars args
             pure (a' :: args')

    removeArg : Term (n :: vs) -> Maybe (Term vs)
    removeArg tm
        = case getFnArgs tm of
               (f, args) =>
                   do args' <- removeArgVars args
                      f' <- shrink f (Drop Refl)
                      pure (apply (getLoc f) f' args')

    strTms : Defs -> (Name, ImplBinding (n :: vars)) ->
             Core (Name, ImplBinding vars)
    strTms defs (f, NameBinding fc c p x y)
        = do xnf <- normaliseHoles defs env x
             ynf <- normaliseHoles defs env y
             case (shrinkPi p (Drop Refl),
                   removeArg xnf,
                   shrink ynf (Drop Refl)) of
               (Just p', Just x', Just y') =>
                    pure (f, NameBinding fc c p' x' y')
               _ => throw (BadUnboundImplicit fc env f y)
    strTms defs (f, AsBinding c p x y z)
        = do xnf <- normaliseHoles defs env x
             ynf <- normaliseHoles defs env y
             znf <- normaliseHoles defs env z
             case (shrinkPi p (Drop Refl),
                   shrink xnf (Drop Refl),
                   shrink ynf (Drop Refl),
                   shrink znf (Drop Refl)) of
               (Just p', Just x', Just y', Just z') =>
                    pure (f, AsBinding c p' x' y' z')
               _ => throw (BadUnboundImplicit fc env f y)

export
inScope : {n, vars : _} ->
          {auto c : Ref Ctxt Defs} ->
          {auto e : Ref EST (EState vars)} ->
          FC -> Env Term (n :: vars) ->
          (Ref EST (EState (n :: vars)) -> Core a) ->
          Core a
inScope {c} {e} fc env elab
    = do e' <- weakenedEState
         res <- elab e'
         st' <- strengthenedEState c e' fc env
         put {ref=e} EST st'
         pure res

export
mustBePoly : {auto e : Ref EST (EState vars)} ->
             FC -> Env Term vars ->
             Term vars -> Term vars -> Core ()
mustBePoly fc env tm ty = update EST { polyMetavars $= ((fc, env, tm, ty) :: ) }

-- Return whether we already know the return type of the given function
-- type. If we know this, we can possibly infer some argument types before
-- elaborating them, which might help us disambiguate things more easily.
export
concrete : Defs -> Env Term vars -> NF vars -> Core Bool
concrete defs env (NBind fc _ (Pi {}) sc)
    = do sc' <- sc defs (toClosure defaultOpts env (Erased fc Placeholder))
         concrete defs env sc'
concrete defs env (NDCon {}) = pure True
concrete defs env (NTCon {}) = pure True
concrete defs env (NPrimVal {}) = pure True
concrete defs env (NType {}) = pure True
concrete defs env _ = pure False

export
updateEnv : {new : _} ->
            Env Term new -> Thin new vars ->
            List (Name, FC, RigCount,
                   (vars' ** (Env Term vars', PiInfo (Term vars'),
                              Term vars', Term vars', Thin new vars'))) ->
            EState vars -> EState vars
updateEnv env sub bif st
    = { outerEnv := env
      , subEnv := sub
      , bindIfUnsolved := bif
      } st

export
addBindIfUnsolved : {vars : _} ->
                    Name -> FC -> RigCount -> PiInfo (Term vars) ->
                    Env Term vars -> Term vars -> Term vars ->
                    EState vars -> EState vars
addBindIfUnsolved hn fc r p env tm ty st
    = { bindIfUnsolved $=
         ((hn, fc, r, (_ ** (env, p, tm, ty, subEnv st))) ::)} st

clearBindIfUnsolved : EState vars -> EState vars
clearBindIfUnsolved = { bindIfUnsolved := [] }

-- Clear the 'toBind' list, except for the names given
export
clearToBind : {auto e : Ref EST (EState vars)} ->
              (excepts : List Name) -> Core ()
clearToBind excepts =
  update EST $ { toBind $= filter (\x => fst x `elem` excepts) } . clearBindIfUnsolved

export
noteLHSPatVar : {auto e : Ref EST (EState vars)} ->
                ElabMode -> Name -> Core ()
noteLHSPatVar (InLHS _) n = update EST { lhsPatVars $= (n ::) }
noteLHSPatVar _         _ = pure ()

export
notePatVar : {auto e : Ref EST (EState vars)} ->
             Name -> Core ()
notePatVar n = update EST { allPatVars $= (n ::) }

export
metaVar : {vars : _} ->
          {auto c : Ref Ctxt Defs} ->
          {auto u : Ref UST UState} ->
          FC -> RigCount ->
          Env Term vars -> Name -> Term vars -> Core (Term vars)
metaVar fc rig env n ty
    = do (_, tm) <- newMeta fc rig env n ty (Hole (length env) (holeInit False)) True
         pure tm

export
implBindVar : {vars : _} ->
              {auto c : Ref Ctxt Defs} ->
              {auto u : Ref UST UState} ->
              FC -> RigCount ->
              Env Term vars -> Name -> Term vars -> Core (Term vars)
implBindVar fc rig env n ty
    = do (_, tm) <- newMeta fc rig env n ty (Hole (length env) (holeInit True)) True
         pure tm

export
metaVarI : {vars : _} ->
           {auto c : Ref Ctxt Defs} ->
           {auto u : Ref UST UState} ->
           FC -> RigCount ->
           Env Term vars -> Name -> Term vars -> Core (Int, Term vars)
metaVarI fc rig env n ty
    = do defs <- get Ctxt
         tynf <- nf defs env ty
         let hinf = case tynf of
                         NApp _ (NMeta {}) _ =>
                              { precisetype := True } (holeInit False)
                         _ => holeInit False
         newMeta fc rig env n ty (Hole (length env) hinf) True

export
argVar : {vars : _} ->
         {auto c : Ref Ctxt Defs} ->
         {auto u : Ref UST UState} ->
         FC -> RigCount ->
         Env Term vars -> Name -> Term vars -> Core (Int, Term vars)
argVar fc rig env n ty
    = newMetaLets fc rig env n ty (Hole (length env) (holeInit False)) False True

export
uniVar : {auto c : Ref Ctxt Defs} ->
         {auto u : Ref UST UState} ->
         FC -> Core Name
uniVar fc
    = do n <- genName "u"
         idx <- addDef n (newDef fc n erased Scope.empty (Erased fc Placeholder) (specified Public) None)
         pure (Resolved idx)

export
searchVar : {vars : _} ->
            {auto c : Ref Ctxt Defs} ->
            {auto u : Ref UST UState} ->
            FC -> RigCount -> Nat -> Name ->
            Env Term vars -> NestedNames vars -> Name -> Term vars -> Core (Term vars)
searchVar fc rig depth def env nest n ty
    = do defs <- get Ctxt
         (vars' ** (bind, env')) <- envHints (keys (localHints defs)) env
         -- Initial the search with an environment which binds the applied
         -- local hints
         (_, tm) <- newSearch fc rig depth def env' n
                              (weakenNs (mkSizeOf vars') ty)
         pure (bind tm)
  where
    useVars : {vars : _} ->
              List (Term vars) -> Term vars -> Term vars
    useVars [] sc = sc
    useVars (a :: as) (Bind bfc n (Pi fc c _ ty) sc)
         = Bind bfc n (Let fc c a ty) (useVars (map weaken as) sc)
    useVars as (Bind bfc n (Let fc c v ty) sc)
         = Bind bfc n (Let fc c v ty) (useVars (map weaken as) sc)
    useVars _ sc = sc -- Can't happen?

    find : Name -> List (Name, (Maybe Name, b)) -> Maybe (Maybe Name, b)
    find x [] = Nothing
    find x ((n, t) :: xs)
       = if x == n
            then Just t
            else case t of
                      (Nothing, _) => find x xs
                      (Just n', _) => if x == n'
                                         then Just t
                                         else find x xs

    envHints : List Name -> Env Term vars ->
               Core (vars' ** (Term (vars' ++ vars) -> Term vars, Env Term (vars' ++ vars)))
    envHints [] env = pure (Scope.empty ** (id, env))
    envHints (n :: ns) env
        = do (vs ** (f, env')) <- envHints ns env
             let Just (nestn, argns, tmf) = find !(toFullNames n) (names nest)
                 | Nothing => pure (vs ** (f, env'))
             let n' = maybe n id nestn
             defs <- get Ctxt
             Just ndef <- lookupCtxtExact n' (gamma defs)
                 | Nothing => pure (vs ** (f, env'))
             let nt = getDefNameType ndef
             let app = tmf fc nt
             let tyenv = useVars (getArgs app) (embed (type ndef))
             let binder = Let fc top (weakenNs (mkSizeOf vs) app)
                                     (weakenNs (mkSizeOf vs) tyenv)
             varn <- toFullNames n'
             pure ((varn :: vs) **
                    (\t => f (Bind fc varn binder t),
                       binder :: env'))

-- Elaboration info (passed to recursive calls)
public export
record ElabInfo where
  constructor MkElabInfo
  elabMode : ElabMode
  implicitMode : BindMode
  topLevel : Bool
  bindingVars : Bool
  preciseInf : Bool -- are types inferred precisely (True) or do we generalise
                    -- pi bindings to RigW (False, default)
  ambigTries : List Name

export
initElabInfo : ElabMode -> ElabInfo
initElabInfo m = MkElabInfo m NONE False True False []

export
tryError : {vars : _} ->
           {auto c : Ref Ctxt Defs} ->
           {auto m : Ref MD Metadata} ->
           {auto u : Ref UST UState} ->
           {auto e : Ref EST (EState vars)} ->
           Core a -> Core (Either Error a)
tryError elab
    = do ust <- get UST
         est <- get EST
         md <- get MD
         defs <- branch
         catch (do res <- elab
                   commit
                   pure (Right res))
               (\err => do put UST ust
                           put EST est
                           put MD md
                           defs' <- get Ctxt
                           put Ctxt ({ timings := timings defs' } defs)
                           pure (Left err))

export
try : {vars : _} ->
      {auto c : Ref Ctxt Defs} ->
      {auto m : Ref MD Metadata} ->
      {auto u : Ref UST UState} ->
      {auto e : Ref EST (EState vars)} ->
      Core a -> Core a -> Core a
try elab1 elab2
    = do Right ok <- tryError elab1
               | Left err => elab2
         pure ok

export
handle : {vars : _} ->
         {auto c : Ref Ctxt Defs} ->
         {auto m : Ref MD Metadata} ->
         {auto u : Ref UST UState} ->
         {auto e : Ref EST (EState vars)} ->
         Core a -> (Error -> Core a) -> Core a
handle elab1 elab2
    = do Right ok <- tryError elab1
               | Left err => elab2 err
         pure ok

successful : {vars : _} ->
             {auto c : Ref Ctxt Defs} ->
             {auto m : Ref MD Metadata} ->
             {auto u : Ref UST UState} ->
             {auto e : Ref EST (EState vars)} ->
             Bool -> -- constraints allowed
             List (Maybe Name, Core a) ->
             Core (List (Either (Int, Maybe Name, Error)
                                (Nat, a, Defs, UState, EState vars, Metadata)))
successful allowCons [] = pure []
successful allowCons ((tm, elab) :: elabs)
    = do ust <- get UST
         let ncons = if allowCons
                        then 0
                        else length (toList (guesses ust))
         est <- get EST
         md <- get MD
         defs <- branch
         catch (do -- Run the elaborator
                   logC "elab" 5 $
                            do tm' <- maybe (pure (UN $ Basic "__"))
                                             toFullNames tm
                               pure ("Running " ++ show tm')
                   res <- elab
                   -- Record post-elaborator state
                   ust' <- get UST
                   let ncons' = if allowCons
                                   then 0
                                   else length (toList (guesses ust'))

                   est' <- get EST
                   md' <- get MD
                   defs' <- get Ctxt

                   -- Reset to previous state and try the rest
                   put UST ust
                   put EST est
                   put MD md
                   put Ctxt defs
                   logC "elab" 5 $
                            do tm' <- maybe (pure (UN $ Basic "__"))
                                            toFullNames tm
                               pure ("Success " ++ show tm' ++
                                     " (" ++ show ncons' ++ " - "
                                          ++ show ncons ++ ")")
                   elabs' <- successful allowCons elabs
                   -- Record success, and the state we ended at
                   pure (Right (minus ncons' ncons,
                                res, defs', ust', est', md') :: elabs'))
               (\err => do -- How far the attempt got before failing: the
                           -- number of names it generated (for implicit
                           -- arguments, holes, ...), read before the state
                           -- is restored. Used to rank the failures.
                           progress <- (\u => nextName u - nextName ust) <$> get UST
                           put UST ust
                           put EST est
                           put MD md
                           put Ctxt defs
                           when (abandon err) $ throw err
                           elabs' <- successful allowCons elabs
                           pure (Left (progress, tm, err) :: elabs'))
  where
    -- Some errors, it's not worth trying all the possibilities because
    -- something serious has gone wrong, so just give up immediately.
    abandon : Error -> Bool
    abandon (UndefinedName {}) = True
    abandon (InType _ _ err) = abandon err
    abandon (InCon _ err) = abandon err
    abandon (InLHS _ _ err) = abandon err
    abandon (InRHS _ _ err) = abandon err
    abandon (AllFailed _ errs) = any (abandon . snd) errs
    abandon (MaybeMisspelling err _) = abandon err
    abandon _ = False

-- The counters of --timing-summary for an ambiguous term: the sites, the
-- alternatives elaborated, those that succeeded, and the sites where more
-- than one succeeded
ambigCounts : Nat -> Nat -> List (String, Int)
ambigCounts alts oks
    = [("ambig.sites", 1), ("ambig.alts", cast alts), ("ambig.alts.ok", cast oks),
       ("ambig.sites.several_ok", if oks > 1 then 1 else 0)]

||| How promising a failed candidate looks, judging by its error: lower is
||| closer to working. A failed search or constraint means the candidate
||| itself fit; a mismatch between two types with the same head means it was
||| the right kind of thing; a mismatch of heads means it was not; a wrong
||| number of arguments is the furthest from what was meant.
failureClass : Error -> Nat
failureClass (WhenUnifying _ _ _ _ _ _ _ err) = failureClass err
failureClass (Fatal err) = failureClass err
failureClass (CantSolveGoal {}) = 0
failureClass (CantSolveEq {}) = 0
failureClass (DeterminingArg {}) = 0
failureClass (CantConvert _ _ _ l r)
    = case (isPi l, isPi r) of
           (True, False) => 3
           (False, True) => 3
           _ => if sameHead (getFn l) (getFn r) then 1 else 2
  where
    isPi : Term vs -> Bool
    isPi (Bind _ _ (Pi {}) _) = True
    isPi _ = False

    -- A metavariable could become anything, so it counts as the same head
    sameHead : Term vs -> Term vs' -> Bool
    sameHead (Meta {}) _ = True
    sameHead _ (Meta {}) = True
    sameHead (Ref _ _ x) (Ref _ _ y) = x == y
    sameHead (TType {}) (TType {}) = True
    sameHead (PrimVal _ x) (PrimVal _ y) = x == y
    sameHead (Bind _ _ (Pi {}) _) (Bind _ _ (Pi {}) _) = True
    sameHead _ _ = False
failureClass (InvalidArgs {}) = 3
failureClass (NotFunctionType {}) = 3
failureClass _ = 2

||| Order the failures of the candidates of an ambiguous name so that the most
||| promising comes first: the one whose attempt got furthest (whose error is
||| furthest into the expression, since arguments are checked from left to
||| right, and then which generated more names), then by the kind of error
||| (see `failureClass`), then those defined in the current namespace, then
||| in the order the candidates were tried.
rankFailures : {auto c : Ref Ctxt Defs} ->
               List (Int, Maybe Name, Error) -> Core (List (Maybe Name, Error))
rankFailures fs
    = do ns <- getNS
         keyed <- traverse (key ns) (zip [0 .. length fs] fs)
         pure $ map snd $ sortBy (compare `on` fst) keyed
  where
    elsewhere : Namespace -> Maybe Name -> Core Nat
    elsewhere ns Nothing = pure 1
    elsewhere ns (Just n)
        = do n' <- getFullName n
             pure $ case n' of
                         NS ns' _ => if ns' == ns then 0 else 1
                         _ => 0

    innermost : Error -> Error
    innermost (WhenUnifying _ _ _ _ _ _ _ err) = innermost err
    innermost (Fatal err) = innermost err
    innermost err = err

    -- where the error is, the later the further
    position : Error -> (Int, Int)
    position err
        = fromMaybe (0, 0) $ do fc <- getErrorLoc (innermost err)
                                (_, (l, c), _) <- isNonEmptyFC fc
                                pure (negate l, negate c)

    key : Namespace -> (Nat, Int, Maybe Name, Error) ->
          Core (((Int, Int), Int, Nat, Nat, Nat), (Maybe Name, Error))
    key ns (i, progress, mn, err)
        = pure ((position err, negate progress, failureClass err, !(elsewhere ns mn), i), (mn, err))

export
exactlyOne' : {vars : _} ->
              {auto c : Ref Ctxt Defs} ->
              {auto m : Ref MD Metadata} ->
              {auto u : Ref UST UState} ->
              {auto e : Ref EST (EState vars)} ->
              Bool -> FC -> Env Term vars ->
              List (Maybe Name, Core (Term vars, Glued vars)) ->
              Core (Term vars, Glued vars)
exactlyOne' allowCons fc env [(tm, elab)] = elab
exactlyOne' {vars} allowCons fc env all
    = profile "ambig" $
      do elabs <- successful allowCons all
         profileCounts (ambigCounts (length all) (length (rights elabs)))
         case getRight elabs of
              Right (res, defs, ust, est, md) =>
                    do put UST ust
                       put EST est
                       put MD  md
                       put Ctxt defs
                       commit
                       pure res
              Left rs => throw (altError !(rankFailures (lefts elabs)) rs)
  where
    getRight : List (Either err (Nat, res)) -> Either (List res) res
    getRight es
        = case rights es of
               [(_, res)] => Right res
               rs => case filter (\x => fst x == Z) rs of
                          [(_, res)] => Right res
                          _ => Left (map snd rs)

    getRes : ((Term vars, Glued vars), Defs, st) -> (Context, Term vars)
    getRes ((tm, _), defs, thisst) = (gamma defs, tm)

    getDepthError : Error -> Maybe Error
    getDepthError e@(AmbiguityTooDeep {}) = Just e
    getDepthError _ = Nothing

    depthError : List (Maybe Name, Error) -> Maybe Error
    depthError [] = Nothing
    depthError ((_, e) :: es)
        = maybe (depthError es) Just (getDepthError e)

    -- If they've all failed, collect all the errors
    -- If more than one succeeded, report the ambiguity
    altError : List (Maybe Name, Error) ->
               List ((Term vars, Glued vars), Defs, st) ->
               Error
    altError ls []
        = case depthError ls of
               Nothing => AllFailed fc ls
               Just err => err
    altError ls rs = AmbiguousElab fc env (map getRes rs)

export
exactlyOne : {vars : _} ->
             {auto c : Ref Ctxt Defs} ->
             {auto m : Ref MD Metadata} ->
             {auto u : Ref UST UState} ->
             {auto e : Ref EST (EState vars)} ->
             FC -> Env Term vars ->
             List (Maybe Name, Core (Term vars, Glued vars)) ->
             Core (Term vars, Glued vars)
exactlyOne = exactlyOne' True

export
anyOne : {vars : _} ->
         {auto c : Ref Ctxt Defs} ->
         {auto m : Ref MD Metadata} ->
         {auto u : Ref UST UState} ->
         {auto e : Ref EST (EState vars)} ->
         FC -> List (Maybe Name, Core (Term vars, Glued vars)) ->
         Core (Term vars, Glued vars)
anyOne fc es = profile "ambig" $ profileCount "ambig.first.sites" 1 *> anyOneErrs es [<] where
  anyOneErrs : List (Maybe Name, Core a) -> SnocList (Maybe Name, Error) -> Core a
  anyOneErrs [] [<]        = throw $ GenericMsg fc "No elaborators provided"
  anyOneErrs [] [<(tm, e)] = throw e
  anyOneErrs [] errs       = throw $ AllFailed fc $ errs <>> []
  anyOneErrs ((tm, elab) :: es) errs = case !(profileCount "ambig.first.alts" 1 *> tryError elab) of
    Right res => pure res
    Left err  => anyOneErrs es $ errs :< (tm, err)

-- Implemented in TTImp.Elab.Term; delaring just the type allows us to split
-- the elaborator over multiple files more easily
export
check : {vars : _} ->
        {auto c : Ref Ctxt Defs} ->
        {auto m : Ref MD Metadata} ->
        {auto u : Ref UST UState} ->
        {auto e : Ref EST (EState vars)} ->
        {auto s : Ref Syn SyntaxInfo} ->
        {auto o : Ref ROpts REPLOpts} ->
        RigCount -> ElabInfo ->
        NestedNames vars -> Env Term vars -> RawImp ->
        Maybe (Glued vars) ->
        Core (Term vars, Glued vars)

-- As above, but doesn't add any implicit lambdas, forces, delays, etc
export
checkImp : {vars : _} ->
           {auto c : Ref Ctxt Defs} ->
           {auto m : Ref MD Metadata} ->
           {auto u : Ref UST UState} ->
           {auto e : Ref EST (EState vars)} ->
           {auto s : Ref Syn SyntaxInfo} ->
           {auto o : Ref ROpts REPLOpts} ->
           RigCount -> ElabInfo ->
           NestedNames vars -> Env Term vars -> RawImp -> Maybe (Glued vars) ->
           Core (Term vars, Glued vars)

-- Implemented in TTImp.ProcessDecls
export
processDecl : {vars : _} ->
              {auto c : Ref Ctxt Defs} ->
              {auto m : Ref MD Metadata} ->
              {auto u : Ref UST UState} ->
              {auto s : Ref Syn SyntaxInfo} ->
              {auto o : Ref ROpts REPLOpts} ->
              List ElabOpt -> NestedNames vars ->
              Env Term vars -> ImpDecl -> Core ()

-- Check whether two terms are convertible. May solve metavariables (in Ctxt)
-- in doing so.
-- Returns a list of constraints which need to be solved for the conversion
-- to work; if this is empty, the terms are convertible.
convertWithLazy
        : {vars : _} ->
          {auto c : Ref Ctxt Defs} ->
          {auto u : Ref UST UState} ->
          (withLazy : Bool) -> UnifyOrder ->
          FC -> ElabInfo -> Env Term vars -> Glued vars -> Glued vars ->
          Core UnifyResult
convertWithLazy withLazy order fc elabinfo env x y
    = let umode : UnifyInfo
                = { termOrder := order } $ case elabMode elabinfo of
                       InLHS _ => inLHS
                       _ => inTerm in
          catch
            (do let lazy = !isLazyActive && withLazy
                logGlueNF "elab.unify" 5 ("Unifying " ++ show withLazy ++ " "
                             ++ show (elabMode elabinfo)) env x
                logGlueNF "elab.unify" 5 "....with" env y
                vs <- if isFromTerm x && isFromTerm y
                         then do xtm <- getTerm x
                                 ytm <- getTerm y
                                 if lazy
                                    then unifyWithLazy umode fc env xtm ytm
                                    else unify umode fc env xtm ytm
                         else do xnf <- getNF x
                                 ynf <- getNF y
                                 if lazy
                                    then unifyWithLazy umode fc env xnf ynf
                                    else unify umode fc env xnf ynf
                when (holesSolved vs) $
                    solveConstraints umode Normal
                pure vs)
            (\err =>
               do xtm <- getTerm x
                  ytm <- getTerm y
                  -- See if we can improve the error message by
                  -- resolving any more constraints
                  catch (solveConstraints umode Normal)
                        (\err => pure ())
                  -- We need to normalise the known holes before
                  -- throwing because they may no longer be known
                  -- by the time we look at the error
                  defs <- get Ctxt
                  throw (WhenUnifying fc order (gamma defs) env xtm ytm [] err))

||| Check that the type an expression has (the first) converts with the type
||| its context expects (the second).
export
convert : {vars : _} ->
          {auto c : Ref Ctxt Defs} ->
          {auto u : Ref UST UState} ->
          FC -> ElabInfo -> Env Term vars -> Glued vars -> Glued vars ->
          Core UnifyResult
convert = convertWithLazy False GotExpected

||| Check that two terms convert, when neither is the expected one.
export
convertUnordered : {vars : _} ->
                   {auto c : Ref Ctxt Defs} ->
                   {auto u : Ref UST UState} ->
                   FC -> ElabInfo -> Env Term vars -> Glued vars -> Glued vars ->
                   Core UnifyResult
convertUnordered = convertWithLazy False Unordered

-- Check whether the type we got for the given type matches the expected
-- type.
-- Returns the term and its type.
-- This may generate new constraints; if so, the term returned is a constant
-- guarded by the constraints which need to be solved.
export
checkExp : {vars : _} ->
           {auto c : Ref Ctxt Defs} ->
           {auto u : Ref UST UState} ->
           RigCount -> ElabInfo -> Env Term vars -> FC ->
           (term : Term vars) ->
           (got : Glued vars) -> (expected : Maybe (Glued vars)) ->
           Core (Term vars, Glued vars)
checkExp rig elabinfo env fc tm got (Just exp)
    = do vs <- convertWithLazy True GotExpected fc elabinfo env got exp
         case (constraints vs) of
              [] => case addLazy vs of
                         NoLazy => do logTerm "elab" 5 "Solved" tm
                                      pure (tm, got)
                         AddForce r => do logTerm "elab" 5 "Force" tm
                                          logGlue "elab" 5 "Got" got
                                          logGlue "elab" 5 "Exp" exp
                                          pure (TForce fc r tm, exp)
                         AddDelay r => do ty <- getTerm got
                                          logTerm "elab" 5 "Delay" tm
                                          pure (TDelay fc r ty tm, exp)
              cs => do logTerm "elab" 5 "Not solved" tm
                       defs <- get Ctxt
                       empty <- clearDefs defs
                       cty <- getTerm exp
                       ctm <- newConstant fc rig env tm cty cs
                       dumpConstraints "elab" 5 False
                       case addLazy vs of
                            NoLazy => pure (ctm, got)
                            AddForce r => pure (TForce fc r tm, exp)
                            AddDelay r => do ty <- getTerm got
                                             pure (TDelay fc r ty tm, exp)
checkExp rig elabinfo env fc tm got Nothing = pure (tm, got)
