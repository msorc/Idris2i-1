module Core.Termination.Positivity

import Core.Context.Log
import Core.Env
import Core.Normalise
import Core.Value

import Core.Termination.References

import Data.String

import Libraries.Data.NameMap
import Libraries.Data.NatSet

%default covering

isAssertTotal : Ref Ctxt Defs => NHead vars -> Core Bool
isAssertTotal (NRef _ fn_in) =
  do fn <- getFullName fn_in
     pure (fn == NS builtinNS (UN $ Basic "assert_total"))
isAssertTotal _ = pure False

nameIn : {auto c : Ref Ctxt Defs} ->
         Defs -> List Name -> ClosedNF -> Core Bool
nameIn defs tyns (NBind fc x b sc)
    = if !(nameIn defs tyns !(evalClosure defs (binderType b)))
         then pure True
         else do let nm = Ref fc Bound (MN ("NAMEIN_" ++ show x) 0)
                 let arg = toClosure defaultOpts Env.empty nm
                 sc' <- sc defs arg
                 nameIn defs tyns sc'
nameIn defs tyns (NApp _ nh args)
    = do False <- isAssertTotal nh
           | True => pure False
         -- the placeholders standing for a parameter or function argument
         -- in paramPositive and fnArgPositive
         let NRef Bound hn = nh
             | _ => anyM (nameIn defs tyns)
                      !(traverse (evalClosure defs . snd) args)
         if hn `elem` tyns then pure True else
          anyM (nameIn defs tyns)
           !(traverse (evalClosure defs . snd) args)
nameIn defs tyns (NTCon _ n _ _ args)
    = if n `elem` tyns
         then pure True
         else do args' <- traverse (evalClosure defs . snd) args
                 anyM (nameIn defs tyns) args'
nameIn defs tyns (NDCon _ n _ _ args)
    = anyM (nameIn defs tyns)
           !(traverse (evalClosure defs . snd) args)
nameIn defs tyns (NDelayed fc lr ty) = nameIn defs tyns ty
nameIn defs tyns (NDelay fc lr ty tm) = nameIn defs tyns !(evalClosure defs tm)
nameIn defs tyns _ = pure False

-- Check an argument type doesn't contain a negative occurrence of any of
-- the given type names
-- `seen` lists the (type constructor, parameter position) pairs whose
-- positivity is being checked further up, and is assumed while checking
-- them (so that `List`, whose constructors mention `List a`, terminates).
posArg  : {auto c : Ref Ctxt Defs} ->
          Defs -> List (Name, Nat) -> List Name -> ClosedNF -> Core Terminating

-- Is parameter `i` of type constructor `tc` used only strictly positively
-- by the constructors of `tc`?
paramPositive : {auto c : Ref Ctxt Defs} ->
                Defs -> List (Name, Nat) -> Name -> Nat -> Core Bool

-- Is argument `j` of the type-level function `fn` used only strictly
-- positively by every clause of `fn`? This lets a stuck application such as
-- `Arr d r`, with `Arr` defined by matching on `d`, count as positive in `r`.
fnArgPositive : {auto c : Ref Ctxt Defs} ->
                Defs -> List (Name, Nat) -> Name -> Nat -> Core Bool

-- The positivity of the parameters of a type constructor, recorded by
-- recordPositiveParams in the module that defines it
recorded : List DefFlag -> Maybe NatSet
recorded [] = Nothing
recorded (PositiveParams ps :: _) = Just ps
recorded (_ :: fs) = recorded fs

numbered : Nat -> List a -> List (Nat, a)
numbered i [] = []
numbered i (x :: xs) = (i, x) :: numbered (S i) xs

