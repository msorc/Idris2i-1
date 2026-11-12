module TTImp.Elab.Local

import Core.Env
import Core.Metadata
import Core.Normalise
import Core.Unify

import Idris.REPL.Opts
import Idris.Syntax

import TTImp.Elab.Check
import TTImp.TTImp

import Data.List1

import Libraries.Data.NameMap
import Libraries.Data.WithDefault

%default covering

export
localHelper : {vars : _} ->
             {auto c : Ref Ctxt Defs} ->
             {auto m : Ref MD Metadata} ->
             {auto u : Ref UST UState} ->
             {auto e : Ref EST (EState vars)} ->
             {auto s : Ref Syn SyntaxInfo} ->
             {auto o : Ref ROpts REPLOpts} ->
             NestedNames vars -> Env Term vars ->
             List ImpDecl -> (NestedNames vars -> Core a) ->
             Core a
localHelper {vars} nest env nestdecls_in func
    = do est <- get EST
         let f = defining est
         defs <- get Ctxt
         gdef <- lookupCtxtExact (Resolved (defining est)) (gamma defs)
         let vis  = maybe Public (collapseDefault . visibility) gdef
         let mult = maybe linear GlobalDef.multiplicity gdef

         -- If the parent function is public, the nested definitions need
         -- to be public too
         let nestdeclsVis =
               if vis == Public
                  then map setPublic nestdecls_in
                  else nestdecls_in

         -- If the parent function is erased, then the nested definitions
         -- will be erased too
         let nestdeclsMult =
           if mult == erased
              then map setErased nestdeclsVis
              else nestdeclsVis

         let defNames = definedInBlock emptyNS nestdeclsMult
         names' <- traverse (applyEnv f) defNames
         let nest' = { names $= (names' ++) } nest
         -- TODO is this comment still up-to-date?
         -- For the local definitions, don't allow access to linear things
         -- unless they're explicitly passed.
         -- This is because, at the moment, we don't have any mechanism of
         -- ensuring the nested definition is used exactly once
         let env' = eraseLinear env
         -- We don't want to keep rechecking delayed elaborators in the
         -- locals block, because they're not going to make progress until
         -- we come out again, so save them
         ust <- get UST
         let olddelayed = delayedElab ust
         put UST ({ delayedElab := [] } ust)
         defs <- get Ctxt
         -- store the local hints, so we can reset them after we've elaborated
         -- everything
         let oldhints = localHints defs

         let nestdecls = map (updateName nest') nestdeclsMult
         log "elab.def.local" 20 $ show nestdecls

         traverse_ (processDecl [] nest' env') nestdecls
         update UST { delayedElab := olddelayed }
         res <- func nest'
         update Ctxt { localHints := oldhints }
         pure res
  where
    applyEnv : Int -> Name ->
               Core (Name, (Maybe Name, List (Var vars), FC -> NameType -> Term vars))
    applyEnv outer inner
          = do ust <- get UST
               put UST ({ nextName $= (+1) } ust)
               let nestedName_in = Nested (outer, nextName ust) inner
               nestedName <- inCurrentNS nestedName_in
               n' <- addName nestedName
               pure (inner, (Just nestedName, reverse (allVars env),
                        \fc, nt => applyToFull fc
                               (Ref fc nt (Resolved n')) env))

    -- Update the names in the declarations to the new 'nested' names.
    -- When we encounter the names in elaboration, we'll update to an
    -- application of the nested name.
    updateTyName : NestedNames vars -> ImpTy -> ImpTy
    updateTyName nest ty
        = update "tyname" (map (mapNestedName nest)) ty

    updateDataName : NestedNames vars -> ImpData -> ImpData
    updateDataName nest (MkImpData loc' n tycons dopts dcons)
        = MkImpData loc' (mapNestedName nest n) tycons dopts
                         (map (updateTyName nest) dcons)
    updateDataName nest (MkImpLater loc' n tycons)
        = MkImpLater loc' (mapNestedName nest n) tycons

    updateFieldName : NestedNames vars -> IField -> IField
    updateFieldName nest field
        = update "name" (map (mapNestedName nest)) field

    updateRecordName : NestedNames vars -> ImpRecordData Name -> ImpRecordData Name
    updateRecordName nest (MkImpRecord header body)
        = let updatedTyName = (update "name" (map (mapNestedName nest)) header)
              updatedConName = (update "name" (map (mapNestedName nest)) body)
              updatedParameters = (map (map (updateFieldName nest)) updatedConName)
          in MkImpRecord updatedTyName updatedParameters

    updateRecordNS : NestedNames vars -> Maybe String -> Maybe String
    updateRecordNS _    Nothing   = Nothing
    updateRecordNS nest (Just ns) = Just $ show $ mapNestedName nest (UN $ mkUserName ns)

    updateName : NestedNames vars -> ImpDecl -> ImpDecl
    updateName nest (IClaim claim)
         = IClaim $ map {type $= updateTyName nest} claim
    updateName nest (IDef loc' n cs)
         = IDef loc' (mapNestedName nest n) cs
    updateName nest (IData loc' vis mbt d)
         = IData loc' vis mbt (updateDataName nest d)
    updateName nest (IRecord loc' ns vis mbt imprecord)
         = IRecord loc' (updateRecordNS nest ns) vis mbt (map (updateRecordName nest) imprecord)
    updateName nest i = i

    setPublic : ImpDecl -> ImpDecl
    setPublic (IClaim claim)
        = IClaim $ map {vis := Public} claim
    setPublic (IData fc _ mbt d) = IData fc (specified Public) mbt d
    setPublic (IRecord fc c _ mbt r) = IRecord fc c (specified Public) mbt r
    setPublic (IParameters fc ps decls)
        = IParameters fc ps (map setPublic decls)
    setPublic (INamespace fc ps decls)
        = INamespace fc ps (map setPublic decls)
    setPublic d = d

    setErased : ImpDecl -> ImpDecl
    setErased (IClaim claim)
        = IClaim $ map {rig := erased} claim
    setErased (IParameters fc ps decls)
        = IParameters fc ps (map setErased decls)
    setErased (INamespace fc ps decls)
        = INamespace fc ps (map setErased decls)
    setErased d = d

------------------------------------------------------------------------
-- Warning about local constants which are recomputed at each use
--
-- A local definition without arguments of its own, such as
--
--   f m xs = sum (map go xs)
--     where
--       us : SortedMap Nat Nat
--       us = expensive m
--       go : Nat -> Nat
--       go x = fromMaybe 0 (lookup x us)
--
-- is lifted to a top level function of the enclosing environment
-- (`us m xs`), so `us` is recomputed at each use rather than shared like a
-- `let` binding. We warn when such a definition (a) has no arguments of its
-- own, (b) uses a runtime relevant variable of the enclosing environment and
-- (c) is used repeatedly: from a local function with arguments, under a
-- lambda, or from more than one place.

-- The runtime relevant pattern variables that a right hand side refers to.
-- `d` counts the binders we went under inside the term.
outerVarsUsed : {vs : _} -> Env Term vs -> Term vs -> List Name
outerVarsUsed env tm = go (rigs env) Z tm []
  where
    rigs : {vs' : _} -> Env Term vs' -> List (Name, RigCount)
    rigs {vs' = []} [] = []
    rigs {vs' = x :: _} (b :: bs) = (x, multiplicity b) :: rigs bs

    -- `outer` is passed on rather than being a `where` constant, which
    -- would be recomputed at each use
    mutual
      go : List (Name, RigCount) -> Nat -> Term ns -> List Name -> List Name
      go outer d (Local _ _ idx _) acc
          = if idx < d
               then acc
               else case getAt (minus idx d) outer of
                         Just (n, r) => if isErased r || elem n acc
                                           then acc
                                           else n :: acc
                         Nothing => acc
      go outer d (Meta _ _ _ args) acc = foldr (go outer d) acc args
      go outer d (Bind _ _ b sc) acc
          = goBinder outer d b (go outer (S d) sc acc)
      go outer d (App _ f a) acc = go outer d f (go outer d a acc)
      go outer d (As _ _ a p) acc = go outer d a (go outer d p acc)
      go outer d (TDelayed _ _ t) acc = go outer d t acc
      go outer d (TDelay _ _ ty t) acc = go outer d t acc
      go outer d (TForce _ _ t) acc = go outer d t acc
      go outer d _ acc = acc

      goBinder : List (Name, RigCount) -> Nat -> Binder (Term ns) ->
                 List Name -> List Name
      goBinder outer d (Let _ _ v _) acc = go outer d v acc
      goBinder outer d (PLet _ _ v _) acc = go outer d v acc
      goBinder outer d _ acc = acc

-- What we know about how a local definition is used
record Uses where
  constructor MkUses
  count : Nat -- number of references found
  repeated : Bool -- found a reference which is evaluated repeatedly
  seen : List Name -- auxiliary definitions already looked at

-- Count the references to `target` in a term. `rep` says whether we're in
-- a context which is evaluated repeatedly (a lambda or a function with
-- arguments). We look inside the case and with blocks, nested functions
-- and solved holes the term refers to, except those in `skip` (the local
-- definitions of the block, which are looked at separately).
mutual
  usesIn : {auto c : Ref Ctxt Defs} ->
           (target : Name -> Bool) -> (skip : List Name) ->
           Bool -> Uses -> Term ns -> Core Uses
  usesIn tgt skip rep u (Ref _ _ n)
      = if tgt n
           then pure ({ count $= S, repeated $= (|| rep) } u)
           else do n' <- getFullName n
                   case auxRep n' of
                        Nothing => pure u
                        Just rep' => usesInDef tgt skip (rep || rep') u n'
    where
      auxRep : Name -> Maybe Bool
      auxRep nm
          = if nm `elem` skip
               then Nothing
               else case dropNS nm of
                         CaseBlock {} => Just False
                         WithBlock {} => Just False
                         Nested {} => Just True
                         _ => Nothing
  usesIn tgt skip rep u (Meta _ n i args)
      = do u <- usesInDef tgt skip rep u (Resolved i)
           usesInList tgt skip rep u args
  usesIn tgt skip rep u (Bind _ _ b sc)
      = do let rep' = case b of
                           Lam {} => True
                           _ => rep
           u <- usesInBinder tgt skip rep u b
           usesIn tgt skip rep' u sc
  usesIn tgt skip rep u (App _ f a)
      = do u <- usesIn tgt skip rep u f
           usesIn tgt skip rep u a
  usesIn tgt skip rep u (As _ _ _ p) = usesIn tgt skip rep u p
  usesIn tgt skip rep u (TDelayed _ _ t) = usesIn tgt skip rep u t
  usesIn tgt skip rep u (TDelay _ _ _ t) = usesIn tgt skip rep u t
  usesIn tgt skip rep u (TForce _ _ t) = usesIn tgt skip rep u t
  usesIn tgt skip rep u _ = pure u

  usesInList : {auto c : Ref Ctxt Defs} ->
               (target : Name -> Bool) -> (skip : List Name) ->
               Bool -> Uses -> List (Term ns) -> Core Uses
  usesInList tgt skip rep u [] = pure u
  usesInList tgt skip rep u (t :: ts)
      = do u <- usesIn tgt skip rep u t
           usesInList tgt skip rep u ts

  usesInBinder : {auto c : Ref Ctxt Defs} ->
                 (target : Name -> Bool) -> (skip : List Name) ->
                 Bool -> Uses -> Binder (Term ns) -> Core Uses
  usesInBinder tgt skip rep u (Let _ _ v _) = usesIn tgt skip rep u v
  usesInBinder tgt skip rep u (PLet _ _ v _) = usesIn tgt skip rep u v
  usesInBinder tgt skip rep u _ = pure u

  -- References in the right hand sides of a definition
  usesInDef : {auto c : Ref Ctxt Defs} ->
              (target : Name -> Bool) -> (skip : List Name) ->
              Bool -> Uses -> Name -> Core Uses
  usesInDef tgt skip rep u n
      = if n `elem` seen u
           then pure u
           else do defs <- get Ctxt
                   let u = { seen $= (n ::) } u
                   Just gdef <- lookupCtxtExact n (gamma defs)
                        | Nothing => pure u
                   let PMDef _ _ _ _ pats = definition gdef
                        | _ => pure u
                   usesInPats u pats
    where
      usesInPats : Uses -> List (vs ** (Env Term vs, Term vs, Term vs)) ->
                   Core Uses
      usesInPats u [] = pure u
      usesInPats u ((_ ** (_, _, rhs)) :: ps)
          = do u <- usesIn tgt skip rep u rhs
               usesInPats u ps

-- What we need to know about each local definition of the block
record LocalInfo where
  constructor MkLocalInfo
  userName : Name
  fullName : Name
  resName : Name
  loc : FC
  hasArgs : Bool
  outerUses : List Name -- enclosing variables used, if it has no arguments
  rhss : List (vs ** Term vs)

usesInRhss : {auto c : Ref Ctxt Defs} ->
             (Name -> Bool) -> List Name -> Bool -> Uses ->
             List (vs ** Term vs) -> Core Uses
usesInRhss tgt skip rep u [] = pure u
usesInRhss tgt skip rep u ((_ ** t) :: ts)
    = do u <- usesIn tgt skip rep u t
         usesInRhss tgt skip rep u ts

-- Look for the candidates among the definitions of a local block. If one is
-- used repeatedly from the other definitions of the block, warn now.
-- Otherwise, the decision depends on the uses in the scope of the block,
-- which may still be in delayed elaborators, so we save it until the
-- enclosing definition is complete (see `checkWhereUses`).
warnRecomputed : {vars : _} ->
                 {auto c : Ref Ctxt Defs} ->
                 {auto u : Ref UST UState} ->
                 {auto e : Ref EST (EState vars)} ->
                 List (Name, (Maybe Name, List (Var vars), FC -> NameType -> Term vars)) ->
                 Core ()
warnRecomputed {vars} new
    = do est <- get EST
         defs <- get Ctxt
         Just outer <- lookupCtxtExact (Resolved (defining est)) (gamma defs)
              | Nothing => pure ()
         -- Nothing to share at runtime if the enclosing definition is erased
         let False = isErased (multiplicity outer)
              | True => pure ()
         infos <- traverse getInfo new
         let infos = catMaybes infos
         let skip = map fullName infos
         traverse_ (checkInfo (defining est) (fullname outer) skip infos) infos
  where
    getInfo : (Name, (Maybe Name, List (Var vars), FC -> NameType -> Term vars)) ->
              Core (Maybe LocalInfo)
    getInfo (inner, (Just n, _, _))
        = do defs <- get Ctxt
             Just gdef <- lookupCtxtExact n (gamma defs)
                  | Nothing => pure Nothing
             let PMDef _ args _ _ pats = definition gdef
                  | _ => pure Nothing
             rn <- toResolvedNames (fullname gdef)
             arity <- getArity defs Env.empty (type gdef)
             let hasArgs = arity > length vars || length args > length vars
             -- Only runtime relevant definitions matter
             let outerUses
                   = if hasArgs || isErased (multiplicity gdef)
                        then []
                        else nub $ concatMap (\ (_ ** (penv, _, rhs)) =>
                                                outerVarsUsed penv rhs) pats
             pure $ Just $ MkLocalInfo inner (fullname gdef) rn (location gdef)
                         hasArgs outerUses
                         (map (\ (vs ** (_, _, rhs)) => (vs ** rhs)) pats)
    getInfo _ = pure Nothing

    checkInfo : Int -> Name -> List Name -> List LocalInfo -> LocalInfo -> Core ()
    checkInfo outerIdx outer skip infos info
        = case outerUses info of
               [] => pure ()
               (d :: ds) =>
                 do let tgt = \ n => n == resName info || n == fullName info
                    let others = filter (\ i => fullName i /= fullName info) infos
                    u <- foldlC (\ u, i => usesInRhss tgt skip (hasArgs i) u (rhss i))
                                (MkUses 0 False []) others
                    if repeated u || count u > 1
                       then recordWarning (WhereRecompute (loc info) (userName info)
                                                          outer (d ::: ds))
                       else update UST { whereChecks $=
                                 (MkWhereCheck outerIdx (resName info) (fullName info)
                                               (userName info) (loc info) (d ::: ds)
                                               skip (count u) ::) }

||| Called once a definition is complete, with its checked clauses: decide
||| whether the local definitions saved by `warnRecomputed` for it are used
||| repeatedly.
export
checkWhereUses : {auto c : Ref Ctxt Defs} ->
                 {auto u : Ref UST UState} ->
                 Int -> List (vs ** (Env Term vs, Term vs, Term vs)) -> Core ()
checkWhereUses n pats
    = do ust <- get UST
         let (mine, rest) = partition (\ w => wcOuter w == n) (whereChecks ust)
         let (_ :: _) = mine
              | [] => pure ()
         put UST ({ whereChecks := rest } ust)
         outerName <- getFullName (Resolved n)
         traverse_ (checkOne outerName) (reverse mine)
  where
    checkOne : Name -> WhereCheck -> Core ()
    checkOne outerName w
        = do let tgt = \ nm => nm == wcLocal w || nm == wcLocalFull w
             u <- usesInRhss tgt (wcSkip w) False (MkUses (wcUses w) False [])
                             (map (\ (vs ** (_, _, rhs)) => (vs ** rhs)) pats)
             when (repeated u || count u > 1) $
               recordWarning (WhereRecompute (wcLoc w) (wcUser w) outerName (wcDeps w))

export
checkLocal : {vars : _} ->
             {auto c : Ref Ctxt Defs} ->
             {auto m : Ref MD Metadata} ->
             {auto u : Ref UST UState} ->
             {auto e : Ref EST (EState vars)} ->
             {auto s : Ref Syn SyntaxInfo} ->
             {auto o : Ref ROpts REPLOpts} ->
             RigCount -> ElabInfo ->
             NestedNames vars -> Env Term vars ->
             FC -> List ImpDecl -> (scope : RawImp) ->
             (expTy : Maybe (Glued vars)) ->
             Core (Term vars, Glued vars)
checkLocal {vars} rig elabinfo nest env fc nestdecls_in scope expty
    = localHelper nest env nestdecls_in $ \nest' =>
        do res <- check rig elabinfo nest' env scope expty
           when (warnWhereRecompute !getSession) $
             do let new = take (length (definedInBlock emptyNS nestdecls_in))
                               (names nest')
                warnRecomputed new
           pure res

getLocalTerm : {vars : _} ->
               {auto c : Ref Ctxt Defs} ->
               FC -> Env Term vars -> Term vars -> List Name ->
               Core (Term vars, List (Var vars))
getLocalTerm fc env f [] = pure (f, [])
getLocalTerm fc env f (a :: as)
    = case defined a env of
           Just (MkIsDefined rigb lv) =>
                do (tm, vs) <- getLocalTerm fc env
                                   (App fc f (Local fc Nothing _ lv)) as
                   pure (tm, MkVar lv :: vs)
           Nothing => throw (InternalError "Case Local failed")

export
checkCaseLocal : {vars : _} ->
                 {auto c : Ref Ctxt Defs} ->
                 {auto m : Ref MD Metadata} ->
                 {auto u : Ref UST UState} ->
                 {auto e : Ref EST (EState vars)} ->
                 {auto s : Ref Syn SyntaxInfo} ->
                 {auto o : Ref ROpts REPLOpts} ->
                 RigCount -> ElabInfo ->
                 NestedNames vars -> Env Term vars ->
                 FC -> Name -> Name -> List Name -> RawImp ->
                 (expTy : Maybe (Glued vars)) ->
                 Core (Term vars, Glued vars)
checkCaseLocal {vars} rig elabinfo nest env fc uname iname args sc expty
    = do defs <- get Ctxt
         Just def <- lookupCtxtExact iname (gamma defs)
              | Nothing => check rig elabinfo nest env sc expty
         let nt = getDefNameType def
         let name = Ref fc nt iname
         (app, args) <- getLocalTerm fc env name args
         log "elab.local" 5 $ "Updating case local " ++ show uname ++ " " ++ show args
         logTermNF "elab.local" 5 "To" env app
         let nest' = { names $= ((uname, (Just iname, args,
                                         (\fc, nt => app))) :: ) }
                     nest
         check rig elabinfo nest' env sc expty
