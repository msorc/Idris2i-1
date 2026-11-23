module Core.AutoSearch

import Core.Context.Log
import Core.Env
import Core.Normalise
import Core.Unify
import Core.UniverseCheck
import Core.Value

import Data.Either
import Data.Maybe

import Libraries.Data.NatSet
import Libraries.Data.List.SizeOf
import Libraries.Data.WithDefault

%default covering

tryUnifyUnambig' : {auto c : Ref Ctxt Defs} ->
                   {auto u : Ref UST UState} ->
                   {default False preferLeftError : Bool} ->
                   Core a -> (Error -> Core a) -> Core a
tryUnifyUnambig' left right = handleUnify left $ \case
  e@(AmbiguousSearch {}) => throw e
  e                      => if preferLeftError
                              then tryUnify (right e) (throw e)
                              else right e

tryUnifyUnambig : {auto c : Ref Ctxt Defs} ->
                  {auto u : Ref UST UState} ->
                  {default False preferLeftError : Bool} ->
                  Core a -> Core a -> Core a
tryUnifyUnambig left right = tryUnifyUnambig' {preferLeftError} left $ const right

tryNoDefaultsFirst : {auto c : Ref Ctxt Defs} ->
                     {auto u : Ref UST UState} ->
                     (Bool -> Core a) -> Core a
tryNoDefaultsFirst f = tryUnifyUnambig {preferLeftError=True} (f False) (f True)

-- The head of a type (or of an argument of a type constructor) when it is
-- known whatever its metavariables and bound variables stand for. Unifying
-- two terms whose rigid heads clash always fails, so a candidate whose type
-- clashes with the goal can be rejected without creating metavariables for
-- its arguments and running the unifier. This must stay conservative: a
-- clash is only reported where the unifier would fail.
public export
data RigidHead = RTCon Name | RDCon Int | RPrim Constant | RType

-- Whether unification of two terms with these heads certainly fails: type
-- constructors are compared by name, data constructors by tag, and
-- constants by value, as the unifier does (all types unify with each other)
export
clash : RigidHead -> RigidHead -> Bool
clash (RTCon x) (RTCon y) = x /= y
clash (RDCon x) (RDCon y) = x /= y
clash (RPrim x) (RPrim y) = x /= y
clash RType RType = False
clash _ _ = True

clashM : Maybe RigidHead -> Maybe RigidHead -> Bool
clashM (Just x) (Just y) = clash x y
clashM _ _ = False

-- The rigid head of a term, as the evaluator would produce it (see 'ntCon'),
-- if it has one whatever the variables in it stand for
export
termHead : Term vs -> Maybe RigidHead
termHead tm
    = case getFnArgs tm of
           (Ref _ (TyCon ar _) n, as) => Just (tconHead n ar as)
           (Ref _ (DataCon t _) _, _) => Just (RDCon t)
           (PrimVal _ c, []) => Just (RPrim c)
           (TType {}, []) => Just RType
           _ => Nothing
  where
    tconHead : Name -> Nat -> List (Term vs) -> RigidHead
    tconHead (UN (Basic "Type")) Z [] = RType
    tconHead n Z [] = maybe (RTCon n) (RPrim . PrT) (isConstantType n)
    tconHead n _ _ = RTCon n

nfHead : NF vs -> Maybe RigidHead
nfHead (NTCon _ n _ _ _) = Just (RTCon n)
nfHead (NDCon _ _ t _ _) = Just (RDCon t)
nfHead (NPrimVal _ c) = Just (RPrim c)
nfHead (NType {}) = Just RType
nfHead _ = Nothing

-- The rigid head of an argument, found by evaluating only the solutions of
-- metavariables in it: a rigid head stays when the rest is evaluated, and
-- evaluating an argument fully here would duplicate work of the unifier,
-- which can be large (a type computed by a function).
closureHead : {vars : _} ->
              {auto c : Ref Ctxt Defs} ->
              Defs -> Closure vars -> Core (Maybe RigidHead)
closureHead defs c = nfHead <$> evalClosureWithOpts defs withHoles c

-- A goal which is a type constructor applied to arguments, with the rigid
-- heads of those arguments
public export
TargetHeads : Type
TargetHeads = (Name, List (Maybe RigidHead))

-- (If evaluating an argument fails, nothing is rejected, and the error
-- happens where it happened before, when a candidate is unified.)
export
targetHeads : {vars : _} ->
              {auto c : Ref Ctxt Defs} ->
              NF vars -> Core (Maybe TargetHeads)
targetHeads (NTCon _ n _ _ args)
    = do defs <- get Ctxt
         catch (do hs <- traverse (closureHead defs) (map snd args)
                   pure (Just (n, hs)))
               (\ _ => pure Nothing)
targetHeads _ = pure Nothing