-- a tyn can only appear in the parameter positions of tc, and only in
-- parameters that tc itself uses strictly positively; report positivity
-- failure if it appears anywhere else. Without the second condition
-- `MkBad : Neg Bad -> Bad` with `MkNeg : (a -> Void) -> Neg a` is accepted.
posArg defs seen tyns nf@(NTCon loc tc _ _ args) =
  do logNF "totality.positivity" 50 "Found a type constructor" Env.empty nf
     Just def <- lookupDefExact tc (gamma defs)
       | Nothing => notLoaded
     let TCon _ params _ _ _ _ _ = def
       | _ => throw (GenericMsg loc (show tc ++ " not a data type"))
     log "totality.positivity" 50 $
       unwords [show tc, "has", show (size params), "parameters"]
     checkArgs params (numbered 0 (map snd args))
  where
    checkArgs : NatSet -> List (Nat, ClosedClosure) -> Core Terminating
    checkArgs params [] = pure IsTerminating
    checkArgs params ((i, cl) :: rest)
        = do xNF <- evalClosure defs cl
             False <- nameIn defs tyns xNF
               | True =>
                   if not (i `elem` params)
                      then pure (NotTerminating NotStrictlyPositive)
                      else do
                        True <- paramPositive defs seen tc i
                          | False => pure (NotTerminating NotStrictlyPositive)
                        logNF "totality.positivity" 50 "Checking parameter for positivity" Env.empty xNF
                        IsTerminating <- posArg defs seen tyns xNF
                          | err => pure err
                        checkArgs params rest
             checkArgs params rest

    -- A type constructor whose definition is not loaded: nothing is known
    -- about how it uses its arguments, so none of them may mention the
    -- types being checked.  (This happens only when a type in the context
    -- normalises to one from a module that it does not load; a type
    -- constructor that it loads carries the positivity of its parameters,
    -- see `recordPositiveParams`, and that is all paramPositive needs.)
    notLoaded : Core Terminating
    notLoaded
        = do log "totality.positivity" 30 $
               "The definition of " ++ show tc ++ " is not loaded"
             checkArgs NatSet.empty (numbered 0 (map snd args))
-- a tyn can not appear as part of ty
posArg defs seen tyns nf@(NBind fc x (Pi _ _ e ty) sc)
  = do logNF "totality.positivity" 50 "Found a Pi-type" Env.empty nf
       if !(nameIn defs tyns !(evalClosure defs ty))
         then pure (NotTerminating NotStrictlyPositive)
         else do let nm = Ref fc Bound (MN ("POSCHECK_" ++ show x) 1)
                 let arg = toClosure defaultOpts Env.empty nm
                 sc' <- sc defs arg
                 posArg defs seen tyns sc'
-- a type-level lambda, e.g. the second argument of a DPair: the tyns must
-- not appear in the binder's type, and the body is checked like any type.
-- (It used to reach the catchall, so `MkBad : (n ** (Bad -> Void)) -> Bad`
-- was accepted.)
posArg defs seen tyns nf@(NBind fc x (Lam _ _ _ ty) sc)
  = do logNF "totality.positivity" 50 "Found a lambda" Env.empty nf
       if !(nameIn defs tyns !(evalClosure defs ty))
         then pure (NotTerminating NotStrictlyPositive)
         else do let nm = Ref fc Bound (MN ("POSCHECK_" ++ show x) 2)
                 let arg = toClosure defaultOpts Env.empty nm
                 sc' <- sc defs arg
                 posArg defs seen tyns sc'
posArg defs seen tyns nf@(NApp fc nh args)
    = do False <- isAssertTotal nh
           | True => do logNF "totality.positivity" 50 "Trusting an assertion" Env.empty nf
                        pure IsTerminating
         logNF "totality.positivity" 50 "Found an application" Env.empty nf
         args <- traverse (evalClosure defs . snd) args
         -- A stuck application may mention the tyns only in the arguments
         -- that the function (if it is a defined one) uses strictly
         -- positively, and those arguments must themselves be positive.
         let NRef _ fn = nh
           | _ => do log "totality.positivity" 50 "Not headed by a name"
                     noneMention args
         checkFnArgs fn (numbered 0 args)
  where
    noneMention : List ClosedNF -> Core Terminating
    noneMention args
        = pure $ if !(anyM (nameIn defs tyns) args)
                    then NotTerminating NotStrictlyPositive
                    else IsTerminating

    checkFnArgs : Name -> List (Nat, ClosedNF) -> Core Terminating
    checkFnArgs fn [] = pure IsTerminating
    checkFnArgs fn ((j, a) :: rest)
        = do False <- nameIn defs tyns a
               | True => do
                   log "totality.positivity" 50 $ "Argument " ++ show j ++ " mentions " ++ show tyns
                   True <- fnArgPositive defs seen fn j
                     | False => pure (NotTerminating NotStrictlyPositive)
                   IsTerminating <- posArg defs seen tyns a
                     | err => pure err
                   checkFnArgs fn rest
             checkFnArgs fn rest
