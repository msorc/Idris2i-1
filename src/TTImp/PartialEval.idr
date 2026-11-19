module TTImp.PartialEval

import Core.Env
import Core.Hash
import Core.Metadata
import Core.Value
import Core.UnifyState

import Idris.REPL.Opts
import Idris.Syntax

import TTImp.Elab.Check
import TTImp.ProcessFnOpt
import TTImp.TTImp
import TTImp.TTImp.Functor
import TTImp.TTImp.Traversals
import TTImp.Unelab

import Protocol.Hex

import Libraries.Data.ANameMap
import Libraries.Data.NameMap
import Libraries.Data.UserNameMap
import Libraries.Data.NatSet
import Libraries.Data.WithDefault
import Libraries.Data.SnocList.SizeOf
import Libraries.Data.String.Iterator

%default covering

data ArgMode' tm = Static tm | Dynamic

ArgMode : Type
ArgMode = ArgMode' ClosedTerm

traverseArgMode : (a -> Core b) -> ArgMode' a -> Core (ArgMode' b)
traverseArgMode f (Static t) = Static <$> f t
traverseArgMode f Dynamic = pure Dynamic

covering
Show a => Show (ArgMode' a) where
  show (Static tm) = "Static " ++ show tm
  show Dynamic = "Dynamic"


getStatic : ArgMode -> Maybe ClosedTerm
getStatic Dynamic = Nothing
getStatic (Static t) = Just t

-- The key of a specialised copy: a hash of the function and of the static
-- arguments that it is specialised by, which names the copy.  (`hash` of
-- Core.Hash multiplies by 33 and adds, so that sequences like the names
-- `Ab` and `BA` hash alike: a copy made for one was used for the other.
-- This one mixes every word into all the bits of the state.)  The names in
-- the arguments are full names; the binders of the arguments are not
-- hashed, nor their locations, as they are not compared either (see
-- copyName).
namespace SpecKey
  export
  mixKey : Int -> Int -> Int
  mixKey h w
      = let y = prim__mul_Int (prim__xor_Int h w) (-7046029254386353131) in
            prim__xor_Int y (prim__and_Int (prim__shr_Int y 29) 0x7ffffffff)

  keyString : Int -> String -> Int
  keyString h s = mixKey (Iterator.foldl (\k, c => mixKey k (ord c)) h s) (cast (length s))

  keyUN : Int -> UserName -> Int
  keyUN h (Basic s) = keyString (mixKey h 1) s
  keyUN h (Field s) = keyString (mixKey h 2) s
  keyUN h Underscore = mixKey h 3

  export
  keyName : Int -> Name -> Int
  keyName h (NS ns n)
      = let ss = unsafeUnfoldNamespace ns in
            keyName (mixKey (foldl keyString (mixKey h 1) ss) (cast (length ss))) n
  keyName h (UN un) = keyUN (mixKey h 2) un
  keyName h (MN s i) = mixKey (keyString (mixKey h 3) s) i
  keyName h (PV n i) = mixKey (keyName (mixKey h 4) n) i
  keyName h (DN _ n) = keyName h n
  keyName h (Nested (i, j) n) = keyName (mixKey (mixKey (mixKey h 6) i) j) n
  keyName h (CaseBlock s i) = mixKey (keyString (mixKey h 7) s) i
  keyName h (WithBlock s i) = mixKey (keyString (mixKey h 8) s) i
  keyName h (Resolved i) = mixKey (mixKey h 9) i

  -- (`show` does not tell apart the types of numbers)
  constKind : Constant -> Int
  constKind (I _) = 0
  constKind (I8 _) = 1
  constKind (I16 _) = 2
  constKind (I32 _) = 3
  constKind (I64 _) = 4
  constKind (BI _) = 5
  constKind (B8 _) = 6
  constKind (B16 _) = 7
  constKind (B32 _) = 8
  constKind (B64 _) = 9
  constKind (Str _) = 10
  constKind (Ch _) = 11
  constKind (Db _) = 12
  constKind (PrT _) = 13
  constKind WorldVal = 14

  keyRig : Int -> RigCount -> Int
  keyRig h = elimSemi (mixKey h 0) (mixKey h 1) (const $ mixKey h 2)

  mutual
    keyPi : Int -> PiInfo (Term vs) -> Int
    keyPi h Implicit = mixKey h 0
    keyPi h Explicit = mixKey h 1
    keyPi h AutoImplicit = mixKey h 2
    keyPi h (DefImplicit t) = keyTerm (mixKey h 3) t

    keyBinder : Int -> Binder (Term vs) -> Int
    keyBinder h (Lam _ c p ty) = keyTerm (keyPi (keyRig (mixKey h 0) c) p) ty
    keyBinder h (Let _ c val ty) = keyTerm (keyTerm (keyRig (mixKey h 1) c) val) ty
    keyBinder h (Pi _ c p ty) = keyTerm (keyPi (keyRig (mixKey h 2) c) p) ty
    keyBinder h (PVar _ c p ty) = keyTerm (keyPi (keyRig (mixKey h 3) c) p) ty
    keyBinder h (PLet _ c val ty) = keyTerm (keyTerm (keyRig (mixKey h 4) c) val) ty
    keyBinder h (PVTy _ c ty) = keyTerm (keyRig (mixKey h 5) c) ty

    export
    keyTerm : Int -> Term vs -> Int
    keyTerm h (Local _ _ idx _) = mixKey (mixKey h 0) (cast idx)
    keyTerm h (Ref _ _ n) = keyName (mixKey h 1) n
    keyTerm h (Meta _ _ i args) = foldl keyTerm (mixKey (mixKey h 2) i) args
    keyTerm h (Bind _ _ b sc) = keyTerm (keyBinder (mixKey h 3) b) sc
    keyTerm h (App _ f a) = keyTerm (keyTerm (mixKey h 4) f) a
    keyTerm h (As _ _ a p) = keyTerm (keyTerm (mixKey h 5) a) p
    keyTerm h (TDelayed _ _ t) = keyTerm (mixKey h 6) t
    keyTerm h (TDelay _ _ t x) = keyTerm (keyTerm (mixKey h 7) t) x
    keyTerm h (TForce _ _ t) = keyTerm (mixKey h 8) t
    keyTerm h (PrimVal _ c) = keyString (mixKey (mixKey h 9) (constKind c)) (show c)
    keyTerm h (Erased _ _) = mixKey h 10
    keyTerm h (TType _ _) = mixKey h 11

specialiseTy : {vars : _} ->
               Nat -> List (Nat, ClosedTerm) -> Term vars -> Term vars
specialiseTy i specs (Bind fc x (Pi fc' c p ty) sc)
    = case lookup i specs of
           Nothing => Bind fc x (Pi fc' c p ty) $ -- easier later if everything explicit
                        specialiseTy (1 + i) specs sc
           Just tm => specialiseTy (1 + i) specs (subst (embed tm) sc)
specialiseTy i specs tm = tm

substLoc : {vs : _} ->
           Nat -> Term vs -> Term vs -> Term vs
substLoc i tm (Local fc l idx p)
    = if i == idx then tm else (Local fc l idx p)
substLoc i tm (Bind fc x b sc)
    = Bind fc x (map (substLoc i tm) b) (substLoc (1 + i) (weaken tm) sc)
substLoc i tm (Meta fc n r args)
    = Meta fc n r (map (substLoc i tm) args)
substLoc i tm (App fc f a) = App fc (substLoc i tm f) (substLoc i tm a)
substLoc i tm (As fc s f a) = As fc s (substLoc i tm f) (substLoc i tm a)
substLoc i tm (TDelayed fc r d) = TDelayed fc r (substLoc i tm d)
substLoc i tm (TDelay fc r ty d) = TDelay fc r (substLoc i tm ty) (substLoc i tm d)
substLoc i tm (TForce fc r d) = TForce fc r (substLoc i tm d)
substLoc i tm x = x

substLocs : {vs : _} ->
            List (Nat, Term vs) -> Term vs -> Term vs
substLocs [] tm = tm
substLocs ((i, tm') :: subs) tm = substLocs subs (substLoc i tm' tm)

mkSubsts : Nat -> List (Nat, ClosedTerm) ->
           List (Term vs) -> Term vs -> Maybe (List (Nat, Term vs))
mkSubsts i specs [] rhs = Just []
mkSubsts i specs (arg :: args) rhs
    = do subs <- mkSubsts (1 + i) specs args rhs
         case lookup i specs of
              Nothing => Just subs
              Just tm => case arg of
                              Local _ _ idx _ =>
                                   Just ((idx, embed tm) :: subs)
                              As _ _ (Local _ _ idx1 _) (Local _ _ idx2 _) =>
                                   Just ((idx1, embed tm) :: (idx2, embed tm) :: subs)
                              As _ _ _ (Local _ _ idx _) =>
                                   Just ((idx, embed tm) :: subs)
                              _ => Nothing

-- In the case where all the specialised positions are variables on the LHS,
-- substitute the term in on the RHS
specPatByVar : List (Nat, ClosedTerm) ->
                (vs ** (Env Term vs, Term vs, Term vs)) ->
                Maybe (vs ** (Env Term vs, Term vs, Term vs))
specPatByVar specs (vs ** (env, lhs, rhs))
    = do let (fn, args) = getFnArgs lhs
         psubs <- mkSubsts 0 specs args rhs
         let lhs' = apply (getLoc fn) fn args
         pure (vs ** (env, substLocs psubs lhs', substLocs psubs rhs))

specByVar : List (Nat, ClosedTerm) ->
            List (vs ** (Env Term vs, Term vs, Term vs)) ->
            Maybe (List (vs ** (Env Term vs, Term vs, Term vs)))
specByVar specs [] = pure []
specByVar specs (p :: ps)
    = do p' <- specPatByVar specs p
         ps' <- specByVar specs ps
         pure (p' :: ps')

dropSpec : Nat -> List (Nat, ClosedTerm) -> List a -> List a
dropSpec i sargs [] = []
dropSpec i sargs (x :: xs)
    = case lookup i sargs of
           Nothing => x :: dropSpec (1 + i) sargs xs
           Just _ => dropSpec (1 + i) sargs xs

getSpecPats : {auto c : Ref Ctxt Defs} ->
              {auto u : Ref UST UState} ->
              FC -> Name ->
              (fn : Name) -> (stk : List (FC, Term vars)) ->
              ClosedNF -> -- Type of 'fn'
              List (Nat, ArgMode) -> -- All the arguments
              List (Nat, ClosedTerm) -> -- Just the static ones
              List (vs ** (Env Term vs, Term vs, Term vs)) ->
              Core (Maybe (List ImpClause))
getSpecPats fc pename fn stk fnty args sargs pats
   = do -- First, see if all the specialised positions are variables. If so,
        -- substitute the arguments directly into the RHS
        let Nothing = specByVar sargs pats
            | Just specpats =>
                   do ps <- traverse (unelabPat pename) specpats
                      pure (Just ps)
        -- Otherwise, build a new definition by taking the remaining arguments
        -- on the lhs, and using the specialised function application on the rhs.
        -- Then, this will get evaluated on elaboration.
        dynnames <- mkDynNames args
        let lhs = apply (IVar fc pename) (map (IBindVar fc) dynnames)
        rhs <- mkRHSargs fnty (IVar fc fn) dynnames args
        pure (Just [PatClause fc lhs rhs])
  where
    mkDynNames : List (Nat, ArgMode) -> Core (List Name)
    mkDynNames [] = pure []
    mkDynNames ((_, Dynamic) :: as) = [| genVarName "_pe" :: mkDynNames as |]
    mkDynNames (_ :: as) = mkDynNames as

    -- Build a RHS from the type of the function to be specialised, the
    -- dynamic argument names, and the list of given arguments. We assume
    -- the latter two correspond appropriately.
    mkRHSargs : ClosedNF -> RawImp -> List Name -> List (Nat, ArgMode) ->
                Core RawImp
    mkRHSargs (NBind _ x (Pi _ _ Explicit _) sc) app (a :: as) ((_, Dynamic) :: ds)
        = do defs <- get Ctxt
             sc' <- sc defs (toClosure defaultOpts Env.empty (Erased fc Placeholder))
             mkRHSargs sc' (IApp fc app (IVar fc a)) as ds
    mkRHSargs (NBind _ x (Pi {}) sc) app (a :: as) ((_, Dynamic) :: ds)
        = do defs <- get Ctxt
             sc' <- sc defs (toClosure defaultOpts Env.empty (Erased fc Placeholder))
             mkRHSargs sc' (INamedApp fc app x (IVar fc a)) as ds
    mkRHSargs (NBind _ x (Pi _ _ Explicit _) sc) app as ((_, Static tm) :: ds)
        = do defs <- get Ctxt
             sc' <- sc defs (toClosure defaultOpts Env.empty (Erased fc Placeholder))
             tm' <- unelabNoSugar Env.empty tm
             mkRHSargs sc' (IApp fc app (map rawName tm')) as ds
    mkRHSargs (NBind _ x (Pi _ _ Implicit _) sc) app as ((_, Static tm) :: ds)
        = do defs <- get Ctxt
             sc' <- sc defs (toClosure defaultOpts Env.empty (Erased fc Placeholder))
             tm' <- unelabNoSugar Env.empty tm
             mkRHSargs sc' (INamedApp fc app x (map rawName tm')) as ds
    mkRHSargs (NBind _ _ (Pi _ _ AutoImplicit _) sc) app as ((_, Static tm) :: ds)
        = do defs <- get Ctxt
             sc' <- sc defs (toClosure defaultOpts Env.empty (Erased fc Placeholder))
             tm' <- unelabNoSugar Env.empty tm
             mkRHSargs sc' (IAutoApp fc app (map rawName tm')) as ds
    -- Type will depend on the value here (we assume a variadic function) but
    -- the argument names are still needed
    mkRHSargs ty app (a :: as) ((_, Dynamic) :: ds)
        = mkRHSargs ty (IApp fc app (IVar fc a)) as ds
    mkRHSargs _ app _ _
        = pure app

    getRawArgs : List (Arg' Name) -> RawImp -> List (Arg' Name)
    getRawArgs args (IApp fc f arg) = getRawArgs (Explicit fc arg :: args) f
    getRawArgs args (INamedApp fc f n arg)
        = getRawArgs (Named fc n arg :: args) f
    getRawArgs args (IAutoApp fc f arg)
        = getRawArgs (Auto fc arg :: args) f
    getRawArgs args tm = args

    reapply : RawImp -> List (Arg' Name) -> RawImp
    reapply f [] = f
    reapply f (Explicit fc arg :: args) = reapply (IApp fc f arg) args
    reapply f (Named fc n arg :: args)
        = reapply (INamedApp fc f n arg) args
    reapply f (Auto fc arg :: args)
        = reapply (IAutoApp fc f arg) args

    dropArgs : Name -> RawImp -> RawImp
    dropArgs pename tm = reapply (IVar fc pename) (dropSpec 0 sargs (getRawArgs [] tm))

    unelabPat : Name -> (vs ** (Env Term vs, Term vs, Term vs)) ->
                Core ImpClause
    unelabPat pename (vs0 ** (env0, lhs0, rhs0))
        = do -- Two pattern variables can have the same name (in a local
             -- definition, a pattern variable of the parent function and one
             -- of its own, `xs` and `x :: xs`): they are renamed apart, or
             -- the LHS that is elaborated again would not be linear.
             let (vs ** (env, compat)) = uniqifyEnv env0
             let lhs = compatTerm compat lhs0
             let rhs = compatTerm compat rhs0
             logTerm "specialise" 20 "Unelaborating LHS:" lhs
             lhsapp <- unelabNoSugar env lhs
             log "specialise" 20 $ "Unelaborating LHS to: \{show lhsapp}"
             let lhs' = bindMachineNames vs $ dropArgs pename (map rawName lhsapp)
             defs <- get Ctxt
             rhs <- normaliseArgHoles defs env rhs
             rhs <- unelabNoSugar env rhs
             let rhs = flip mapTTImp rhs $ \case
                      IHole fc _ => Implicit fc False
                      tm => tm
             pure (PatClause fc lhs' (map rawName rhs))
      where
        -- Only user names are bound as pattern variables when the LHS is
        -- elaborated again, so a pattern variable with a machine name (the
        -- one of a `_` in a case block, say) is bound explicitly.
        bindMachineNames : List Name -> RawImp -> RawImp
        bindMachineNames vs = mapTTImp $ \case
          IVar vfc n@(MN {}) => if n `elem` vs then IBindVar vfc n else IVar vfc n
          tm => tm

    unelabLHS : Name -> (vs ** (Env Term vs, Term vs, Term vs)) ->
                Core RawImp
    unelabLHS pename (_ ** (env, lhs, rhs))
        = do lhsapp <- unelabNoSugar env lhs
             pure $ dropArgs pename (map rawName lhsapp)

-- Specialising by the implementations of interfaces (--spec-interfaces)
--
-- With the option, a function that takes implementations of interfaces
-- (`Ord a => ...`) is specialised by them where they are known, as if it was
-- declared `%spec` on them: the methods of a known implementation are known
-- functions, so the copy calls them directly (or inlines them) instead of
-- applying the closures of a dictionary.  This is for functions that are
-- small, or recursive (where the methods are called again and again) and not
-- too big, and for at most `autoSpecLimit` functions per module, so that the
-- code does not grow too much.  Specialising one function makes the calls
-- that its copy makes with known implementations specialised in turn (see
-- quoteGenNF).

-- The size of a term: roughly its number of nodes.
termSize : Term vs -> Nat
termSize (Bind _ _ b sc) = 1 + termSize (binderType b) + termSize sc
termSize (App _ f a) = 1 + termSize f + termSize a
termSize (Meta _ _ _ as) = 1 + foldl (\n, t => n + termSize t) 0 as
termSize (As _ _ _ p) = termSize p
termSize (TDelayed _ _ t) = 1 + termSize t
termSize (TDelay _ _ _ t) = 1 + termSize t
termSize (TForce _ _ t) = 1 + termSize t
termSize _ = 1

-- Specialised by its interfaces when it is at most this big...
autoSpecSmall : Nat
autoSpecSmall = 150

-- ... or recursive, and at most this big.
autoSpecRecursive : Nat
autoSpecRecursive = 1500

-- The size of a clause of a copy after reduction, at most.
autoSpecReduced : Nat
autoSpecReduced = 5000

-- The size of an argument that a function is specialised by that way, at
-- most.
autoSpecArgSize : Nat
autoSpecArgSize = 200

-- How many copies made that way can be elaborated one in another (a copy
-- calls functions that are specialised in turn) at most, and how many of
-- them can be copies of one function (a recursive function can take a
-- copy of its implementation that is reduced a bit more each time, before
-- the copies are the same).
autoSpecMaxDepth : Nat
autoSpecMaxDepth = 16

autoSpecRepeat : Nat
autoSpecRepeat = 4

-- The number of functions that a module specialises that way.
autoSpecLimit : Nat
autoSpecLimit = 400

-- The names of the arguments of a type that are implementations of
-- interfaces (an `auto` argument, or another one for the case blocks and
-- local definitions that take the implementations of their parent).
interfaceArgs : {auto c : Ref Ctxt Defs} ->
                {auto s : Ref Syn SyntaxInfo} ->
                Term vs -> Core (List Name)
interfaceArgs (Bind _ x (Pi _ rig _ ty) sc)
    = do rest <- interfaceArgs sc
         case getFn ty of
              Ref _ (TyCon _) n =>
                if isErased rig then pure rest else do
                  n' <- toFullNames n
                  syn <- get Syn
                  pure $ if isJust (lookupExact n' (ifaces syn))
                            then x :: rest else rest
              _ => pure rest
interfaceArgs _ = pure []

-- Is a type the type of proofs, which there is nothing to compute with at
-- run time: `Type`, `Void` or an equality, after its arguments.  (Nothing
-- when the result is the application of a function, `x = y` is `x === y`
-- say: the type is to be evaluated first, see isProofNF.)
isProofType : {auto c : Ref Ctxt Defs} -> Term vs -> Core (Maybe Bool)
isProofType (Bind _ _ (Pi {}) sc) = isProofType sc
isProofType (TType {}) = pure (Just True)
isProofType ty
    = case getFn ty of
           Ref _ (TyCon _) n =>
             do n' <- toFullNames n
                pure $ Just (n' == NS builtinNS (UN $ Basic "Equal")
                             || n' == NS builtinNS (UN $ Basic "Void"))
           Ref _ Func _ => pure Nothing
           _ => pure (Just False)

-- The same, on the normal form of a type, which is evaluated lazily, under
-- at most `fuel` binders: a type that is not total can unfold forever
-- (`K = K -> Void`), so the type is not normalised.
isProofNF : {auto c : Ref Ctxt Defs} -> (fuel : Nat) -> ClosedNF -> Core Bool
isProofNF (S k) (NBind fc _ (Pi {}) sc)
    = do defs <- get Ctxt
         isProofNF k !(sc defs (toClosure defaultOpts Env.empty (Erased fc Placeholder)))
isProofNF _ (NType {}) = pure True
isProofNF _ (NTCon _ n _ _)
    = do n' <- toFullNames n
         pure (n' == NS builtinNS (UN $ Basic "Equal")
               || n' == NS builtinNS (UN $ Basic "Void"))
isProofNF _ _ = pure False

isProofTypeNF : {auto c : Ref Ctxt Defs} -> ClosedTerm -> Core Bool
isProofTypeNF ty
    = do Nothing <- isProofType ty
           | Just p => pure p
         defs <- get Ctxt
         isProofNF 100 !(nf defs Env.empty ty)

-- An interface whose methods are all proofs (like `Uninhabited` or
-- `Injective`), from the fields of its constructor (a field for a parent
-- interface is not a proof): a copy by its implementations would compute
-- nothing faster, and the proofs can be costly to reduce.
proofInterface : {auto c : Ref Ctxt Defs} ->
                 {auto s : Ref Syn SyntaxInfo} ->
                 Name -> Core Bool
proofInterface iface
    = do syn <- get Syn
         Just info <- pure (lookupExact iface (ifaces syn))
           | Nothing => pure False
         defs <- get Ctxt
         Just cdef <- lookupCtxtExact (iconstructor info) (gamma defs)
           | Nothing => pure False
         fields (the Nat 100) !(nf defs Env.empty (type cdef))
  where
    fields : Nat -> ClosedNF -> Core Bool
    fields (S k) (NBind fc _ (Pi _ rig _ fty) sc)
        = do defs <- get Ctxt
             prf <- if isErased rig then pure True
                       else isProofNF 100 !(evalClosure defs fty)
             if not prf then pure False else
               fields k !(sc defs (toClosure defaultOpts Env.empty (Erased fc Placeholder)))
    fields Z _ = pure False
    fields _ _ = pure True

-- The arguments of a type that --spec-interfaces specialises by: the
-- implementations of interfaces that are not proof interfaces.  None when
-- the function computes a proof (or a type): the copy would gain nothing at
-- run time.
autoInterfaceArgs : {auto c : Ref Ctxt Defs} ->
                    {auto s : Ref Syn SyntaxInfo} ->
                    ClosedTerm -> Core (List Name)
autoInterfaceArgs ty
    = if !(isProofTypeNF ty) then pure [] else go ty
  where
    go : Term vs' -> Core (List Name)
    go (Bind _ x (Pi _ rig _ aty) sc)
        = do rest <- go sc
             case getFn aty of
                  Ref _ (TyCon _) n =>
                    if isErased rig then pure rest else do
                      n' <- toFullNames n
                      syn <- get Syn
                      pure $ if isJust (lookupExact n' (ifaces syn))
                                && not !(proofInterface n')
                                then x :: rest else rest
                  _ => pure rest
    go _ = pure []

-- The arguments that the function is specialised by when its interfaces
-- are known (empty when it is not).
autoSpecArgs : {auto c : Ref Ctxt Defs} ->
               {auto s : Ref Syn SyntaxInfo} ->
               FC -> Name -> GlobalDef -> Core NatSet
autoSpecArgs fc fn gdef
    = do let PMDef _ _ _ _ pats = definition gdef
             | _ => pure NatSet.empty
         defs <- get Ctxt
         fnfull <- toFullNames fn
         case lookup fnfull (autoSpecs defs) of
              Just specs => pure specs
              Nothing =>
                do ns <- autoInterfaceArgs (type gdef)
                   let size = foldl (\n, (_ ** (_, _, rhs)) => n + termSize rhs) 0 pats
                   refs <- traverse toFullNames (keys (refersTo gdef))
                   let recursive = fnfull `elem` refs
                   specs <- if null ns
                               || not (size <= autoSpecSmall
                                       || (recursive && size <= autoSpecRecursive))
                               then pure NatSet.empty
                               else specPositions fc gdef ns
                   log "specialise.auto" 10 $
                     "\{show fnfull}: interface arguments \{show ns}, size \{show size}"
                     ++ (if recursive then ", recursive" else "")
                     ++ ", specialised by \{show specs}"
                   update Ctxt { autoSpecs $= insert fnfull specs }
                   pure specs

-- The names that a definition refers to, in full.
fullRefs : {auto c : Ref Ctxt Defs} -> GlobalDef -> Core (List Name)
fullRefs d = traverse toFullNames (keys (refersTo d))

-- In the reduction limits of a copy made by --spec-interfaces: the limits
-- are applied (see applySpecialise).
autoLimits : (Name, Nat)
autoLimits = (NS partialEvalNS (UN $ Basic "autoSpecLimits"), 0)

-- Get the reducible names in a function to be partially evaluated. In practice,
-- that's all the functions it refers to
-- TODO: May want to take care with 'partial' names?
getReducible : List Name -> -- calls to check
               NameMap Nat -> -- which nodes have been visited. If the entry is
                              -- present, it's visited
               Defs -> Core (NameMap Nat)
getReducible [] refs defs = pure refs
getReducible (n :: rest) refs defs
  = do let Nothing = lookup n refs
           | Just _ => getReducible rest refs defs
       case !(lookupCtxtExact n (gamma defs)) of
            Nothing => getReducible rest refs defs
            Just def =>
              do let refs' = insert n 65536 refs
                 let calls = refersTo def
                 getReducible (keys calls ++ rest) refs' defs

mkSpecDef : {auto c : Ref Ctxt Defs} ->
            {auto m : Ref MD Metadata} ->
            {auto u : Ref UST UState} ->
            {auto s : Ref Syn SyntaxInfo} ->
            {auto o : Ref ROpts REPLOpts} ->
            FC -> GlobalDef -> (isAuto : Bool) ->
            Name -> (statics : List ClosedTerm) ->
            List (Nat, ArgMode) -> Name -> List (FC, Term vars) ->
            Core (Term vars)
mkSpecDef {vars} fc gdef isAuto pename statics sargs fn stk
    = handleUnify {unResolve = True}
       (do defs <- get Ctxt
           setAllPublic True
           let staticargs
                 = mapMaybe (\ (x, s) => case s of
                                              Dynamic => Nothing
                                              Static t => Just (x, t)) sargs
           let peapp = applyStackWithFC (Ref fc Func pename) (dropSpec 0 staticargs stk)
           Nothing <- lookupCtxtExact pename (gamma defs)
               | Just _ => -- already specialised
                           do log "specialise" 5 $ "Already specialised " ++ show pename
                              pure peapp
           logC "specialise.declare" 5 $
                   do fnfull <- toFullNames fn
                      args' <- traverse (\ (i, arg) =>
                                   do arg' <- the (Core ArgMode) $ case arg of
                                                   Static a =>
                                                      pure $ Static !(toFullNames a)
                                                   Dynamic => pure Dynamic
                                      pure (show (i, arg'))) sargs
                      pure $ "Specialising " ++ show fnfull ++
                             " (" ++ show fn ++ ") -> \{show pename} by " ++
                             showSep ", " args'
           let sty = specialiseTy 0 staticargs (type gdef)
           logTermNF "specialise" 3 ("Specialised type " ++ show pename) Env.empty sty

           -- Add as RigW - if it's something else, we don't need it at
           -- runtime anyway so this is wasted effort, therefore a failure
           -- is okay!
           -- (a copy, made by `%spec` or by --spec-interfaces, is code of
           -- the program that was checked already: it is not checked again,
           -- against the default totality of the module where it is made,
           -- which may ask more of it than its function did.  Nor could it
           -- be: the copy runs the code of the implementations it is given,
           -- which a method hides from the totality checker, so it calls
           -- what they call, like `prim__mod_Int` (not covering) from `mod`
           -- of `Integral Int`, where its function only called `mod`.  How
           -- covering it is is taken from its function, see copyCovering.)
           let defflags : List DefFlag
                 = SetTotal PartialOK :: SpecStatics statics
                     :: filter (not . isSetTotal) (propagateFlags (flags gdef))
           log "specialise.flags" 20 "Defining \{show pename} with flags: \{show defflags}"
           peidx <- addDef pename
                  $ the (GlobalDef -> GlobalDef) { flags := defflags }
                  $ newDef fc pename top Scope.empty sty (specified Public) None
           addToSave (Resolved peidx)

           -- Reduce the function to be specialised, and reduce any name in
           -- the arguments at most once (so that recursive definitions aren't
           -- unfolded forever)
           let specnames = getAllRefs empty (map snd sargs)
           specLimits <- traverse (\n => pure (n, 1))
                                  (keys specnames)

           defs <- get Ctxt
           reds <- getReducible [fn] empty defs
           reds <- if isAuto then (autoLimits ::) <$> autoReducible staticargs (keys specnames) (toList reds)
                             else pure (toList reds)
           setFlag fc (Resolved peidx) (PartialEval (specLimits ++ reds))

           let PMDef pminfo pmargs ct tr pats = definition gdef
               | _ => pure (applyStackWithFC (Ref fc Func fn) stk)
           logC "specialise" 5 $
                   do inpats <- traverse unelabDef pats
                      pure $ "Attempting to specialise:\n" ++
                             showSep "\n" (map showPat inpats)

           Just newpats <- getSpecPats fc pename fn stk !(nf defs Env.empty (type gdef))
                                       sargs staticargs pats
                | Nothing => pure (applyStackWithFC (Ref fc Func fn) stk)
           log "specialise" 5 $ "New patterns for " ++ show pename ++ ":\n" ++
                    showSep "\n" (map showPat newpats)
           -- The copy is not in the source: what elaborating it records
           -- for the IDE (semantic highlighting, the locations and types of
           -- names) would show its names (`PE_...`, `_pe...`) at the
           -- locations of the call, so it is forgotten.
           -- (autoSpecStack: the functions whose copies made by
           -- --spec-interfaces are being elaborated, one in another, see
           -- specialise)
           md <- get MD
           fnfull <- toFullNames fn
           stack <- autoSpecStack <$> get Ctxt
           when isAuto $ update Ctxt { autoSpecStack := fnfull :: stack }
           let done = do put MD md
                         when isAuto $ update Ctxt { autoSpecStack := stack }
           processDecl [InPartialEval] (MkNested []) Env.empty
                       (IDef fc (Resolved peidx) newpats)
             `catch` (\err => do done; throw err)
           done
           copyCovering (Resolved peidx) (keys specnames)
           -- A copy made by --spec-interfaces of a function that does not
           -- call itself must not call itself either: that happens when the
           -- function could not be reduced, and the call left was
           -- specialised again, to the copy.  The copy is not used then.
           when isAuto $
             do bad <- callsItself (Resolved peidx)
                when bad $
                  do setAllPublic False
                     throw (GenericMsg fc "\{show pename} calls itself")
           setAllPublic False
           pure peapp)
           -- If the partially evaluated definition fails, just use the initial
           -- application. It might indicates a bug in the P.E. function generation
           -- if it fails, but I don't want the whole system to be dependent on
           -- the correctness of PE!
        (\err =>
           do logC "specialise.fail" 1 $ do
                 fn <- toFullNames fn
                 pure "Partial evaluation of \{show fn} failed:\n\{show err}"
              update Ctxt { peFailures $= insert pename () }
              -- (the copy may be defined already, and is saved in the TTC
              -- file: without its SpecStatics, the modules that import this
              -- one do not reuse it, see copyName)
              defs <- get Ctxt
              whenJust !(lookupCtxtExact pename (gamma defs)) $ \ d =>
                ignore $ addDef pename ({ flags $= filter (not . isSpecStatics) } d)
              pure (applyStackWithFC (Ref fc Func fn) stk))
  where
    -- A specialisation made because of --spec-interfaces only reduces the
    -- implementations that it is given (see specLimits) and the methods of
    -- interfaces, small functions that take an implementation (projections
    -- of a known implementation give its functions), once.  The function
    -- itself is reduced once when its clauses do not take the
    -- implementations as variables (see getSpecPats), not at all otherwise.
    -- (Reducing everything that the function refers to, as a `%spec` does,
    -- unfolds infinite structures like the streams of `iterate`.)  The
    -- list is never empty: an empty list would reduce everything.
    autoReducible : List (Nat, ClosedTerm) -> List Name -> List (Name, Nat) ->
                    Core (List (Name, Nat))
    autoReducible staticargs staticrefs reds
        = do defs <- get Ctxt
             let byVar = case definition gdef of
                              PMDef _ _ _ _ pats => isJust (specByVar staticargs pats)
                              _ => False
             glue <- allGlue defs
             pure ((fn, if byVar then 0 else 1) :: map (\n => (n, 1)) glue)
      where
        -- An implementation of an interface: its type is an interface.
        isImplementation : Defs -> Term vs -> Core Bool
        isImplementation defs (Bind _ _ (Pi {}) sc) = isImplementation defs sc
        isImplementation defs ty
            = case getFn ty of
                   Ref _ (TyCon _) n =>
                     do n' <- toFullNames n
                        syn <- get Syn
                        pure (isJust (lookupExact n' (ifaces syn)))
                   _ => pure False

        -- A method of an interface (a small function that takes an
        -- implementation), or an implementation.
        isGlue : Defs -> Name -> Core Bool
        isGlue defs n
            = do Just d <- lookupCtxtExact n (gamma defs)
                   | Nothing => pure False
                 let PMDef _ _ _ _ pats = definition d
                   | _ => pure False
                 if !(isImplementation defs (type d)) then pure True else do
                   let size = foldl (\k, (_ ** (_, _, rhs)) => k + termSize rhs) 0 pats
                   if size > 10 then pure False
                      else pure (not (null !(interfaceArgs (type d))))

        -- The glue that the function and the implementations it is given
        -- refer to, transitively through implementations (an
        -- implementation refers to the implementations of its parents).
        allGlue : Defs -> Core (List Name)
        allGlue defs
            = go [] (map fst reds ++ staticrefs)
          where
            go : List Name -> List Name -> Core (List Name)
            go acc [] = pure acc
            go acc (n :: ns)
                = if n `elem` acc then go acc ns else
                    if not !(isGlue defs n) then go acc ns else do
                      Just d <- lookupCtxtExact n (gamma defs)
                        | Nothing => go acc ns
                      let more = if !(isImplementation defs (type d))
                                    then keys (refersTo d) else []
                      go (n :: acc) (more ++ ns)

    -- Does the copy call itself, when the function does not?
    callsItself : Name -> Core Bool
    callsItself pen
        = do defs <- get Ctxt
             Just pedef <- lookupCtxtExact pen (gamma defs)
               | Nothing => pure False
             perefs <- fullRefs pedef
             fnrefs <- fullRefs gdef
             pefull <- toFullNames pename
             fnfull <- toFullNames fn
             pure (any (== pefull) perefs && not (any (== fnfull) fnrefs))

    -- Set how covering the copy is to how covering a call of the function
    -- by the static arguments is: that of the function and of the names in
    -- the arguments.  What the copy calls itself is not looked at (see
    -- the flags of the copy).  A copy that misses cases that its function
    -- does not miss is wrong (the patterns of the function do not all
    -- survive the specialisation), and is not used.
    copyCovering : Name -> List Name -> Core ()
    copyCovering pen staticrefs
        = do defs <- get Ctxt
             Just pedef <- lookupCtxtExact pen (gamma defs)
               | Nothing => pure ()
             let fncov = isCovering (totality gdef)
             case isCovering (totality pedef) of
                  IsCovering => pure ()
                  MissingCases cs =>
                    case fncov of
                         MissingCases _ => pure ()
                         _ => do setAllPublic False
                                 cs' <- traverse toFullNames cs
                                 throw (GenericMsg fc
                                   "\{show pename} misses cases that \{show fn} does not: \{show cs'}")
                  NonCoveringCall _ =>
                    do bad <- filterM (notCovering defs) staticrefs
                       let bad = case fncov of
                                      IsCovering => bad
                                      _ => fn :: bad
                       setCovering fc pen
                         (if null bad then IsCovering else NonCoveringCall bad)
      where
        notCovering : Defs -> Name -> Core Bool
        notCovering defs n
            = do Just d <- lookupCtxtExact n (gamma defs)
                   | Nothing => pure False
                 pure $ case isCovering (totality d) of
                             IsCovering => False
                             _ => True

    isSetTotal : DefFlag -> Bool
    isSetTotal (SetTotal _) = True
    isSetTotal _ = False

    isSpecStatics : DefFlag -> Bool
    isSpecStatics (SpecStatics _) = True
    isSpecStatics _ = False

    identityFlag : List (Nat, ArgMode) -> Nat -> Maybe Nat
    identityFlag [] k = pure k
    identityFlag ((pos, mode) :: sargs) k
      = k <$ guard (k < pos)
      <|> (case mode of { Static _ => (`minus` 1); Dynamic => id }) <$> identityFlag sargs k


    propagateFlags : List DefFlag -> List DefFlag
    propagateFlags = mapMaybe $ \case
      Deprecate => Nothing
      SpecStatics _ => Nothing
      Overloadable => Nothing
      Identity k => Identity <$> identityFlag sargs k
      fl => Just fl

    getAllRefs : NameMap Bool -> List ArgMode -> NameMap Bool
    getAllRefs ns (Dynamic :: xs) = getAllRefs ns xs
    getAllRefs ns (Static t :: xs)
        = addRefs False (UN Underscore) (getAllRefs ns xs) t
    getAllRefs ns [] = ns

    updateApp : Name -> RawImp -> RawImp
    updateApp n (IApp fc f a) = IApp fc (updateApp n f) a
    updateApp n (IAutoApp fc f a) = IAutoApp fc (updateApp n f) a
    updateApp n (INamedApp fc f m a) = INamedApp fc (updateApp n f) m a
    updateApp n f = IVar fc n

    unelabDef : (vs ** (Env Term vs, Term vs, Term vs)) ->
                Core ImpClause
    unelabDef (_ ** (env, lhs, rhs))
        = do lhs' <- unelabNoSugar env lhs
             defs <- get Ctxt
             rhsnf <- normaliseArgHoles defs env rhs
             rhs' <- unelabNoSugar env rhsnf
             pure (PatClause fc (map rawName lhs') (map rawName rhs'))

    showPat : ImpClause -> String
    showPat (PatClause _ lhs rhs) = show lhs ++ " = " ++ show rhs
    showPat _ = "Can't happen"

eraseInferred : {auto c : Ref Ctxt Defs} ->
                Term vars -> Core (Term vars)
eraseInferred (Bind fc x b tm)
    = do b' <- traverse eraseInferred b
         tm' <- eraseInferred tm
         pure (Bind fc x b' tm')
eraseInferred tm
    = case getFnArgs tm of
           (f, []) => pure f
           (Ref fc Func n, args) =>
                do defs <- get Ctxt
                   Just gdef <- lookupCtxtExact n (gamma defs)
                        | Nothing => pure tm
                   let argsE = NatSet.overwrite (Erased fc Placeholder) (inferrable gdef) args
                   argsE' <- traverse eraseInferred argsE
                   pure (apply fc (Ref fc Func n) argsE')
           -- (the arguments of another head, a constructor or a local
           -- variable, are left as they are, as they always were: they used
           -- to be traversed, and the result dropped.  Erasing in them too
           -- would change the arguments that the copies are made by, and
           -- elaborated with, everywhere.)
           _ => pure tm

-- The arguments that a function is specialised by, and whether that is
-- because of --spec-interfaces.
-- (Within a copy, `inCopy`, the methods of interfaces are not specialised:
-- they are reduced, see autoReducible, and a copy of a method would stop the
-- reduction there.)
specArgsOf : {auto c : Ref Ctxt Defs} ->
             {auto s : Ref Syn SyntaxInfo} ->
             (inCopy : Bool) -> FC -> Name -> GlobalDef -> Core (NatSet, Bool)
specArgsOf inCopy fc fn gdef
    = if not (NatSet.isEmpty (specArgs gdef))
         then pure (specArgs gdef, False)
         else do defs <- get Ctxt
                 if not (specInterfaces (session (options defs)))
                    then pure (NatSet.empty, False)
                    else do specs <- autoSpecArgs fc fn gdef
                            if inCopy && not (NatSet.isEmpty specs)
                                      && !(isMethod gdef)
                               then pure (NatSet.empty, True)
                               else pure (specs, True)
  where
    isMethod : GlobalDef -> Core Bool
    isMethod d
        = do let PMDef _ _ _ _ pats = definition d
               | _ => pure False
             let size = foldl (\k, (_ ** (_, _, rhs)) => k + termSize rhs) 0 pats
             fnfull <- toFullNames fn
             refs <- fullRefs d
             pure (size <= 10 && not (any (== fnfull) refs))

-- The name of the copy by these static arguments.  A copy is named by the
-- key of its arguments, in the namespace of the copies of the module that
-- makes it: `_PE.M.PE_f_key`, made in module M.  It is reused, by M and by
-- the modules that import M, for the arguments that it was made by only (its
-- SpecStatics); a copy of the key that was made by other arguments, which
-- has the same key, is not.
--  * The name of an existing copy by these arguments: one made by this
--    module, or by any module it imports, is found among the names of the
--    same root (`PE_f_key`) in a `_PE` namespace.
--  * Otherwise, the name of the key in the namespace of this module, unless
--    this module made a copy of that name by other arguments: then the name
--    of the next key.
-- The key is only 64 bits, so two modules that do not import each other
-- can make copies of the same key by different arguments; they used to have
-- the same name `_PE.PE_f_key`, and a module importing both saw only the
-- one it read first (Core.Binary.addGlobalDef does not replace a complete
-- definition), and used it for both.  In the namespaces of their modules,
-- they are two names, and each is called by the code made with it.  (Two
-- such modules that make a copy by the same arguments make two copies of
-- one root, then; a module importing both reuses one of them.)
-- A copy that was not used (see mkSpecDef) has no SpecStatics: it is never
-- reused by another module, and this module knows it from peFailures.
copyName : {auto c : Ref Ctxt Defs} ->
           Name -> List ClosedTerm -> Int -> Nat -> Core (Maybe Name)
copyName fnfull statics key k
    = do defs <- get Ctxt
         let root = Basic ("PE_" ++ nameRoot fnfull ++ "_" ++ asHex (cast key))
         let pename = NS (partialEvalNSOf (moduleNS defs)) (UN root)
         if isJust (lookup pename (peFailures defs)) then pure (Just pename) else do
           let others = maybe [] (mapMaybe copyOf) $
                          lookup root (possibles (gamma defs))
           Nothing <- findCopy defs others
             | Just found => pure (Just found)
           Just _ <- lookupCtxtExact pename (gamma defs)
             | Nothing => pure (Just pename)
           log "specialise" 3 $
             "The key of \{show pename} is that of other arguments"
           if k >= 8 then pure Nothing
              else copyName fnfull statics (mixKey key 1) (S k)
  where
    copyOf : PossibleName -> Maybe (Name, Int)
    copyOf (Direct n@(NS ns _) i) = if isPartialEvalNS ns then Just (n, i) else Nothing
    copyOf _ = Nothing

    findCopy : Defs -> List (Name, Int) -> Core (Maybe Name)
    findCopy defs [] = pure Nothing
    findCopy defs ((n, i) :: ns)
        = do Just d <- lookupCtxtExact (Resolved i) (gamma defs)
               | Nothing => findCopy defs ns
             if SpecStatics statics `elem` flags d
                then pure (Just n)
                else findCopy defs ns

-- Specialise a function name according to arguments. Return the specialised
-- application on success, or Nothing if it's not specialisable (due to static
-- arguments not being concrete)
specialise : {vars : _} ->
             (inCopy : Bool) -> (er : Bool) ->
             {auto c : Ref Ctxt Defs} ->
             {auto m : Ref MD Metadata} ->
             {auto u : Ref UST UState} ->
             {auto s : Ref Syn SyntaxInfo} ->
             {auto o : Ref ROpts REPLOpts} ->
             FC -> Env Term vars -> GlobalDef ->
             Name -> List (FC, Term vars) ->
             Core (Maybe (Term vars))
specialise {vars} inCopy er fc env gdef fn stk
    = do (specs, isAuto) <- specArgsOf inCopy fc fn gdef
         if NatSet.isEmpty specs || (isAuto && er)
            then pure Nothing
            else specialiseBy specs isAuto
  where
    concrete : {vars : _} ->
               Term vars -> Maybe ClosedTerm
    concrete tm = shrink tm none

    -- (An argument that --spec-interfaces would specialise by is at most
    -- autoSpecArgSize big, before and after its holes are normalised: in a
    -- proof, the types of the implementations can be huge, and normalising
    -- them at every application costs more than the copy can gain.)
    getSpecArgs : Bool -> Nat -> NatSet -> List (FC, Term vars) ->
                  Core (Maybe (List (Nat, ArgMode)))
    getSpecArgs isAuto i specs [] = pure (Just [])
    getSpecArgs isAuto i specs ((_, x) :: xs)
        = do Just xs' <- getSpecArgs isAuto (1 + i) specs xs
                 | Nothing => pure Nothing
             if i `elem` specs
                then do let True = small x
                              | False => tooBig x
                        defs <- get Ctxt
                        x' <- normaliseHoles defs env x
                        let True = small x'
                              | False => tooBig x'
                        x' <- eraseInferred x'
                        let Just xok = concrete x'
                            | Nothing => pure Nothing
                        pure $ Just ((i, Static xok) :: xs')
                else pure $ Just ((i, Dynamic) :: xs')
      where
        small : Term vars -> Bool
        small tm = not isAuto || termSize tm <= autoSpecArgSize

        tooBig : Term vars -> Core (Maybe a)
        tooBig tm
            = do log "specialise.auto" 20 $
                   "Not specialising \{show !(toFullNames fn)}: argument \{show i} has size \{show (termSize tm)}"
                 pure Nothing

    specialiseBy : NatSet -> Bool -> Core (Maybe (Term vars))
    specialiseBy specs isAuto = do
        fnfull <- toFullNames fn
        -- If all the arguments are concrete (meaning, no local variables
        -- or holes in them, so they can be a ClosedTerm) we can specialise
        Just sargs <- getSpecArgs isAuto 0 specs stk
            | Nothing => pure Nothing
        defs <- get Ctxt
        -- (The implementations of interfaces that --spec-interfaces
        -- specialises by are kept as they are, references to them in
        -- practice: the normal form of an implementation whose methods use
        -- implementations of the same type can be infinite, see
        -- autoReducible.)
        sargs <- if isAuto then pure sargs
                    else for sargs $ traversePair $ traverseArgMode $ \ tm =>
                           normalise defs Env.empty tm
        statics <- traverse toFullNames $ mapMaybe getStatic $ map snd sargs
        -- (the function name is in the key too, to avoid namespace clashes;
        -- --debug-spec-collide leaves out the arguments, to test copyName)
        let fnkey = keyName 0x5bd1e995 fnfull
        let key = if defs.options.session.debugSpecCollide
                     then fnkey
                     else foldl keyTerm fnkey statics
        Just pename <- copyName fnfull statics key 0
          | Nothing => pure Nothing
        defs <- get Ctxt
        case lookup pename (peFailures defs) of
             Nothing =>
               do -- (a new copy made because of --spec-interfaces counts
                  -- towards the limit of the module)
                  new <- isNothing <$> lookupCtxtExact pename (gamma defs)
                  -- (nor is one made in too many copies of the function,
                  -- or of any, one in another: polymorphic recursion, as in
                  -- a finger tree, would make a copy for every depth of the
                  -- type, up to the limit of the module)
                  let stack = autoSpecStack defs
                  if isAuto && new && autoSpecCount defs >= autoSpecLimit
                     then pure Nothing
                     else if isAuto && new
                             && (count (== fnfull) stack >= autoSpecRepeat
                                 || length stack >= autoSpecMaxDepth)
                     then do log "specialise.auto" 10 $
                               "Not specialising \{show fnfull}: \{show (length stack)} copies are being made, one in another, \{show (count (== fnfull) stack)} of it"
                             pure Nothing
                     else do
                       when (isAuto && new) $ update Ctxt { autoSpecCount $= S }
                       Just <$> mkSpecDef fc gdef isAuto pename statics sargs fn stk
             Just _ => pure Nothing

-- The positions of the arguments of quantity 0 in a type of a function or a
-- constructor: they are erased at run time.
erasedPositions : Term vs -> NatSet
erasedPositions = go 0
  where
    go : Nat -> Term vs' -> NatSet
    go i (Bind _ _ (Pi _ rig _ _) sc)
        = let rest = go (S i) sc in
              if isErased rig then insert i rest else rest
    go i _ = NatSet.empty

-- Which arguments of an application of this head are erased at run time:
-- the arguments of quantity 0 of a function or a constructor, and all the
-- arguments of a type constructor.
erasedArgsOf : {auto c : Ref Ctxt Defs} -> Term vars -> Core (Nat -> Bool)
erasedArgsOf (Ref _ (TyCon _) _) = pure (const True)
erasedArgsOf (Ref _ Bound _) = pure (const False)
erasedArgsOf (Ref _ _ n)
    = do defs <- get Ctxt
         Just gdef <- lookupCtxtExact n (gamma defs)
           | Nothing => pure (const False)
         let es = erasedPositions (type gdef)
         pure (\i => i `elem` es)
erasedArgsOf _ = pure (const False)

-- (`er`: the term is erased at run time, it is a type or an argument of
-- quantity 0.  A copy made by --spec-interfaces would gain nothing there,
-- so none is made; the copies of `%spec` functions are made everywhere.)
findSpecs : {vars : _} ->
            {auto c : Ref Ctxt Defs} ->
            {auto m : Ref MD Metadata} ->
            {auto u : Ref UST UState} ->
            {auto s : Ref Syn SyntaxInfo} ->
            {auto o : Ref ROpts REPLOpts} ->
            Env Term vars -> (er : Bool) -> List (FC, Term vars) -> Term vars ->
            Core (Term vars)
findSpecs env er stk (Ref fc Func fn)
    = do defs <- get Ctxt
         Just gdef <- lookupCtxtExact fn (gamma defs)
              | Nothing => pure (applyStackWithFC (Ref fc Func fn) stk)
         Just r <- specialise False er fc env gdef fn stk
              | Nothing => pure (applyStackWithFC (Ref fc Func fn) stk)
         pure r
findSpecs env er stk (Meta fc n i args)
    = do args' <- traverse (findSpecs env er []) args
         pure $ applyStackWithFC (Meta fc n i args') stk
findSpecs env er stk (Bind fc x b sc)
    = do b' <- case b of
                    Let bfc r val ty =>
                      pure $ Let bfc r !(findSpecs env er [] val)
                                       !(findSpecs env True [] ty)
                    _ => traverse (findSpecs env True []) b
         sc' <- findSpecs (b' :: env) (er || isPi b) [] sc
         pure $ applyStackWithFC (Bind fc x b' sc') stk
  where
    isPi : Binder (Term vars) -> Bool
    isPi (Pi {}) = True
    isPi _ = False
findSpecs env er stk tm@(App {})
    = do let (f, args) = spine tm []
         erasedAt <- erasedArgsOf f
         args' <- goArgs erasedAt 0 args
         findSpecs env er (args' ++ stk) f
  where
    spine : Term vars -> List (FC, Term vars) -> (Term vars, List (FC, Term vars))
    spine (App afc f a) acc = spine f ((afc, a) :: acc)
    spine f acc = (f, acc)

    goArgs : (Nat -> Bool) -> Nat -> List (FC, Term vars) ->
             Core (List (FC, Term vars))
    goArgs erasedAt i [] = pure []
    goArgs erasedAt i ((afc, a) :: as)
        = do a' <- findSpecs env (er || erasedAt i) [] a
             pure ((afc, a') :: !(goArgs erasedAt (S i) as))
findSpecs env er stk (TDelayed fc r tm)
    = do tm' <- findSpecs env True [] tm
         pure $ applyStackWithFC (TDelayed fc r tm') stk
findSpecs env er stk (TDelay fc r ty tm)
    = do ty' <- findSpecs env True [] ty
         tm' <- findSpecs env er [] tm
         pure $ applyStackWithFC (TDelay fc r ty' tm') stk
findSpecs env er stk (TForce fc r tm)
    = do tm' <- findSpecs env er [] tm
         pure $ applyStackWithFC (TForce fc r tm') stk
findSpecs env er stk tm = pure $ applyStackWithFC tm stk

bName : {auto q : Ref QVar Int} -> String -> Core Name
bName n
    = do i <- get QVar
         put QVar (i + 1)
         pure (MN n i)

-- This is like 'quote' in 'Normalise', except that when we encounter a
-- function name we need to check whether to specialise.
-- (Sorry about all the repetition - I don't really want to export those
-- internal details, and there is a small but crucial change where we call
-- quoteHead as compared with the version in Core.Normalise, to deal with
-- checking for specialised applications.)
mutual
  quoteArgs : {bound, free : _} ->
              {auto c : Ref Ctxt Defs} ->
              {auto m : Ref MD Metadata} ->
              {auto u : Ref UST UState} ->
              {auto s : Ref Syn SyntaxInfo} ->
              {auto o : Ref ROpts REPLOpts} ->
              Ref QVar Int -> Defs -> Bounds bound ->
              Env Term free -> List (Closure free) ->
              Core (List (Term (bound ++ free)))
  quoteArgs q defs bounds env [] = pure []
  quoteArgs q defs bounds env (a :: args)
      = pure $ (!(quoteGenNF q defs bounds env !(evalClosure defs a)) ::
                !(quoteArgs q defs bounds env args))

  quoteArgsWithFC : {auto c : Ref Ctxt Defs} ->
                    {auto m : Ref MD Metadata} ->
                    {auto u : Ref UST UState} ->
                    {auto s : Ref Syn SyntaxInfo} ->
                    {auto o : Ref ROpts REPLOpts} ->
                    {bound, free : _} ->
                    Ref QVar Int -> Defs -> Bounds bound ->
                    Env Term free -> List (FC, Closure free) ->
                    Core (List (FC, Term (bound ++ free)))
  quoteArgsWithFC q defs bounds env terms
      = pure $ zip (map fst terms) !(quoteArgs q defs bounds env (map snd terms))

  quoteHead : {bound, free : _} ->
              {auto c : Ref Ctxt Defs} ->
              {auto m : Ref MD Metadata} ->
              {auto u : Ref UST UState} ->
              {auto s : Ref Syn SyntaxInfo} ->
              {auto o : Ref ROpts REPLOpts} ->
              Ref QVar Int -> Defs ->
              FC -> Bounds bound -> Env Term free -> NHead free ->
              Core (Term (bound ++ free))
  quoteHead {bound} q defs fc bounds env (NLocal mrig _ prf)
      = let MkVar prf' = addLater bound prf in
            pure $ Local fc mrig _ prf'
    where
      addLater : {idx : _} -> (ys : List Name) -> (0 p : IsVar n idx xs) ->
                 Var (ys ++ xs)
      addLater [] isv = MkVar isv
      addLater (x :: xs) isv
          = let MkVar isv' = addLater xs isv in
                MkVar (Later isv')
  quoteHead q defs fc bounds env (NRef Bound (MN n i))
      = case findName bounds of
             Just (MkVar p) => pure $ Local fc Nothing _ (embedIsVar p)
             Nothing => pure $ Ref fc Bound (MN n i)
    where
      findName : Bounds bound' -> Maybe (Var bound')
      findName None = Nothing
      findName (Add x (MN n' i') ns)
          = if i == i' -- this uniquely identifies it, given how we
                       -- generated the names, and is a faster test!
               then Just first
               else do MkVar p <-findName ns
                       Just (MkVar (Later p))
      findName (Add x _ ns)
          = do MkVar p <-findName ns
               Just (MkVar (Later p))
  quoteHead q defs fc bounds env (NRef nt n) = pure $ Ref fc nt n
  quoteHead q defs fc bounds env (NMeta n i args)
      = do args' <- quoteArgs q defs bounds env args
           pure $ Meta fc n i args'

  quotePi : {bound, free : _} ->
            {auto c : Ref Ctxt Defs} ->
            {auto m : Ref MD Metadata} ->
            {auto u : Ref UST UState} ->
            {auto s : Ref Syn SyntaxInfo} ->
            {auto o : Ref ROpts REPLOpts} ->
            Ref QVar Int -> Defs -> Bounds bound ->
            Env Term free -> PiInfo (Closure free) ->
            Core (PiInfo (Term (bound ++ free)))
  quotePi q defs bounds env Explicit = pure Explicit
  quotePi q defs bounds env Implicit = pure Implicit
  quotePi q defs bounds env AutoImplicit = pure AutoImplicit
  quotePi q defs bounds env (DefImplicit t)
      = do t' <- quoteGenNF q defs bounds env !(evalClosure defs t)
           pure (DefImplicit t')

  quoteBinder : {bound, free : _} ->
                {auto c : Ref Ctxt Defs} ->
                {auto m : Ref MD Metadata} ->
                {auto u : Ref UST UState} ->
                {auto s : Ref Syn SyntaxInfo} ->
                {auto o : Ref ROpts REPLOpts} ->
                Ref QVar Int -> Defs -> Bounds bound ->
                Env Term free -> Binder (Closure free) ->
                Core (Binder (Term (bound ++ free)))
  quoteBinder q defs bounds env (Lam fc r p ty)
      = do ty' <- quoteGenNF q defs bounds env !(evalClosure defs ty)
           p' <- quotePi q defs bounds env p
           pure (Lam fc r p' ty')
  quoteBinder q defs bounds env (Let fc r val ty)
      = do val' <- quoteGenNF q defs bounds env !(evalClosure defs val)
           ty' <- quoteGenNF q defs bounds env !(evalClosure defs ty)
           pure (Let fc r val' ty')
  quoteBinder q defs bounds env (Pi fc r p ty)
      = do ty' <- quoteGenNF q defs bounds env !(evalClosure defs ty)
           p' <- quotePi q defs bounds env p
           pure (Pi fc r p' ty')
  quoteBinder q defs bounds env (PVar fc r p ty)
      = do ty' <- quoteGenNF q defs bounds env !(evalClosure defs ty)
           p' <- quotePi q defs bounds env p
           pure (PVar fc r p' ty')
  quoteBinder q defs bounds env (PLet fc r val ty)
      = do val' <- quoteGenNF q defs bounds env !(evalClosure defs val)
           ty' <- quoteGenNF q defs bounds env !(evalClosure defs ty)
           pure (PLet fc r val' ty')
  quoteBinder q defs bounds env (PVTy fc r ty)
      = do ty' <- quoteGenNF q defs bounds env !(evalClosure defs ty)
           pure (PVTy fc r ty')

  quoteGenNF : {bound, vars : _} ->
               {auto c : Ref Ctxt Defs} ->
               {auto m : Ref MD Metadata} ->
               {auto u : Ref UST UState} ->
               {auto s : Ref Syn SyntaxInfo} ->
               {auto o : Ref ROpts REPLOpts} ->
               Ref QVar Int ->
               Defs -> Bounds bound ->
               Env Term vars -> NF vars -> Core (Term (bound ++ vars))
  quoteGenNF q defs bound env (NBind fc n b sc)
      = do var <- bName "qv"
           sc' <- quoteGenNF q defs (Add n var bound) env
                       !(sc defs (toClosure defaultOpts env (Ref fc Bound var)))
           b' <- quoteBinder q defs bound env b
           pure (Bind fc n b' sc')
  -- IMPORTANT CASE HERE
  -- If fn is to be specialised, quote the args directly (no further
  -- reduction) then call specialise. Otherwise, quote as normal
  quoteGenNF q defs bound env (NApp fc (NRef Func fn) args)
      = do Just gdef <- lookupCtxtExact fn (gamma defs)
                | Nothing => do args' <- quoteArgsWithFC q defs bound env args
                                pure $ applyStackWithFC (Ref fc Func fn) args'
           args' <- quoteArgsWithFC q defs bound env args
           (specs, isAuto) <- specArgsOf True fc fn gdef
           let False = NatSet.isEmpty specs
               | _ => pure $ applyStackWithFC (Ref fc Func fn) args'
           -- The implementations that --spec-interfaces specialises by are
           -- taken as they are given, not reduced (if they do not need to
           -- be reduced to be closed): they are not normalised either (see
           -- specialise), and in a copy, which reduces the implementations
           -- it is given once, a recursive call would take its
           -- implementation reduced a bit more than the copy did, and so
           -- make another copy, and so on, until the implementation does
           -- not reduce any more (four copies of `toTree` of the treeInt
           -- benchmark, one in another, by `Ord Int`).  Given as they
           -- are, they are the same as in the call that made the copy, so
           -- the recursive call is to the copy.
           stk <- if not isAuto then pure args' else
                    do empty <- clearDefs defs
                       staticAsGiven empty bound specs 0 args args'
           Just r <- specialise True False fc (extendEnv bound env) gdef fn stk
                | Nothing =>
                     -- can't specialise, keep the arguments
                     -- unreduced
                     do empty <- clearDefs defs
                        args' <- quoteArgsWithFC q empty bound env args
                        pure $ applyStackWithFC (Ref fc Func fn) args'
           pure r
     where
       staticAsGiven : {bs : _} ->
                       Defs -> Bounds bs -> NatSet -> Nat ->
                       List (FC, Closure vars) ->
                       List (FC, Term (bs ++ vars)) ->
                       Core (List (FC, Term (bs ++ vars)))
       staticAsGiven empty bnds specs i ((_, c) :: cs) (a :: as)
           = do rest <- staticAsGiven empty bnds specs (S i) cs as
                if not (i `elem` specs) then pure (a :: rest) else do
                  given <- quoteGenNF q empty bnds env !(evalClosure empty c)
                  pure $ if isJust (shrink given none)
                            then (fst a, given) :: rest
                            else a :: rest
       staticAsGiven _ _ _ _ _ as = pure as

       extendEnv : Bounds bs -> Env Term vs -> Env Term (bs ++ vs)
       extendEnv None env = env
       extendEnv (Add x n bs) env
           -- We're just using this to evaluate holes in the right scope, so
           -- a placeholder binder is fine
           = Lam fc top Explicit (Erased fc Placeholder) :: extendEnv bs env
  quoteGenNF q defs bound env (NApp fc f args)
      = do f' <- quoteHead q defs fc bound env f
           args' <- quoteArgsWithFC q defs bound env args
           pure $ applyStackWithFC f' args'
  quoteGenNF q defs bound env (NDCon fc n t ar args)
      = do args' <- quoteArgsWithFC q defs bound env args
           pure $ applyStackWithFC (Ref fc (DataCon t ar) n) args'
  quoteGenNF q defs bound env (NTCon fc n ar args)
      = do args' <- quoteArgsWithFC q defs bound env args
           pure $ applyStackWithFC (Ref fc (TyCon ar) n) args'
  quoteGenNF q defs bound env (NAs fc s n pat)
      = do n' <- quoteGenNF q defs bound env n
           pat' <- quoteGenNF q defs bound env pat
           pure (As fc s n' pat')
  quoteGenNF q defs bound env (NDelayed fc r arg)
      = do argQ <- quoteGenNF q defs bound env arg
           pure (TDelayed fc r argQ)
  quoteGenNF q defs bound env (NDelay fc r ty arg)
      -- unlike main evaluator, we want to look under Delays
      = do argNF <- evalClosure defs arg
           argQ <- quoteGenNF q defs bound env argNF
           tyNF <- evalClosure defs ty
           tyQ <- quoteGenNF q defs bound env tyNF
           pure (TDelay fc r tyQ argQ)
    where
      toHolesOnly : Closure vs -> Closure vs
      toHolesOnly (MkClosure _ locs env tm)
          = MkClosure withHoles locs env tm
      toHolesOnly c = c
  quoteGenNF q defs bound env (NForce fc r arg args)
      = do args' <- quoteArgsWithFC q defs bound env args
           case arg of
                NDelay fc _ _ arg =>
                   do argNF <- evalClosure defs arg
                      pure $ applyStackWithFC !(quoteGenNF q defs bound env argNF) args'
                _ => do arg' <- quoteGenNF q defs bound env arg
                        pure $ applyStackWithFC (TForce fc r arg') args'
  quoteGenNF q defs bound env (NPrimVal fc c) = pure $ PrimVal fc c
  quoteGenNF q defs bound env (NErased fc Impossible) = pure $ Erased fc Impossible
  quoteGenNF q defs bound env (NErased fc Placeholder) = pure $ Erased fc Placeholder
  quoteGenNF q defs bound env (NErased fc (Dotted t))
    = pure $ Erased fc $ Dotted !(quoteGenNF q defs bound env t)
  quoteGenNF q defs bound env (NType fc u) = pure $ TType fc u

evalRHS : {vars : _} ->
          {auto c : Ref Ctxt Defs} ->
          {auto m : Ref MD Metadata} ->
          {auto u : Ref UST UState} ->
          {auto s : Ref Syn SyntaxInfo} ->
          {auto o : Ref ROpts REPLOpts} ->
          Env Term vars -> NF vars -> Core (Term vars)
evalRHS env nf
    = do q <- newRef QVar 0
         defs <- get Ctxt
         quoteGenNF q defs None env nf

export
applySpecialise : {vars : _} ->
                  {auto c : Ref Ctxt Defs} ->
                  {auto m : Ref MD Metadata} ->
                  {auto u : Ref UST UState} ->
                  {auto s : Ref Syn SyntaxInfo} ->
                  {auto o : Ref ROpts REPLOpts} ->
                  Env Term vars ->
                  Maybe (List (Name, Nat)) ->
                        -- ^ If we're specialising, names to reduce in the RHS
                        -- with their reduction limits
                  Term vars -> -- initial RHS
                  Core (Term vars)
applySpecialise env Nothing tm
    = findSpecs env False [] tm -- not specialising, just search through RHS
applySpecialise env (Just ls) tmin -- specialising, evaluate RHS while looking
                                 -- for names to specialise
    = do defs <- get Ctxt
         tm <- toResolvedNames tmin
         -- In a copy made by --spec-interfaces, the names are only reduced
         -- as many times as `ls` says along a path (see mkSpecDef), and the
         -- names that it does not list are not reduced, so that recursive
         -- definitions, and infinite structures under delays (which
         -- quoteGenNF looks under), are not unfolded forever.  (The copies
         -- of `%spec` functions reduce everything, as they always did: a
         -- `%spec` function that builds an infinite structure does not
         -- terminate.)
         ls <- if fst autoLimits `elem` map fst ls
                  then traverse (\(n, k) => pure (!(toResolvedNames n), k)) ls
                  else pure []
         nf <- nfOpts ({ reduceLimit := ls } defaultOpts) defs env tm
         tm' <- evalRHS env nf
         -- A copy made by --spec-interfaces that grows too big when it is
         -- reduced is not used (the error makes mkSpecDef fall back to the
         -- function): it would cost more to compile, and to store, than it
         -- gains at run time.
         when (not (null ls)) $
           do let size = termSize tm'
              log "specialise.auto" 15 $
                "Size of a clause of a copy after reduction: \{show size}"
              when (size > autoSpecReduced) $
                throw (GenericMsg emptyFC
                         "A clause of the copy is too big after reduction (\{show size})")
         tmfull <- toFullNames tm'
         logTermNF "specialise" 5 ("New RHS") env tmfull
         pure tmfull