-- Whether the type of a global hint can match the goal: False only if
-- unifying the goal with the type's return type (its Pi bound variables made
-- metavariables, as in 'mkArgs') certainly fails
export
hintCanMatch : TargetHeads -> Term vs -> Bool
hintCanMatch th (Bind _ _ (Pi {}) sc) = hintCanMatch th sc
hintCanMatch (tyn, ths) ty
    = case termHead ty of
           Nothing => True
           Just h =>
             not (clash (RTCon tyn) h) &&
               (let as = snd (getFnArgs ty) in
                    length as /= length ths ||
                      all (\ (a, th) => not (clashM (termHead a) th)) (zip as ths))

-- The same for the type of a local variable, which is a normal form. Its Pi
-- bound variables are instantiated with placeholders, which the evaluator
-- treats as it treats unsolved metavariables (it gets stuck on them).
localCanMatch : {vars : _} ->
                {auto c : Ref Ctxt Defs} ->
                Env Term vars -> TargetHeads -> NF vars -> Core Bool
localCanMatch env th ty = catch (canMatch ty) (\ _ => pure True)
  where
    rigidMatch : TargetHeads -> NF vars -> Core Bool
    rigidMatch (tyn, ths) ty
        = case nfHead ty of
               Nothing => pure True
               Just h =>
                 if clash (RTCon tyn) h then pure False
                    else case ty of
                           NTCon _ _ _ _ args =>
                             if length args /= length ths
                                then pure True
                                else do defs <- get Ctxt
                                        as <- traverse (closureHead defs) (map snd args)
                                        pure (all (\ (a, t) => not (clashM a t)) (zip as ths))
                           _ => pure True

    canMatch : NF vars -> Core Bool
    canMatch (NBind fc _ (Pi {}) sc)
        = do defs <- get Ctxt
             canMatch !(sc defs (toClosure defaultOpts env (Erased fc Placeholder)))
    canMatch ty = rigidMatch th ty

-- The same for the type of a local variable, as a term, before it is
-- evaluated: a local whose type is a pair is kept, since its projections are
-- tried too (see 'findPos').
retTyHead : Term vs -> Maybe RigidHead
retTyHead (Bind _ _ (Pi {}) sc) = retTyHead sc
retTyHead tm = termHead tm

localTypeCanMatch : {auto c : Ref Ctxt Defs} ->
                    TargetHeads -> Term vars -> Core Bool
localTypeCanMatch th ty
    = if hintCanMatch th ty
         then pure True
         else case retTyHead ty of
                   Just (RTCon n) => isPairType n
                   _ => pure False

-- Drop the candidates that 'keep' rejects from a list for 'anyOne', except
-- the last one: a candidate which fails without recording a sub-goal (as a
-- rejected one does) changes nothing in 'anyOne', unless it is the last one,
-- whose failure is reported.
dropRejectedInit : (a -> Bool) -> List a -> List a
dropRejectedInit keep [] = []
dropRejectedInit keep [x] = [x]
dropRejectedInit keep (x :: xs)
    = if keep x then x :: dropRejectedInit keep xs else dropRejectedInit keep xs

SearchEnv : Scoped
SearchEnv vars = List (NF vars, Closure vars)

-- A failed search records, as its cause, the chain of sub-goals that could
-- not be solved after a candidate's type had already matched the goal, each
-- with the candidate that needed it (`SearchNeeds`). This lets us report e.g.
-- that `Show (List Foo)` failed because the implementation for lists needs
-- `Show Foo`. The chain is only built as a failure propagates, so a search
-- that succeeds does not pay for it.
hasSubgoalCause : Error -> Bool
hasSubgoalCause (CantSolveGoal _ _ _ _ (Just (SearchNeeds {}))) = True
hasSubgoalCause _ = False

-- Keep the first error, unless it is a plain search failure and the second
-- one says which sub-goal failed. Any other error (e.g. an ambiguous search)
-- is more informative, so we keep it.
preferSubgoalCause : Error -> Error -> Error
preferSubgoalCause e1@(CantSolveGoal _ _ _ _ Nothing) e2
    = if hasSubgoalCause e2 then e2 else e1
preferSubgoalCause e1 _ = e1

-- Rethrow a failure as a failure of the goal 'top', keeping any recorded
-- sub-goal cause
failWithCause : {auto c : Ref Ctxt Defs} ->
                FC -> (topTy : ClosedTerm) -> List Error -> Core a
failWithCause fc top errs
    = do defs <- get Ctxt
         throw (CantSolveGoal fc (gamma defs) Env.empty top (findCause errs))
  where
    findCause : List Error -> Maybe Error
    findCause [] = Nothing
    findCause (CantSolveGoal _ _ _ _ (Just cause@(SearchNeeds {})) :: _)
        = Just cause
    findCause (_ :: es) = findCause es