posArg defs seen tyn (NDelayed fc lr ty) = posArg defs seen tyn ty
posArg defs seen tyn nf
  = do logNF "totality.positivity" 50 "Reached the catchall" Env.empty nf
       pure IsTerminating

paramPositive defs seen tc i
    = if (tc, i) `elem` seen then pure True else
      do Just gdef <- lookupCtxtExact tc (gamma defs)
           | Nothing => pure False -- not loaded: nothing is known about it
         case recorded (flags gdef) of
           Just ps => pure (i `elem` ps)
           Nothing => do
             let TCon _ _ _ _ _ mcons _ = definition gdef
               | _ => pure False
             -- A type with no constructors (an external type such as
             -- `ArrayData`, or an empty or abstract one) uses its parameters
             -- strictly positively: Idris code has no way to make one of
             -- its values, so none can hold a function of the parameter,
             -- and the primitives that make values of external types are
             -- trusted, as all primitives are.
             let cons = fromMaybe [] mcons
             allM conOK cons
  where
    -- Replace every binder by a distinct placeholder, collecting the
    -- argument types, until the return type `tc ...` is reached.
    peel : Int -> List ClosedNF -> ClosedNF -> Core (Maybe (List ClosedNF, ClosedNF))
    peel k acc (NBind fc x (Pi _ _ _ ty) sc)
        = do tyNF <- evalClosure defs ty
             let nm = Ref fc Bound (MN "POSPARAM" k)
             sc' <- sc defs (toClosure defaultOpts Env.empty nm)
             peel (k + 1) (tyNF :: acc) sc'
    peel k acc ret = pure (Just (acc, ret))

    -- The placeholder, possibly eta-expanded as `\x1 .. xn => p x1 .. xn`
    -- (a parameter of function type is often written so, see #660).
    etaVar : Int -> List Name -> ClosedNF -> Core (Maybe Name)
    etaVar k vs (NBind fc x (Lam {}) sc)
        = do let v = MN "POSETA" k
             sc' <- sc defs (toClosure defaultOpts Env.empty (Ref fc Bound v))
             etaVar (k + 1) (vs ++ [v]) sc'
    etaVar k vs (NApp _ (NRef Bound p) args)
        = do args' <- traverse (evalClosure defs . snd) args
             pure $ if not (p `elem` vs) && map boundName args' == map Just vs
                       then Just p else Nothing
      where
        boundName : ClosedNF -> Maybe Name
        boundName (NApp _ (NRef Bound n) []) = Just n
        boundName _ = Nothing
    etaVar k vs _ = pure Nothing

    paramName : ClosedNF -> Core (Maybe Name)
    paramName (NTCon _ n _ _ args)
        = if n /= tc then pure Nothing else
          case drop i (map snd args) of
            (cl :: _) => etaVar 0 [] !(evalClosure defs cl)
            [] => pure Nothing
    paramName _ = pure Nothing


    inIndex : Name -> ClosedNF -> Core Bool
    inIndex p (NTCon _ _ _ _ args)
        = do Just (TCon _ params _ _ _ _ _) <- lookupDefExact tc (gamma defs)
               | _ => pure True
             let (_, indices) = NatSet.partition params (map snd args)
             anyM (\cl => nameIn defs [p] !(evalClosure defs cl)) indices
    inIndex p _ = pure True

    conOK : Name -> Core Bool
    conOK cn
        = do Just ty <- lookupTyExact cn (gamma defs)
               | Nothing => pure False
             tyNF <- nf defs Env.empty ty
             Just (argTys, ret) <- peel 0 [] tyNF
               | Nothing => pure False
             -- unexpected shape of the return type: be conservative
             Just p <- paramName ret
               | Nothing => pure False
             -- A parameter that also appears in an index of the return type
             -- can be transported by matching (as in `Refl : x = x`), so
             -- `Abs : (D = e) -> (e -> Void) -> D` hides a negative
             -- occurrence of D. Such a parameter is not strictly positive.
             False <- inIndex p ret
               | True => pure False
             let seen' = (tc, i) :: seen
             allM (\a => do IsTerminating <- posArg defs seen' [p] a
                              | _ => pure False
                            pure True) argTys

fnArgPositive defs seen fn j
    = if (fn, j) `elem` seen then pure True else
      do Just (PMDef _ _ _ _ pats) <- lookupDefExact fn (gamma defs)
           | _ => do logC "totality.positivity" 50 $
                       pure $ "Not a function defined by clauses: "
                              ++ show !(toFullNames fn)
                     pure False
         -- no clauses (e.g. not yet defined): nothing is known about it
         let (_ :: _) = pats
           | [] => do logC "totality.positivity" 50 $
                        pure $ "No clauses: " ++ show !(toFullNames fn)
                      pure False
         allM clauseOK pats
  where
    -- Replace the lambdas closing over the clause environment by
    -- placeholders, outermost first.
    peel : Int -> ClosedNF -> Core ClosedNF
    peel k (NBind fc x (Lam {}) sc)
        = do sc' <- sc defs (toClosure defaultOpts Env.empty
                               (Ref fc Bound (MN "POSFN" k)))
             peel (k + 1) sc'
    peel k tm = pure tm

    -- Lets in the environment stay lets in `abstractEnv` and are reduced
    -- away by `nf`, so only the other binders become lambdas.
    countLams : Env Term ws -> Nat
    countLams [] = 0
    countLams (b :: env) = (if isLet b then 0 else 1) + countLams env

    -- The position, counting lambdas from the outside, of the variable with
    -- de Bruijn index `idx`; Nothing if it is let bound.
    lamPos : Nat -> Env Term ws -> Maybe Nat
    lamPos Z (b :: env) = if isLet b then Nothing else Just (countLams env)
    lamPos (S k) (b :: env) = lamPos k env
    lamPos _ [] = Nothing

    -- An as-pattern binding becomes a lambda in `abstractEnv`, which would
    -- hide its value from the check; be conservative about those.
    hasPLet : Env Term ws -> Bool
    hasPLet [] = False
    hasPLet (PLet {} :: env) = True
    hasPLet (_ :: env) = hasPLet env

    -- A pattern variable, possibly as `x@_` (case blocks bind their
    -- arguments that way); `x@(C ...)` is a type-case and doesn't count.
    patVar : Term ws -> Maybe Nat
    patVar (Local _ _ idx _) = Just idx
    patVar (As _ _ (Local _ _ idx _) (Erased {})) = Just idx
    patVar (As _ _ (Erased {}) (Local _ _ idx _)) = Just idx
    -- not `x@y`: the right hand side could use y, which we don't track
    patVar _ = Nothing

    clauseOK : (vs : Scope ** (Env Term vs, Term vs, Term vs)) -> Core Bool
    clauseOK (vs ** (env, lhs, rhs))
        = if hasPLet env then pure False else
          do let (_, largs) = getFnArgs lhs
             logTerm "totality.positivity" 50
               ("Checking argument " ++ show j ++ " in clause") lhs
             -- argument j must be matched by a plain pattern variable: a
             -- constructor pattern there is a type-case, which can observe
             -- the argument in any way it likes
             let (a :: _) = drop j largs
               | _ => pure False
             let Just idx = patVar a
               | _ => do log "totality.positivity" 50 "Not a pattern variable"
                         pure False
             let Just k = lamPos idx env
               | Nothing => do log "totality.positivity" 50 "Let bound"
                               pure False
             let p = MN "POSFN" (cast k)
             rhsNF <- peel 0 !(nf defs Env.empty (abstractEnv emptyFC env rhs))
             IsTerminating <- posArg defs ((fn, j) :: seen) [p] rhsNF
               | _ => pure False
             pure True