-- The candidate whose arguments are searched for: a global hint, or a local
-- variable (whose name is only looked up if the search fails)
data Candidate : Scoped where
  GlobalCand : Name -> Candidate vars
  LocalCand : Term vars -> Candidate vars

candidateName : {vars : _} -> Candidate vars -> (Name, Bool)
candidateName (GlobalCand n) = (n, False)
candidateName (LocalCand (Local _ _ _ p)) = (nameAt p, True)
candidateName (LocalCand _) = (UN (Basic "local"), True)

searchType : {vars : _} ->
             {auto c : Ref Ctxt Defs} ->
             {auto u : Ref UST UState} ->
             FC -> RigCount ->
             (defaults : Bool) -> (trying : List (Term vars)) ->
             (depth : Nat) ->
             (defining : Name) ->
             (checkDets : Bool) -> (topTy : ClosedTerm) ->
             Env Term vars -> (target : Term vars) -> Core (Term vars)

public export
record ArgInfo (vars : Scope) where
  constructor MkArgInfo
  holeID : Int
  argRig : RigCount
  plicit : PiInfo (Closure vars)
  metaApp : Term vars
  argType : Term vars

export
mkArgs : {vars : _} ->
         {auto c : Ref Ctxt Defs} ->
         {auto u : Ref UST UState} ->
         FC -> RigCount ->
         Env Term vars -> NF vars ->
         Core (List (ArgInfo vars), NF vars)