checkPosArgs : {auto c : Ref Ctxt Defs} ->
               Defs -> List Name -> ClosedNF -> Core Terminating
checkPosArgs defs tyns (NBind fc x (Pi _ _ e ty) sc)
    = case !(posArg defs [] tyns !(evalClosure defs ty)) of
           IsTerminating =>
               do let nm = Ref fc Bound (MN ("POSCHECK_" ++ show x) 0)
                  let arg = toClosure defaultOpts Env.empty nm
                  checkPosArgs defs tyns !(sc defs arg)
           bad => pure bad
checkPosArgs defs tyns nf
  = do logNF "totality.positivity" 50 "Giving up on non-Pi type" Env.empty nf
       pure IsTerminating

checkCon : {auto c : Ref Ctxt Defs} ->
           Defs -> List Name -> Name -> Core Terminating
checkCon defs tyns cn
    = case !(lookupTyExact cn (gamma defs)) of
        Nothing => do log "totality.positivity" 20 $
                        "Couldn't find constructor " ++ show cn
                      pure Unchecked
        Just ty =>
          case !(totRefsIn defs ty) of
            IsTerminating =>
              do tyNF <- nf defs Env.empty ty
                 logNF "totality.positivity" 20 "Checking the type " Env.empty tyNF
                 checkPosArgs defs tyns tyNF
            bad => pure bad

checkData : {auto c : Ref Ctxt Defs} ->
            Defs -> List Name -> List Name -> Core Terminating
checkData defs tyns [] = pure IsTerminating
checkData defs tyns (c :: cs)
    = do log "totality.positivity" 40 $
           "Checking positivity of constructor " ++ show c
         case !(checkCon defs tyns c) of
           IsTerminating => checkData defs tyns cs
           bad => pure bad

blockingAssertTotal : {auto c : Ref Ctxt Defs} -> FC -> Core a -> Core a
blockingAssertTotal loc ma
  = do defs <- get Ctxt
       let at = NS builtinNS (UN $ Basic "assert_total")
       Just _ <- lookupCtxtExact at (gamma defs)
         | Nothing => ma
       setVisibility loc at Private
       a <- ma
       setVisibility loc at Public
       pure a

-- Calculate whether a type satisfies the strict positivity condition, and
||| Record, as a flag of every type constructor of the current module, which
||| of its parameters its constructors use strictly positively.  A module that
||| imports the type constructor then needs neither its constructors nor the
||| types that they mention, which it may not load (those of a module that
||| the module of the type constructor imports privately): without this, a
||| parameter used negatively through a type of such a module could not be
||| told from a positive one.  Called when the module is complete, so that the
||| constructors of all its types (mutual ones too) are known.
export
recordPositiveParams : {auto c : Ref Ctxt Defs} -> Core ()
recordPositiveParams
    = do defs <- get Ctxt
         traverse_ recordFor (keys (toSave defs))
  where
    recordFor : Name -> Core ()
    recordFor n
        = do defs <- get Ctxt
             Just gdef <- lookupCtxtExact n (gamma defs)
               | Nothing => pure ()
             let TCon _ params _ _ _ _ _ = definition gdef
               | _ => pure ()
             let Nothing = recorded (flags gdef)
               | Just _ => pure ()
             -- (nothing to record without parameters)
             let False = isEmpty params
               | True => pure ()
             -- (paramPositive compares with the names in the types, which
             -- are resolved)
             rn <- toResolvedNames n
             pos <- filterM (paramPositive defs [] rn) (toList params)
             logC "totality.positivity" 10 $
               pure $ "Positive parameters of " ++ show !(toFullNames n) ++ ": " ++ show pos
             setFlag emptyFC n (PositiveParams (foldr insert NatSet.empty pos))

-- return whether it's terminating, along with its data constructors
export
calcPositive : {auto c : Ref Ctxt Defs} ->
               FC -> Name -> Core (Terminating, List Name)
calcPositive loc n
    = do defs <- get Ctxt
         logC "totality.positivity" 6 $ do pure $ "Calculating positivity: " ++ show !(toFullNames n)
         case !(lookupDefTyExact n (gamma defs)) of
              Just (TCon _ _ _ _ tns dcons _, ty) =>
                  let dcons = fromMaybe [] dcons in
                  case !(totRefsIn defs ty) of
                       IsTerminating =>
                            do log "totality.positivity" 30 $
                                 "Now checking constructors of " ++ show !(toFullNames n)
                               t <- blockingAssertTotal loc $ checkData defs (n :: tns) dcons
                               pure (t , dcons)
                       bad => pure (bad, dcons)
              Just _ => throw (GenericMsg loc (show n ++ " not a data type"))
              Nothing => undefinedName loc n