mkArgs fc rigc env (NBind nfc x (Pi fc' c p ty) sc)
    = do defs <- get Ctxt
         empty <- clearDefs defs
         nm <- genName "sa"
         argTy <- quote empty env ty
         let argRig = rigMult rigc c
         (idx, arg) <- newMeta fc' argRig env nm argTy
                               (Hole (length env) (holeInit False)) False
         setInvertible fc (Resolved idx)
         (rest, restTy) <- mkArgs fc rigc env
                              !(sc defs (toClosure defaultOpts env arg))
         pure (MkArgInfo idx argRig p arg argTy :: rest, restTy)
mkArgs fc rigc env ty = pure ([], ty)

export
impLast : List (ArgInfo vars) -> List (ArgInfo vars)
impLast xs = filter (not . impl) xs ++ filter impl xs
  where
      impl : ArgInfo vs -> Bool
      impl inf
          = case plicit inf of
                 Explicit => False
                 _ => True

-- Whether the cause of a failed search is one a candidate's need is added to
isSubgoalCause : Maybe Error -> Bool
isSubgoalCause Nothing = True
isSubgoalCause (Just (SearchNeeds {})) = True
isSubgoalCause _ = False

searchIfHole : {vars : _} ->
               {auto c : Ref Ctxt Defs} ->
               {auto u : Ref UST UState} ->
               FC ->
               (defaults : Bool) -> List (Term vars) ->
               (ispair : Bool) -> (depth : Nat) ->
               (defining : Name) -> (topTy : ClosedTerm) -> Env Term vars ->
               Candidate vars -> (arg : ArgInfo vars) ->
               Core ()
searchIfHole fc defaults trying ispair Z def top env cand arg
    = throw (CantSolveGoal fc (gamma !(get Ctxt)) Env.empty top Nothing) -- possibly should say depth limit hit?
searchIfHole fc defaults trying ispair (S depth) def top env cand arg
    = do let hole = holeID arg
         let rig = argRig arg

         defs <- get Ctxt
         Just gdef <- lookupCtxtExact (Resolved hole) (gamma defs)
              | Nothing => throw (CantSolveGoal fc (gamma !(get Ctxt)) Env.empty top Nothing)
         let Hole _ _ = definition gdef
              | _ => pure () -- already solved
         top' <- if ispair
                    then normaliseScope defs Env.empty (type gdef)
                    else pure top

         argTy <- normaliseScope defs env (argType arg)
         argdef <- catch (searchType fc rig defaults trying depth def False top' env argTy)
                         (\case
                            CantSolveGoal efc egam eenv eg cause =>
                              if isSubgoalCause cause
                                 then do -- The candidate needed this argument.
                                         -- Normalise it now, while any holes
                                         -- it mentions are still solved
                                         defs' <- get Ctxt
                                         argTy' <- normaliseHoles defs' env argTy
                                         let (cn, loc) = candidateName cand
                                         throw (CantSolveGoal efc egam eenv eg
                                                  (Just (SearchNeeds fc (gamma defs') cn loc env argTy' cause)))
                                 else throw (CantSolveGoal efc egam eenv eg cause)
                            err => throw err)
         logTermNF "auto" 5 "Solved arg" env argdef
         logTermNF "auto" 5 "Arg meta" env (metaApp arg)
         ok <- solveIfUndefined env (metaApp arg) argdef
         if ok
            then pure ()
            else do vs <- unify inTerm fc env (metaApp arg) argdef
                    let [] = constraints vs
                        | _ => throw (CantSolveGoal fc (gamma defs) Env.empty top Nothing)
                    pure ()

successful : {vars : _} ->
             {auto c : Ref Ctxt Defs} ->
             {auto u : Ref UST UState} ->
             List (Core (Term vars)) ->
             Core (List (Either Error (Term vars, Defs, UState)))
successful [] = pure []
successful (elab :: elabs)
    = do ust <- get UST
         defs <- branch
         catch (do -- Run the elaborator
                   res <- elab
                   -- Record post-elaborator state
                   ust' <- get UST
                   defs' <- get Ctxt
                   -- Reset to previous state and try the rest
                   put UST ust
                   put Ctxt defs
                   elabs' <- successful elabs
                   -- Record success, and the state we ended at
                   pure (Right (res, defs', ust') :: elabs'))
               (\err => do put UST ust
                           put Ctxt defs
                           elabs' <- successful elabs
                           pure (Left err :: elabs'))

anyOne : {auto c : Ref Ctxt Defs} ->
         {auto u : Ref UST UState} ->
         FC -> Env Term vars -> (topTy : ClosedTerm) ->
         List (Core (Term vars)) ->
         Core (Term vars)
anyOne fc env top [] = throw (CantSolveGoal fc (gamma !(get Ctxt)) Env.empty top Nothing)
anyOne fc env top [elab]
    = catch elab $
         \case
           err@(CantSolveGoal {})   => throw err
           err@(AmbiguousSearch {}) => throw err
           _ => throw $ CantSolveGoal fc (gamma !(get Ctxt)) Env.empty top Nothing
anyOne fc env top (elab :: elabs)
    = handleUnify elab $ \err =>
        handleUnify (anyOne fc env top elabs) $ \err' =>
          throw (preferSubgoalCause err' err)

-- Run all the candidates, and keep the only one that succeeds. A goal with a
-- single candidate is handled by 'exactlyOne', which reports its failure
-- differently, so this is also what a goal with several candidates (some
-- of which were dropped early) must use, however many are left.
exactlyOneOf : {vars : _} ->
               {auto c : Ref Ctxt Defs} ->
               {auto u : Ref UST UState} ->
               FC -> Env Term vars -> (topTy : ClosedTerm) -> (target : NF vars) ->
               List (Core (Term vars)) ->
               Core (Term vars)
exactlyOneOf {vars} fc env top target all
    = do elabs <- successful all
         case nubBy ((==) `on` fst) $ rights elabs of
              [(res, defs, ust)] =>
                    do put UST ust
                       put Ctxt defs
                       commit
                       pure res
              [] => failWithCause fc top (lefts elabs)
              rs => throw (AmbiguousSearch fc env !(quote !(get Ctxt) env target)
                             !(traverse normRes rs))
  where
    normRes : (Term vars, Defs, UState) -> Core (Term vars)
    normRes (tm, defs, _) = normaliseHoles defs env tm

exactlyOne : {vars : _} ->
             {auto c : Ref Ctxt Defs} ->
             {auto u : Ref UST UState} ->
             FC -> Env Term vars -> (topTy : ClosedTerm) -> (target : NF vars) ->
             List (Core (Term vars)) ->
             Core (Term vars)
exactlyOne fc env top target [elab]
    = catch elab $
         \case
           err@(CantSolveGoal {}) => throw err
           _ => throw $ CantSolveGoal fc (gamma !(get Ctxt)) Env.empty top Nothing
exactlyOne fc env top target all = exactlyOneOf fc env top target all

-- We can only resolve things which are at unrestricted multiplicity. Expression
-- search happens before linearity checking and we can't guarantee that just
-- because something is apparently available now, it will be available by the
-- time we get to linearity checking.
-- It's also fine to use anything if we're working at multiplicity 0
getUsableEnv : FC -> RigCount ->
               SizeOf done ->
               Env Term vars ->
               -- TODO this will be `vars <>< done` after refactoring
               List (Term (done ++ vars), Term (done ++ vars))
getUsableEnv fc rigc p [] = []
getUsableEnv {vars = v :: vs} {done} fc rigc p (b :: env)
   = let rest = getUsableEnv fc rigc (sucR p) env in
         if (multiplicity b == top || isErased rigc)
            then let 0 var = mkIsVar (hasLength p) in
                     (Local (binderLoc b) Nothing _ var,
                       rewrite appendAssociative done (Scope.single v) vs in
                          weakenNs (sucR p) (binderType b)) ::
                               rewrite appendAssociative done (Scope.single v) vs in rest
            else rewrite appendAssociative done (Scope.single v) vs in rest

-- A local is usable if it contains no holes in a determining argument position
usableLocal : {vars : _} ->
              {auto c : Ref Ctxt Defs} ->
              FC -> (defaults : Bool) ->
              Env Term vars -> (locTy : NF vars) -> Core Bool
-- pattern variables count as concrete things!
usableLocal loc defaults env (NApp fc (NMeta (PV {}) _ _) args)
    = pure True
usableLocal loc defaults env (NApp fc (NMeta {}) args)
    = pure False
usableLocal {vars} loc defaults env (NTCon _ n _ _ args)
    = do sd <- getSearchData loc (not defaults) n
         usableLocalArg 0 (detArgs sd) (map snd args)
  -- usable if none of the determining arguments of the local's type are
  -- holes
  where
    usableLocalArg : Nat -> NatSet -> List (Closure vars) -> Core Bool
    usableLocalArg i dets [] = pure True
    usableLocalArg i dets (c :: cs)
        = if i `elem` dets
             then do defs <- get Ctxt
                     u <- usableLocal loc defaults env !(evalClosure defs c)
                     if u
                        then usableLocalArg (1 + i) dets cs
                        else pure False
             else usableLocalArg (1 + i) dets cs
usableLocal loc defaults env (NDCon _ n _ _ args)
    = do defs <- get Ctxt
         us <- traverse (usableLocal loc defaults env)
                        !(traverse (evalClosure defs) $ map snd args)
         pure (all id us)
usableLocal loc defaults env (NApp _ (NLocal {}) args)
    = do defs <- get Ctxt
         us <- traverse (usableLocal loc defaults env)
                        !(traverse (evalClosure defs) $ map snd args)
         pure (all id us)
usableLocal loc defaults env (NBind fc x (Pi {}) sc)
    = do defs <- get Ctxt
         usableLocal loc defaults env
                !(sc defs (toClosure defaultOpts env (Erased fc Placeholder)))
usableLocal loc defaults env (NErased {}) = pure False
usableLocal loc _ _ _ = pure True

searchLocalWith : {vars : _} ->
                  {auto c : Ref Ctxt Defs} ->
                  {auto u : Ref UST UState} ->
                  FC -> RigCount ->
                  (defaults : Bool) -> List (Term vars) ->
                  (depth : Nat) ->
                  (defining : Name) -> (topTy : ClosedTerm) ->
                  Env Term vars -> Maybe TargetHeads -> (Term vars, Term vars) ->
                  (target : NF vars) -> Core (Term vars)
searchLocalWith {vars} fc rigc defaults trying depth def top env heads (prf, ty) target
    = do defs <- get Ctxt
         nty <- nf defs env ty
         findPos defs pure nty target
  where
    clearEnvType : {idx : Nat} -> (0 p : IsVar nm idx vs) ->
                   FC -> Env Term vs -> Env Term vs
    clearEnvType First fc (b :: env)
        = Lam (binderLoc b) (multiplicity b) Explicit (Erased fc Placeholder) :: env
    clearEnvType (Later p) fc (b :: env) = b :: clearEnvType p fc env

    clearEnv : Term vars -> Env Term vars -> Env Term vars
    clearEnv (Local fc _ idx p) env
        = clearEnvType p fc env
    clearEnv _ env = env

    findDirect : Defs ->
                 (Term vars -> Core (Term vars)) ->
                 NF vars ->  -- local's type
                 (target : NF vars) ->
                 Core (Term vars)
    findDirect defs f ty target
        = do -- Reject a local whose type clashes with the goal before
             -- making metavariables for its arguments
             whenJust heads $ \ th =>
               do ok <- localCanMatch env th ty
                  unless ok $
                    do profileCount "search.rejected.local" 1
                       throw (CantSolveGoal fc (gamma defs) Env.empty top Nothing)
             (args, appTy) <- mkArgs fc rigc env ty
             fprf <- f prf
             logTermNF "auto" 10 "Trying" env fprf
             logNF "auto" 10 "Type" env ty
             logNF "auto" 10 "For target" env target
             ures <- unify inTerm fc env target appTy
             let [] = constraints ures
                 | _ => throw (CantSolveGoal fc (gamma defs) Env.empty top Nothing)
             -- We can only use the local if its type is not an unsolved hole
             if !(usableLocal fc defaults env ty)
                then do
                   let candidate = apply fc fprf (map metaApp args)
                   logTermNF "auto" 10 "Local var candidate " env candidate
                   -- Clear the local from the environment to avoid getting
                   -- into a loop repeatedly applying it
                   let env' = clearEnv prf env
                   -- Work right to left, because later arguments may solve
                   -- earlier ones by unification
                   traverse_ (searchIfHole fc defaults trying False depth def top env'
                                          (LocalCand prf))
                            (impLast args)
                   pure candidate
                else do logNF "auto" 10 "Can't use " env ty
                        throw (CantSolveGoal fc (gamma defs) Env.empty top Nothing)

    findPos : Defs ->
              (Term vars -> Core (Term vars)) ->
              NF vars ->  -- local's type
              (target : NF vars) ->
              Core (Term vars)
    findPos defs f nty@(NTCon pfc pn _ _ [(_, xty), (_, yty)]) target
        = tryUnifyUnambig (findDirect defs f nty target) $
             do fname <- maybe (throw (CantSolveGoal fc (gamma defs) Env.empty top Nothing))
                               pure
                               !fstName
                sname <- maybe (throw (CantSolveGoal fc (gamma defs) Env.empty top Nothing))
                               pure
                               !sndName
                if !(isPairType pn)
                   then do empty <- clearDefs defs
                           xtytm <- quote empty env xty
                           ytytm <- quote empty env yty
                           exactlyOne fc env top target
                            [(do xtynf <- evalClosure defs xty
                                 findPos defs
                                     (\arg => normalise defs env $ apply fc (Ref fc Func fname)
                                                        [xtytm,
                                                         ytytm,
                                                         !(f arg)])
                                     xtynf target),
                             (do ytynf <- evalClosure defs yty
                                 findPos defs
                                     (\arg => normalise defs env $ apply fc (Ref fc Func sname)
                                                        [xtytm,
                                                         ytytm,
                                                         !(f arg)])
                                     ytynf target)]
                   else throw (CantSolveGoal fc (gamma defs) Env.empty top Nothing)
    findPos defs f nty target
        = findDirect defs f nty target

searchLocalVars : {vars : _} ->
                  {auto c : Ref Ctxt Defs} ->
                  {auto u : Ref UST UState} ->
                  FC -> RigCount ->
                  (defaults : Bool) -> List (Term vars) ->
                  (depth : Nat) ->
                  (defining : Name) -> (topTy : ClosedTerm) ->
                  Env Term vars -> Maybe TargetHeads ->
                  (target : NF vars) -> Core (Term vars)
searchLocalVars fc rig defaults trying depth def top env heads target
    = do let usable = getUsableEnv fc rig zero env
         let try = \t => searchLocalWith fc rig defaults trying depth def
                                         top env heads t target
         case usable of
              [_] => exactlyOne fc env top target (map try usable)
              _ => -- Drop the locals whose types clash with the goal before
                   -- evaluating them
                   do usable' <- maybe (pure usable)
                                       (\ th => filterM (localTypeCanMatch th . snd) usable)
                                       heads
                      profileCount "search.rejected.local"
                                   (cast (length usable) - cast (length usable'))
                      exactlyOneOf fc env top target (map try usable')

isPairNF : {auto c : Ref Ctxt Defs} ->
           Env Term vars -> NF vars -> Defs -> Core Bool
isPairNF env (NTCon _ n _ _ _) defs
    = isPairType n
isPairNF env (NBind fc b (Pi {}) sc) defs
    = isPairNF env !(sc defs (toClosure defaultOpts env (Erased fc Placeholder))) defs
isPairNF _ _ _ = pure False

searchName : {vars : _} ->
             {auto c : Ref Ctxt Defs} ->
             {auto u : Ref UST UState} ->
             FC -> RigCount ->
             (defaults : Bool) -> List (Term vars) ->
             (depth : Nat) ->
             (defining : Name) -> (topTy : ClosedTerm) ->
             Env Term vars -> Maybe TargetHeads -> (target : NF vars) ->
             (Name, GlobalDef) ->
             Core (Term vars)
searchName fc rigc defaults trying depth def top env heads target (n, ndef)
    = do defs <- get Ctxt
         when (not (visibleInAny (!getNS :: !getNestedNS)
                                 (fullname ndef) (collapseDefault $ visibility ndef))) $
            throw (CantSolveGoal fc (gamma defs) Env.empty top Nothing)
         when (BlockedHint `elem` flags ndef) $
            throw (CantSolveGoal fc (gamma defs) Env.empty top Nothing)

         ty <- freshenLevels (type ndef)
         when (isErased ty) $
            throw (CantSolveGoal fc (gamma defs) [] top Nothing)

         -- Reject a hint whose type clashes with the goal before evaluating
         -- it and making metavariables for its arguments
         whenJust heads $ \ th =>
           unless (hintCanMatch th ty) $
             do profileCount "search.rejected.hint" 1
                throw (CantSolveGoal fc (gamma defs) Env.empty top Nothing)

         nty <- nf defs env (embed ty)
         logNF "auto" 10 ("Searching Name " ++ show n) env nty
         (args, appTy) <- mkArgs fc rigc env nty
         ures <- unify inTerm fc env target appTy
         let [] = constraints ures
             | _ => throw (CantSolveGoal fc (gamma defs) Env.empty top Nothing)
         ispair <- isPairNF env nty defs
         let candidate = apply fc (Ref fc (getDefNameType ndef) n) (map metaApp args)
         logTermNF "auto" 10 "Candidate " env candidate
         -- Work right to left, because later arguments may solve earlier
         -- dependencies by unification
         traverse_ (searchIfHole fc defaults trying ispair depth def top env
                                 (GlobalCand n))
                  (impLast args)
         pure candidate

searchNames : {vars : _} ->
              {auto c : Ref Ctxt Defs} ->
              {auto u : Ref UST UState} ->
              FC -> RigCount ->
              (defaults : Bool) -> List (Term vars) ->
              (depth : Nat) ->
              (defining : Name) -> (topTy : ClosedTerm) ->
              Env Term vars -> Maybe TargetHeads -> Bool -> List Name ->
              (target : NF vars) -> Core (Term vars)
searchNames fc rigc defaults trying depth defining topty env heads ambig [] target
    = throw (CantSolveGoal fc (gamma !(get Ctxt)) Env.empty topty Nothing)
searchNames fc rigc defaults trying depth defining topty env heads ambig (n :: ns) target
    = do defs <- get Ctxt
         visnsm <- traverse (visible (gamma defs) (currentNS defs :: nestedNS defs)) (n :: ns)
         let visns = mapMaybe id visnsm
         let try = searchName fc rigc defaults trying depth defining topty env heads target
         -- Drop the hints whose types clash with the goal before trying
         -- them, in a way that does not change which error is reported
         let keep : (Name, GlobalDef) -> Bool
             keep nd = maybe True (\ th => hintCanMatch th (type (snd nd))) heads
         if ambig
            then do let visns' = dropRejectedInit keep visns
                    profileCount "search.rejected.hint"
                                 (cast (length visns) - cast (length visns'))
                    anyOne fc env topty (map try visns')
            else case visns of
                      [_] => exactlyOne fc env topty target (map try visns)
                      _ => do let visns' = filter keep visns
                              profileCount "search.rejected.hint"
                                           (cast (length visns) - cast (length visns'))
                              exactlyOneOf fc env topty target (map try visns')
  where
    visible : Context ->
              List Namespace -> Name -> Core (Maybe (Name, GlobalDef))
    visible gam nspace n
        = do Just def <- lookupCtxtExact n gam
                  | Nothing => pure Nothing
             if visibleInAny nspace n (collapseDefault $ visibility def)
                then pure $ Just (n, def)
                else pure $ Nothing

concreteDets : {vars : _} ->
               {auto c : Ref Ctxt Defs} ->
               FC -> Bool ->
               Env Term vars -> (top : ClosedTerm) ->
               (pos : Nat) -> (dets : NatSet) ->
               (args : List (Closure vars)) ->
               Core ()
concreteDets fc defaults env top pos dets [] = pure ()
concreteDets {vars} fc defaults env top pos dets (arg :: args)
    = do when (pos `elem` dets) $ do
           defs <- get Ctxt
           argnf <- evalClosure defs arg
           logNF "auto.determining" 10
             "Checking that the following argument is concrete"
             env argnf
           concrete defs argnf True
         concreteDets fc defaults env top (1 + pos) dets args
  where
    concrete : Defs -> NF vars -> (atTop : Bool) -> Core ()
    concrete defs (NBind nfc x b sc) atTop
        = do scnf <- sc defs (toClosure defaultOpts env (Erased nfc Placeholder))
             concrete defs scnf False
    concrete defs (NTCon nfc n a _ args) atTop
        = do sd <- getSearchData nfc False n
             let args' = NatSet.take (detArgs sd) args
             traverse_ (\ parg => do argnf <- evalClosure defs parg
                                     concrete defs argnf False) (map snd args')
    concrete defs (NDCon nfc n t a args) atTop
        = do traverse_ (\ parg => do argnf <- evalClosure defs parg
                                     concrete defs argnf False) (map snd args)
    concrete defs (NApp _ (NMeta n i _) _) True
        = do Just (Hole _ b) <- lookupDefExact n (gamma defs)
                  | _ => throw (DeterminingArg fc n i Env.empty top)
             unless (implbind b) $
                  throw (DeterminingArg fc n i Env.empty top)
    concrete defs (NApp _ (NMeta n i _) _) False
        = do Just (Hole _ b) <- lookupDefExact n (gamma defs)
                  | def => throw (CantSolveGoal fc (gamma defs) Env.empty top Nothing)
             unless (implbind b) $
                  throw (CantSolveGoal fc (gamma defs) Env.empty top Nothing)
    concrete defs tm atTop = pure ()

checkConcreteDets : {vars : _} ->
                    {auto c : Ref Ctxt Defs} ->
                    FC -> Bool ->
                    Env Term vars -> (top : ClosedTerm) ->
                    NF vars ->
                    Core ()
checkConcreteDets fc defaults env top (NTCon tfc tyn a inst args)
    = do defs <- get Ctxt
         if !(isPairType tyn)
            then case args of
                      [(_, aty), (_, bty)] =>
                          do anf <- evalClosure defs aty
                             bnf <- evalClosure defs bty
                             checkConcreteDets fc defaults env top anf
                             checkConcreteDets fc defaults env top bnf
                      _ => do sd <- getSearchData fc defaults tyn
                              concreteDets fc defaults env top 0 (detArgs sd) (map snd args)
            else
              do sd <- getSearchData fc defaults tyn
                 log "auto.determining" 10 $
                   "Determining arguments for " ++ show !(toFullNames tyn)
                   ++ " " ++ show (detArgs sd)
                 concreteDets fc defaults env top 0 (detArgs sd) (map snd args)
checkConcreteDets fc defaults env top _
    = pure ()

abandonIfCycle : {vars : _} ->
                 {auto c : Ref Ctxt Defs} ->
                 Env Term vars -> Term vars -> List (Term vars) ->
                 Core ()
abandonIfCycle env tm [] = pure ()
abandonIfCycle env tm (ty :: tys)
    = do defs <- get Ctxt
         if !(convert defs env tm ty)
            then throw (InternalError "Cycle in search")
            else abandonIfCycle env tm tys

-- Declared at the top
searchType fc rigc defaults trying depth def checkdets top env (Bind nfc x b@(Pi fc' c p ty) sc)
    = pure (Bind nfc x (Lam fc' c p ty)
             !(searchType fc rigc defaults [] depth def checkdets top
                          (b :: env) sc))
searchType fc rigc defaults trying depth def checkdets top env (Bind nfc x b@(Let fc' c val ty) sc)
    = pure (Bind nfc x b
             !(searchType fc rigc defaults [] depth def checkdets top
                          (b :: env) sc))
searchType {vars} fc rigc defaults trying depth def checkdets top env target
    = do defs <- get Ctxt
         abandonIfCycle env target trying
         let trying' = target :: trying
         nty <- nf defs env target
         case nty of
              NTCon tfc tyn a inst args =>
                  if a == length args
                     then do logNF "auto" 10 "Next target" env nty
                             sd <- getSearchData fc defaults tyn
                             -- Check determining arguments are okay for 'args'
                             when checkdets $
                                 checkConcreteDets fc defaults env top
                                                   (NTCon tfc tyn a inst args)
                             -- The heads of the arguments of the goal, to
                             -- reject candidates that cannot match it
                             heads <- targetHeads nty
                             if defaults && checkdets
                                then tryGroups heads Nothing nty (hintGroups sd)
                                else tryUnifyUnambig
                                       (searchLocalVars fc rigc defaults trying' depth def top env heads nty)
                                       (tryGroups heads Nothing nty (hintGroups sd))
                     else throw (CantSolveGoal fc (gamma defs) Env.empty top Nothing)
              _ => do logNF "auto" 10 "Next target: " env nty
                      searchLocalVars fc rigc defaults trying' depth def top env Nothing nty
  where
    -- Take the earliest error message (that's when we look inside pairs,
    -- typically, and it's best to be more precise)
    tryGroups : Maybe TargetHeads -> Maybe Error ->
                NF vars -> List (Bool, List Name) -> Core (Term vars)
    tryGroups heads (Just err) nty [] = throw err
    tryGroups heads Nothing nty [] = throw (CantSolveGoal fc (gamma !(get Ctxt)) Env.empty top Nothing)
    tryGroups heads merr nty ((ambigok, g) :: gs)
        = tryUnifyUnambig'
             (do logC "auto" 5
                        (do gn <- traverse getFullName g
                            pure ("Search: Trying " ++ show (length gn) ++
                                           " names " ++ show gn))
                 logNF "auto" 5 "For target" env nty
                 tryNoDefaultsFirst $ \d =>
                   searchNames fc rigc d (target :: trying) depth def top env heads ambigok g nty)
             (\err => tryGroups heads (Just $ maybe err (\e => preferSubgoalCause e err) merr) nty gs)

-- Declared in Core.Unify as:
-- search : {vars : _} ->
--          {auto c : Ref Ctxt Defs} ->
--          {auto u : Ref UST UState} ->
--          FC -> RigCount ->
--          (defaults : Bool) -> (depth : Nat) ->
--          (defining : Name) -> (topTy : Term vars) -> Env Term vars ->
--          Core (Term vars)
Core.Unify.search fc rigc defaults depth def top env
    = do logTermNF "auto" 3 "Initial target: " env top
         log "auto" 3 $ "Running search with defaults " ++ show defaults
         profileCount "search.run" 1
         tm <- profile "search" $
                 searchType fc rigc defaults [] depth def
                          True (abstractEnvType fc env top) env
                          top
         profileCount "search.ok" 1
         logTermNF "auto" 3 "Result" env tm
         pure tm
