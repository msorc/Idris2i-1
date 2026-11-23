||| Universe checking (`--check-universes`).
|||
||| The elaborator gives every `Type` it builds a name standing for its
||| universe level (TTImp.Elab.Check.uniVar), but it never relates these
||| names, so `Type : Type` holds and the logic is inconsistent. This module
||| checks the elaborated definitions again, after the elaborator, as a small
||| type checker which infers the type of every subterm and records
|||
|||  * `u < v` for `Type u : Type v`,
|||  * `a <= w` and `b <= w` when `(x : A) -> B : Type w`, with `A : Type a`
|||    and `B : Type b`,
|||  * `u <= v` when a term of type `Type u` is used where `Type v` is
|||    expected (cumulativity; also in the codomain of function types),
|||  * `u = v` when conversion checking compares `Type u` with `Type v`
|||    anywhere else (Core.Normalise.Convert collects these), and on the
|||    left hand side of clauses,
|||  * `w <= a` for the variables bound by a pattern which matches on a
|||    type of `Type w` (see 'inferPat'),
|||  * `a <= u` for every field of a constructor of a data type in `Type u`,
|||    where the field's type is in `Type a`. Parameters are not fields; the
|||    universes of a parameter in the constructor's type are made equal to
|||    those in the data type's type. An index (an argument of the data type
|||    in the return type of a constructor which is not a parameter) can be
|||    in a smaller universe than the data type's argument: it is not stored.
|||
||| The constraints are kept in a graph (Core.Context.Universe), which is
||| inconsistent when it has a cycle with a strict edge. The check runs after
||| each declaration; the constraints are saved in the TTC file so that the
||| modules importing it are checked against them.
|||
||| Universe polymorphism. Terms do not say at which universes a global
||| definition is used, so renaming the universes of a definition at a use is
||| only sound for those universes which evaluation can never produce: if
||| `T = Type u` and every use of `T` could pick its own `u`, `T : T` would be
||| accepted. So a definition is polymorphic in the universes of its type
||| and left hand sides which are not "fixed", where the fixed universes are
||| those occurring in the right hand side of a clause (or in the solution of
||| a metavariable reachable from it or from the type), or in a field of a
||| constructor (the contents of a data type do not depend on the instance,
||| since a data type is not applied to its universes). A data type and its
||| constructors are renamed together. A universe which also occurs in the
||| type of another definition is renamed only if that definition is
||| polymorphic in it and was complete before this one was started. A use of
||| a polymorphic definition renames these universes to fresh ones and copies
||| the constraints which checking the definition put on them. A definition
||| is used monomorphically (with its own universe names) until it has been
||| checked completely, so recursive and mutual uses are monomorphic, and so
||| are definitions which met an unsolved metavariable or something the check
||| could not handle (see 'gap').
|||
||| The type of a solved metavariable is taken to be the type of its solution
||| (the type it was made with can be out of date). When checking universes,
||| the elaborator gives the universes of a global's type fresh names at each
||| use (see 'freshenLevels'), so that the terms it builds don't share them.
module Core.UniverseCheck

import Core.Case.CaseTree
import Core.Context
import Core.Context.Log
import Core.Env
import Core.Normalise
import Core.Options
import Core.TT
import Core.Value

import Data.List
import Data.String
import Libraries.Data.NameMap
import Libraries.Data.NatSet
import Libraries.Data.WithDefault

%default covering

data UCK : Type where

record UCState where
  constructor MkUCState
  origin : Name -- the definition being checked
  loc : FC
  next : Int -- for the names of the universes made by the check itself
  edges : List UEdge
  sawPending : Bool -- met an unsolved metavariable
  incomplete : Bool -- met something it could not check
  metaTypes : NameMap ClosedTerm -- the types of the solutions inferred so far

isLocalU : Name -> Bool
isLocalU (MN "ucheck" _) = True
isLocalU _ = False

freshU : {auto s : Ref UCK UCState} -> Core Name
freshU
    = do st <- get UCK
         put UCK ({ next $= (+1) } st)
         pure (MN "ucheck" (next st))

canonical : {auto c : Ref Ctxt Defs} -> Name -> Core Name
canonical n = getFullName n

addEdge : {auto c : Ref Ctxt Defs} ->
          {auto s : Ref UCK UCState} ->
          Bool -> Name -> Name -> Core ()
addEdge strict lo hi
    = do lo <- canonical lo
         hi <- canonical hi
         st <- get UCK
         let e = MkUEdge lo hi strict (origin st)
         when (strict || lo /= hi) $
           put UCK ({ edges $= (e ::) } st)

addLE, addLT, addEq : {auto c : Ref Ctxt Defs} ->
                      {auto s : Ref UCK UCState} ->
                      Name -> Name -> Core ()
addLE = addEdge False
addLT = addEdge True
addEq a b = do addEdge False a b; addEdge False b a

||| Something the check could not handle: the elaborated term is not well
||| typed as far as the checker can tell (the elaborator builds the motive
||| of a `rewrite` by abstraction, without checking it again, for instance).
||| The check goes on, but the definition is recorded as not checked
||| completely (it is reported in a warning, and it is not made universe
||| polymorphic), so that the check does not claim more than it does.
gap : {auto c : Ref Ctxt Defs} ->
      {auto s : Ref UCK UCState} ->
      String -> Core ()
gap msg
    = do st <- get UCK
         log "universe" 1 $ "Universe check of " ++ show (origin st) ++ ": " ++ msg
         put UCK ({ incomplete := True } st)

-- The universe names in a term, as they are written
levelsOf : Term vars -> List Name -> List Name
levelsOf (Local {}) acc = acc
levelsOf (Ref _ (TyCon _ inst) _) acc = inst ++ acc
levelsOf (Ref {}) acc = acc
levelsOf (Meta _ _ _ args) acc = foldr levelsOf acc args
levelsOf (Bind _ _ b sc) acc = foldr levelsOf (levelsOf sc acc) b
levelsOf (App _ f a) acc = levelsOf f (levelsOf a acc)
levelsOf (As _ _ a p) acc = levelsOf a (levelsOf p acc)
levelsOf (TDelayed _ _ t) acc = levelsOf t acc
levelsOf (TDelay _ _ t v) acc = levelsOf t (levelsOf v acc)
levelsOf (TForce _ _ t) acc = levelsOf t acc
levelsOf (PrimVal {}) acc = acc
levelsOf (Erased _ (Dotted t)) acc = levelsOf t acc
levelsOf (Erased {}) acc = acc
levelsOf (TType _ u) acc = u :: acc

canonicalLevels : {auto c : Ref Ctxt Defs} -> Term vars -> Core (List Name)
canonicalLevels tm = nub <$> traverse canonical (levelsOf tm [])

evalLevelsFrom : {auto c : Ref Ctxt Defs} -> (self : Bool) -> Term vars ->
                 Core (List Name)
evalLevelsFrom self tm
    = do (_, ls) <- start self
         pure ls
  where
    metas : Term vs -> List Int -> List Int
    metas (Meta _ _ i args) acc = i :: foldr metas acc args
    metas (Bind _ _ b sc) acc = foldr metas (metas sc acc) b
    metas (App _ f a) acc = metas f (metas a acc)
    metas (As _ _ a p) acc = metas p acc
    metas (TDelayed _ _ t) acc = metas t acc
    metas (TDelay _ _ t v) acc = metas t (metas v acc)
    metas (TForce _ _ t) acc = metas t acc
    metas (Erased _ (Dotted t)) acc = metas t acc
    metas _ acc = acc

    -- The state is the metavariables done already, and the universes found
    go : (List Int, List Name) -> Either Int (Term vars) -> Core (List Int, List Name)
    go (seen, acc) (Right t)
        = do ls <- traverse canonical (levelsOf t [])
             foldlC (\ st, i => go st (Left i)) (seen, ls ++ acc) (metas t [])
    go (seen, acc) (Left i)
        = if elem i seen then pure (seen, acc) else
          do defs <- get Ctxt
             Just gdef <- lookupCtxtExact (Resolved i) (gamma defs)
                  | Nothing => pure (i :: seen, acc)
             case definition gdef of
                  PMDef _ [] (STerm _ sol) _ _ =>
                    -- the solution is closed
                    go (i :: seen, acc) (Right (embed sol))
                  _ => pure (i :: seen, acc)

    start : Bool -> Core (List Int, List Name)
    start True = go ([], []) (Right tm)
    start False = foldlC (\ st, i => go st (Left i)) ([], []) (metas tm [])

||| The universes which evaluating a term can produce: those in the term and,
||| for the metavariables in it, in their solutions
evalLevels : {auto c : Ref Ctxt Defs} -> Term vars -> Core (List Name)
evalLevels tm = nub <$> evalLevelsFrom True tm

||| The universes in the solutions of the metavariables in a term
metaLevels : {auto c : Ref Ctxt Defs} -> Term vars -> Core (List Name)
metaLevels tm = nub <$> evalLevelsFrom False tm

renameLevels : {auto c : Ref Ctxt Defs} ->
               NameMap Name -> Term vars -> Core (Term vars)
renameLevels ren tm@(Local {}) = pure tm
renameLevels ren tm@(Ref fc (TyCon a inst) n)
    = do inst <- if null inst then ownInstance else pure inst
         if null inst
            then pure tm
            else pure (Ref fc (TyCon a !(traverse rn inst)) n)
  where
    rn : Name -> Core Name
    rn u = do u <- canonical u
              pure (fromMaybe u (lookup u ren))

    -- A use without an instance stands for the family's own universes; when
    -- the renaming renames some of them (the type of a constructor of the
    -- family refers to the family), the use gets them as its instance, so
    -- that it is renamed with them
    ownInstance : Core (List Name)
    ownInstance
        = do defs <- get Ctxt
             fn <- canonical n
             let Just sch = lookup fn (schemas (universes defs))
                  | Nothing => pure []
             pure (if any (\ p => isJust (lookup p ren)) (instOnly sch)
                      then instOnly sch else [])
renameLevels ren tm@(Ref {}) = pure tm
renameLevels ren (Meta fc n i args)
    = Meta fc n i <$> traverse (renameLevels ren) args
renameLevels ren (Bind fc x b sc)
    = Bind fc x <$> traverse (renameLevels ren) b <*> renameLevels ren sc
renameLevels ren (App fc f a)
    = App fc <$> renameLevels ren f <*> renameLevels ren a
renameLevels ren (As fc s a p) = As fc s a <$> renameLevels ren p
renameLevels ren (TDelayed fc r t) = TDelayed fc r <$> renameLevels ren t
renameLevels ren (TDelay fc r t v)
    = TDelay fc r <$> renameLevels ren t <*> renameLevels ren v
renameLevels ren (TForce fc r t) = TForce fc r <$> renameLevels ren t
renameLevels ren tm@(PrimVal {}) = pure tm
renameLevels ren (Erased fc (Dotted t))
    = Erased fc . Dotted <$> renameLevels ren t
renameLevels ren tm@(Erased {}) = pure tm
renameLevels ren (TType fc u)
    = do u <- canonical u
         pure (TType fc (fromMaybe u (lookup u ren)))

addFixed : {auto c : Ref Ctxt Defs} -> List Name -> Core ()
addFixed ns
    = do defs <- get Ctxt
         let new = filter (\ n => not (isJust (lookup n (fixed (universes defs))))) ns
         unless (null new) $
           put Ctxt ({ universes->fixed $= insertFrom (map (\ n => (n, ())) new),
                       universes->savedFixed $= (new ++) } defs)

addOwner : Name -> NameMap (List Name) -> Name -> NameMap (List Name)
addOwner o m l
    = let os = fromMaybe [] (lookup l m) in
          if elem o os then m else insert l (o :: os) m

-- Record which definition's type the universes of a type belong to
addTypeOwner : {auto c : Ref Ctxt Defs} -> Name -> ClosedTerm -> Core ()
addTypeOwner n ty
    = do fn <- getFullName n
         ls <- canonicalLevels ty
         update Ctxt { universes->typeOwner $= \ m => foldl (addOwner fn) m ls,
                       universes->savedTypeOwner $= (map (\ l => (l, fn)) ls ++) }

-- Conversion, recording the universes it identifies
convertU : {auto c : Ref Ctxt Defs} ->
           {auto s : Ref UCK UCState} ->
           {vars : _} ->
           Env Term vars -> NF vars -> NF vars -> Core ()
convertU env x y
    = do r <- coreLift $ newIORef []
         defs <- get Ctxt
         let cdefs = { ucollect := Just r } defs
         ok <- convert cdefs env x y
         -- The elaborator compares types without the arguments which other
         -- arguments determine (see 'inferrable'), so a term it accepts may
         -- only convert with them skipped
         ok <- if ok then pure True else convertInf cdefs env x y
         pairs <- coreLift $ readIORef r
         traverse_ (uncurry addEq) pairs
         unless ok $
           do xt <- quote defs env x
              yt <- quote defs env y
              gap ("the types " ++ show !(toFullNames xt) ++ " and "
                   ++ show !(toFullNames yt) ++ " do not convert")

-- 'got' is the type of a term used where 'exp' is expected. With 'cumul',
-- 'got' can be in a lower universe (also in the codomain of a function
-- type), otherwise the universes have to be equal.
subtypeU : {auto c : Ref Ctxt Defs} ->
           {auto s : Ref UCK UCState} ->
           {vars : _} ->
           (cumul : Bool) ->
           Env Term vars -> NF vars -> NF vars -> Core ()
subtypeU True env (NType _ a) (NType _ b) = addLE a b
subtypeU _ env (NErased {}) _ = pure ()
subtypeU _ env _ (NErased {}) = pure ()
subtypeU True env (NBind fc x (Pi _ c p aty) sc) (NBind _ _ (Pi _ c' p' aty') sc')
    = do defs <- get Ctxt
         convertU env !(evalClosure defs aty) !(evalClosure defs aty')
         st <- get UCK
         put UCK ({ next $= (+1) } st)
         let var = MN "ucheckvar" (next st)
         let cl = MkClosure defaultOpts LocalEnv.empty env (Ref fc Bound var)
         subtypeU True env !(sc defs cl) !(sc' defs cl)
subtypeU _ env x y = convertU env x y

-- The binders of a constructor type which are parameters of the data type:
-- those given as an argument in a parameter position of the return type.
-- Indices count from the outermost binder.
paramBinders : NatSet -> Nat -> Term vs -> List Nat
paramBinders ps depth (Bind _ _ (Pi {}) sc) = paramBinders ps (S depth) sc
paramBinders ps depth tm
    = let (_, args) = getFnArgs tm in
          mapMaybe (\ (i, a) =>
                      if i `elem` ps
                         then case a of
                                   Local _ _ idx _ =>
                                     if idx < depth
                                        then Just (minus depth (S idx))
                                        else Nothing
                                   _ => Nothing
                         else Nothing)
                   (zip [0 .. length args] args)

mutual
  -- The universe of a type
  sortOf : {auto c : Ref Ctxt Defs} ->
           {auto s : Ref UCK UCState} ->
           {vars : _} ->
           Env Term vars -> Term vars -> Core (Maybe Name)
  sortOf env ty
      = do tyty <- infer env ty
           defs <- get Ctxt
           case !(nf defs env tyty) of
                NType _ u => pure (Just u)
                NErased {} => pure Nothing
                t => do gap ("the type " ++ show !(toFullNames ty)
                             ++ " is not in a universe but in "
                             ++ show !(toFullNames !(quote defs env t)))
                        pure Nothing

  -- The type of a global, renaming its polymorphic universes
  -- (A use of a type constructor with an instance renames the universes
  -- of the fields to its instance, and the others to fresh ones; one without
  -- renames only the others.)
  globalType : {auto c : Ref Ctxt Defs} ->
               {auto s : Ref UCK UCState} ->
               NameType -> Name -> ClosedTerm -> Core ClosedTerm
  globalType nt n ty
      = do defs <- get Ctxt
           fn <- canonical n
           let Just sch = lookup fn (schemas (universes defs))
                | Nothing => pure ty
           -- the solved metavariables of the type (the inferred type of a
           -- parameter, say) are part of it, and renamed with it
           ty <- normaliseHoles defs Env.empty ty
           let others = filter (\ p => not (elem p (instOnly sch))) (poly sch)
           ren <- case nt of
                       TyCon _ inst@(_ :: _) =>
                         if length inst == length (instOnly sch)
                            then pure (!(traverse (\ (p, u) => pure (p, !(canonical u)))
                                                  (zip (instOnly sch) inst))
                                       ++ !(traverse (\ p => pure (p, !freshU)) others))
                            else do gap ("the universe instance of " ++ show fn
                                         ++ " does not fit its schema")
                                    pure []
                       TyCon _ [] => traverse (\ p => pure (p, !freshU)) others
                       _ => traverse (\ p => pure (p, !freshU)) (poly sch)
           let renm = fromList ren
           let rn = \ x => fromMaybe x (lookup x renm)
           st <- get UCK
           put UCK ({ edges $= (map (\ e => { lo := rn e.lo, hi := rn e.hi } e)
                                     (edges sch) ++) } st)
           renameLevels renm ty

  -- Infer the type of an elaborated term, recording the constraints
  export
  infer : {auto c : Ref Ctxt Defs} ->
          {auto s : Ref UCK UCState} ->
          {vars : _} ->
          Env Term vars -> Term vars -> Core (Term vars)
  infer env (Local fc r idx p) = pure (binderType (getBinder p env))
  infer env (Ref fc nt n)
      = do defs <- get Ctxt
           Just ty <- lookupTyExact n (gamma defs)
                | Nothing => do gap ("undefined name " ++ show n)
                                pure (Erased fc Placeholder)
           embed <$> globalType nt n ty
  infer env (Meta fc n i args)
      = do defs <- get Ctxt
           Just gdef <- lookupCtxtExact (Resolved i) (gamma defs)
                | Nothing => do gap ("undefined metavariable " ++ show n)
                                pure (Erased fc Placeholder)
           case definition gdef of
                PMDef _ [] (STerm _ sol) _ _ =>
                   -- The type of a solved metavariable is the type of its
                   -- solution: the type it was made with can be out of date
                   -- (with postponed elaboration, for instance), and the
                   -- elaborator does not check solutions against it
                   do ty <- solutionType (fullname gdef) sol
                      inferSpine False (const False) env fc (Meta fc n i []) (embed ty) args
                _ => do checkMeta (Resolved i) gdef
                        inferSpine False (const False) env fc (Meta fc n i []) (embed (type gdef)) args
  infer env tm@(App fc _ _)
      = do let (f, args) = getFnArgs tm
           fty <- infer env f
           inferSpine True (const False) env fc f fty args
  infer env (Bind fc x b sc)
      = do inferPiInfo env b
           case b of
             Pi pfc c p ty =>
                do a <- sortOf env ty
                   b <- sortOf (Pi pfc c p ty :: env) sc
                   piType fc a b
             PVTy pfc c ty =>
                do a <- sortOf env ty
                   b <- sortOf (PVTy pfc c ty :: env) sc
                   piType fc a b
             Lam lfc c p ty =>
                do ignore $ sortOf env ty
                   scty <- infer (b :: env) sc
                   pure (Bind fc x (Pi lfc c p ty) scty)
             Let lfc c val ty =>
                do checkVal env val ty
                   scty <- infer (b :: env) sc
                   pure (Bind fc x (Let lfc c val ty) scty)
             PVar pfc c p ty =>
                do ignore $ sortOf env ty
                   scty <- infer (b :: env) sc
                   pure (Bind fc x (PVTy pfc c ty) scty)
             PLet pfc c val ty =>
                do checkVal env val ty
                   scty <- infer (b :: env) sc
                   pure (Bind fc x (PLet pfc c val ty) scty)
  infer env (As fc s as pat) = infer env pat
  infer env (TDelayed fc r ty)
      = do Just a <- sortOf env ty
                | Nothing => pure (Erased fc Placeholder)
           pure (TType fc a)
  infer env (TDelay fc r ty val)
      = do checkVal env val ty
           pure (TDelayed fc r ty)
  infer env (TForce fc r val)
      = do ty <- infer env val
           defs <- get Ctxt
           case !(nf defs env ty) of
                NDelayed _ _ t => quote defs env t
                NErased {} => pure (Erased fc Placeholder)
                t => do gap ("forcing something which is not delayed: "
                             ++ show !(toFullNames val))
                        pure (Erased fc Placeholder)
  infer env (PrimVal fc (PrT _))
      = do u <- freshU
           pure (TType fc u)
  infer env (PrimVal fc c) = pure (PrimVal fc (PrT (primTypeOf c)))
    where
      primTypeOf : Constant -> PrimType
      primTypeOf (I _) = IntType
      primTypeOf (I8 _) = Int8Type
      primTypeOf (I16 _) = Int16Type
      primTypeOf (I32 _) = Int32Type
      primTypeOf (I64 _) = Int64Type
      primTypeOf (BI _) = IntegerType
      primTypeOf (B8 _) = Bits8Type
      primTypeOf (B16 _) = Bits16Type
      primTypeOf (B32 _) = Bits32Type
      primTypeOf (B64 _) = Bits64Type
      primTypeOf (Str _) = StringType
      primTypeOf (Ch _) = CharType
      primTypeOf (Db _) = DoubleType
      primTypeOf WorldVal = WorldType
      primTypeOf (PrT _) = WorldType -- not reached
  infer env (Erased fc (Dotted t)) = infer env t
  infer env (Erased fc _) = pure (Erased fc Placeholder)
  infer env (TType fc u)
      = do v <- freshU
           addLT u v
           pure (TType fc v)

  piType : {auto c : Ref Ctxt Defs} ->
           {auto s : Ref UCK UCState} ->
           FC -> Maybe Name -> Maybe Name -> Core (Term vars)
  piType fc a b
      = do w <- freshU
           whenJust a $ \ a => addLE a w
           whenJust b $ \ b => addLE b w
           pure (TType fc w)

  inferPiInfo : {auto c : Ref Ctxt Defs} ->
                {auto s : Ref UCK UCState} ->
                {vars : _} ->
                Env Term vars -> Binder (Term vars) -> Core ()
  inferPiInfo env b
      = case piInfo b of
             DefImplicit t => checkVal env t (binderType b)
             _ => pure ()

  -- Check that 'val' has type 'ty' (cumulatively)
  checkVal : {auto c : Ref Ctxt Defs} ->
             {auto s : Ref UCK UCState} ->
             {vars : _} ->
             Env Term vars -> Term vars -> Term vars -> Core ()
  checkVal env val ty
      = do ignore $ sortOf env ty
           valty <- infer env val
           defs <- get Ctxt
           subtypeU True env !(nf defs env valty) !(nf defs env ty)

  -- The arguments of an application. With 'cumul' False, the types of the
  -- arguments have to be in the same universes as those of the function.
  -- 'lhs' says which arguments (by position) are patterns of a left hand
  -- side that match at run time (see 'inferPat').
  inferSpine : {auto c : Ref Ctxt Defs} ->
               {auto s : Ref UCK UCState} ->
               {vars : _} ->
               (cumul : Bool) -> (lhs : Nat -> Bool) ->
               Env Term vars -> FC -> (fn : Term vars) -> Term vars ->
               List (Term vars) -> Core (Term vars)
  inferSpine cumul lhs env fc fn fty [] = pure fty
  inferSpine cumul lhs env fc fn fty args
      = do defs <- get Ctxt
           go 0 !(nf defs env fty) args
    where
      go : Nat -> NF vars -> List (Term vars) -> Core (Term vars)
      go _ fty [] = do defs <- get Ctxt
                       quote defs env fty
      go i (NBind _ _ (Pi _ _ _ aty) sc) (a :: as)
          = do defs <- get Ctxt
               aT <- if cumul then infer env a else inferPat (lhs i) env a
               catch (subtypeU cumul env !(nf defs env aT) !(evalClosure defs aty))
                     (\ err => case err of
                                     GenericMsg efc msg =>
                                       throw (GenericMsg efc (msg ++ "\n(in the argument "
                                                 ++ show !(toFullNames a) ++ " of "
                                                 ++ show !(toFullNames fn) ++ ")"))
                                     _ => throw err)
               go (S i) !(sc defs (toClosure defaultOpts env a)) as
      go i (NErased {}) (a :: as)
          = do ignore $ the (Core (Term vars))
                          (if cumul then infer env a else inferPat (lhs i) env a)
               go (S i) (NErased fc Placeholder) as
      go _ t (a :: _)
          = do defs <- get Ctxt
               gap ("applying something whose type is not a function type: "
                    ++ show !(toFullNames !(quote defs env t)))
               pure (Erased fc Placeholder)

  -- Patterns, on the left hand side of a clause: the types of the pattern
  -- variables are what the constructors say, not something smaller, so
  -- the universes in applications have to be equal.
  --
  -- With 'lhs', the term is a pattern of a left hand side, and a pattern
  -- which matches on a type (a type constructor applied to patterns, or a
  -- function type) gets the variables it binds no smaller than the
  -- universe of the type it matches. The universes of the type which is
  -- matched at run time are not those of the pattern: `elemOf (Seq a) = a`
  -- can be given `Seq X` for any X up to the universe of the argument of
  -- elemOf, so `a` has to be in that universe, or elemOf would take a type
  -- out of a universe into a smaller one (and `elemOf (Seq Type)` would be
  -- a `Type` in its own universe). The arguments of a constructor pattern
  -- which are parameters of its data type (`Right {a = OneOf es p} x`) don't
  -- match anything at run time: they are given by the type of the value
  -- matched, which is made equal to the pattern's.
  inferPat : {auto c : Ref Ctxt Defs} ->
             {auto s : Ref UCK UCState} ->
             {vars : _} ->
             (lhs : Bool) -> Env Term vars -> Term vars -> Core (Term vars)
  inferPat lhs env tm@(App fc _ _)
      = do let (f, args) = getFnArgs tm
           fty <- infer env f
           ps <- the (Core (List Nat)) (if lhs then conParams f else pure [])
           rty <- inferSpine False (\ i => lhs && not (any (== i) ps)) env fc f fty args
           when (lhs && isTyCon f) $
             do defs <- get Ctxt
                case !(nf defs env rty) of
                     NType _ w => traverse_ (bindsAbove env w) args
                     _ => pure ()
           pure rty
    where
      isTyCon : Term vars -> Bool
      isTyCon (Ref _ (TyCon {}) _) = True
      isTyCon _ = False

      -- The positions of the arguments of a data constructor which are
      -- parameters of its data type
      conParams : Term vars -> Core (List Nat)
      conParams (Ref _ (DataCon {}) cn)
          = do defs <- get Ctxt
               Just cty <- lookupTyExact cn (gamma defs)
                    | Nothing => pure []
               let Just tn = retHead cty
                    | Nothing => pure []
               Just tdef <- lookupCtxtExact tn (gamma defs)
                    | Nothing => pure []
               let TCon _ ps _ _ _ _ _ = definition tdef
                    | _ => pure []
               pure (paramBinders ps 0 cty)
        where
          retHead : Term vs -> Maybe Name
          retHead (Bind _ _ (Pi {}) sc) = retHead sc
          retHead tm = case getFnArgs tm of
                            (Ref _ _ n, _) => Just n
                            _ => Nothing
      conParams _ = pure []
  inferPat True env tm@(Bind fc x b@(Pi _ _ _ ty) sc)
      = do rty <- infer env tm
           defs <- get Ctxt
           case !(nf defs env rty) of
                NType _ w =>
                  do whenJust !(sortOf env ty) $ \ a => addLE w a
                     whenJust !(sortOf (b :: env) sc) $ \ a => addLE w a
                _ => pure ()
           pure rty
  inferPat lhs env (As _ _ _ p) = inferPat lhs env p
  inferPat lhs env tm = infer env tm

  -- The universes in the type of an argument of a type pattern are no
  -- smaller than the universe 'w' of the type matched (see 'inferPat')
  bindsAbove : {auto c : Ref Ctxt Defs} ->
               {auto s : Ref UCK UCState} ->
               {vars : _} ->
               Env Term vars -> Name -> Term vars -> Core ()
  bindsAbove env w a
      = do aty <- infer env a
           defs <- get Ctxt
           aty <- quote defs env !(nf defs env aty)
           traverse_ (addLE w) (levelsOf aty [])

  solutionType : {auto c : Ref Ctxt Defs} ->
                 {auto s : Ref UCK UCState} ->
                 Name -> ClosedTerm -> Core ClosedTerm
  solutionType n sol
      = do st <- get UCK
           case lookup n (metaTypes st) of
                Just ty => pure ty
                Nothing =>
                  do ty <- infer Env.empty sol
                     update UCK { metaTypes $= insert n ty }
                     pure ty

  -- Check the solution of a metavariable against its type, once. The
  -- elaborator does not check the type of a solution, so this is where
  -- the universes of the solution meet those of the metavariable's type.
  checkMeta : {auto c : Ref Ctxt Defs} ->
              {auto s : Ref UCK UCState} ->
              Name -> GlobalDef -> Core ()
  checkMeta n gdef
      = do defs <- get Ctxt
           let fn = fullname gdef
           case definition gdef of
                PMDef _ [] (STerm _ tm) _ _ =>
                   do let False = isJust (lookup fn (checkedMetas (universes defs)))
                            | True => pure ()
                      update Ctxt { universes->checkedMetas $= insert fn (),
                                    universes->pendingMetas $= delete fn }
                      checkVal Env.empty tm (type gdef)
                None => pure () -- nothing to check yet
                _ => do update Ctxt { universes->pendingMetas $= insert fn () }
                        update UCK { sawPending := True }

||| Say which universe a universe name stands for, for error messages
showLevel : {auto c : Ref Ctxt Defs} -> Name -> Core String
showLevel n@(MN "ucheck" _) = pure "an inferred universe"
showLevel n
    = do defs <- get Ctxt
         Just gdef <- lookupCtxtExact n (gamma defs)
              | Nothing => pure (show n)
         pure ("the universe of `Type` at " ++ show (location gdef))

||| The error for a cycle with a strict edge
export
cycleError : {auto c : Ref Ctxt Defs} -> FC -> List UEdge -> Core Error
cycleError fc es
    = do ls <- traverse showEdge es
         pure (UniverseInconsistency fc ls)
  where
    showEdge : UEdge -> Core String
    showEdge e
        = pure $ !(showLevel e.lo) ++ (if e.strict then " < " else " <= ")
                 ++ !(showLevel e.hi) ++ " (from " ++ show e.origin ++ ")"

||| Add constraints to the graph of the module, failing if they make it
||| inconsistent. 'keep' says whether they go into the module's TTC.
export
addUConstraints : {auto c : Ref Ctxt Defs} ->
                  FC -> (keep : Bool) -> List UEdge -> Core ()
addUConstraints fc keep es
    = do defs <- get Ctxt
         case addUEdges es (graph (universes defs)) of
              Left cycle => throw !(cycleError fc cycle)
              Right g => put Ctxt (newInfo g defs)
  where
    newInfo : UGraph -> Defs -> Defs
    newInfo g defs
        = let info = universes defs
              saved' : List UEdge
              saved' = if keep then es ++ info.saved else info.saved in
              { universes := { graph := g, saved := saved' } info } defs

||| Add the universe information of an imported module
export
addImportedUniverses : {auto c : Ref Ctxt Defs} ->
                       FC -> List UEdge -> List Name -> List (Name, USchema) ->
                       List (Name, Name) -> Core ()
addImportedUniverses fc es fs schs owners
    = do addUConstraints fc False es
         update Ctxt { universes->fixed $= insertFrom (map (\ n => (n, ())) fs),
                       universes->schemas $= insertFrom schs,
                       universes->typeOwner $= \ m => foldl (\ m, (l, o) => addOwner o m l) m owners }

runCheck : {auto c : Ref Ctxt Defs} ->
           FC -> Name -> (Ref UCK UCState -> Core ()) -> Core ()
runCheck fc origin act
    = do origin <- getFullName origin
         defs0 <- get Ctxt
         let starts = defStart (universes defs0)
         when (isNothing (lookup origin starts)) $
           put Ctxt ({ universes->defStart := insert origin (completions (universes defs0)) starts } defs0)
         s <- newRef UCK (MkUCState origin fc 0 [] False False empty)
         act s
         st <- get UCK
         -- Check with every edge, to have the whole cycle in an error
         defs <- get Ctxt
         case addUEdges (edges st) (graph (universes defs)) of
              Left cycle => throw !(cycleError fc cycle)
              Right _ => pure ()
         let es = projectUEdges isLocalU origin (edges st)
         addUConstraints fc True es
         defs <- get Ctxt
         let m = defEdges (universes defs)
         let (old, p) = fromMaybe ([], False) (lookup origin m)
         let ics = incompleteDefs (universes defs)
         let ics' : List Name = if incomplete st then origin :: ics else ics
         put Ctxt ({ universes->defEdges := insert origin (es ++ old, p || sawPending st || incomplete st) m,
                     universes->incompleteDefs := ics' } defs)

whenChecking : {auto c : Ref Ctxt Defs} -> Core () -> Core ()
whenChecking act
    = do sess <- getSession
         when (checkUniverses sess) act

-- A definition has been checked completely: make it polymorphic in the
-- universes of its type ('extra' are further universes of its type, for
-- data constructors) which are not fixed. Of these, those in 'instOnly' (the
-- universes in the fields of a data type) are renamed only through a
-- universe instance of a type constructor (see 'globalType').
complete : {auto c : Ref Ctxt Defs} ->
           (constraintsOf : Name) -> (owners : List Name) -> Name -> List Name ->
           (instOnly : List Name) -> Core ()
complete cn owners n extra instOnly
    = do defs <- get Ctxt
         fn <- getFullName n
         fcn <- getFullName cn
         Just ty <- lookupTyExact n (gamma defs)
              | Nothing => pure ()
         -- the solved metavariables of the type are renamed with it (see
         -- 'globalType')
         ty <- normaliseHoles defs Env.empty ty
         tyls <- canonicalLevels ty
         -- what evaluating the type can produce can't be renamed either
         tyfixed <- metaLevels ty
         let info = universes defs
         let (es, pending) = fromMaybe ([], False) (lookup fcn (defEdges info))
         owners <- traverse getFullName owners
         let start = fromMaybe (completions (universes defs)) (lookup fcn (defStart (universes defs)))
         let ps = nub (filter (\ u => not (isJust (lookup u (fixed info)))
                                     && not (elem u tyfixed)
                                     && ownedBy info start owners u (lookup u (typeOwner info)))
                              (tyls ++ extra))
         log "universe" 5 $ "Universes of " ++ show fn ++ ": " ++ show tyls
                ++ "; polymorphic in " ++ show ps
                ++ (if pending then " (but met an unsolved metavariable)" else "")
         unless (pending || null ps) $
           do let stamp = completions info
              let sch = MkUSchema ps (filter (touches ps) es) (filter (\ u => elem u instOnly) ps) stamp
              update Ctxt { universes->completions := stamp + 1,
                            universes->schemas $= insert fn sch,
                            universes->savedSchemas $= ((fn, sch) ::) }
  where
    -- A universe in the type of another definition is not renamed: that
    -- definition's own constraints on it are not in this one's
    -- A universe in the type of another definition can be renamed only if
    -- that definition is polymorphic in it and was complete before this one
    -- was started (so this one only used it through renamed copies);
    -- otherwise that definition's own constraints on it are not in this
    -- one's
    ownedBy : UniverseInfo -> Int -> List Name -> Name -> Maybe (List Name) -> Bool
    ownedBy info start os u Nothing = True
    ownedBy info start os u (Just ts) = all ok ts
      where
        ok : Name -> Bool
        ok t = elem t os ||
               case lookup t (schemas info) of
                    Just sch => elem u (poly sch) && stamp sch < start
                    Nothing => False

    touches : List Name -> UEdge -> Bool
    touches ps e = elem e.lo ps || elem e.hi ps

checkPendingMetas : {auto c : Ref Ctxt Defs} ->
                    {auto s : Ref UCK UCState} ->
                    Core ()
checkPendingMetas
    = do defs <- get Ctxt
         traverse_ check (keys (pendingMetas (universes defs)))
  where
    check : Name -> Core ()
    check n
        = do defs <- get Ctxt
             Just gdef <- lookupCtxtExact n (gamma defs)
                  | Nothing => pure ()
             checkMeta n gdef

||| Check the type of a global definition
export
checkTypeUniverses : {auto c : Ref Ctxt Defs} ->
                     FC -> Name -> ClosedTerm -> Core ()
checkTypeUniverses fc n ty
    = whenChecking $
        do addTypeOwner n ty
           runCheck fc n $ \ s => ignore $ sortOf Env.empty ty

||| Check that two types given to the same name (a forward declaration and
||| the definition) have the same universes
export
checkSameTypeUniverses : {auto c : Ref Ctxt Defs} ->
                         FC -> Name -> ClosedTerm -> ClosedTerm -> Core ()
checkSameTypeUniverses fc n ty ty'
    = whenChecking $ runCheck fc n $ \ s =>
          do defs <- get Ctxt
             convertU Env.empty !(nf defs Env.empty ty) !(nf defs Env.empty ty')

||| Check the clauses of a definition by pattern matching
export
checkClauseUniverses : {auto c : Ref Ctxt Defs} ->
                       FC -> Name ->
                       List (vs ** (Env Term vs, Term vs, Term vs)) -> Core ()
checkClauseUniverses fc n pats
    = whenChecking $
        do runCheck fc n $ \ s => traverse_ checkClause pats
           -- Evaluation can produce the universes in the right hand sides
           -- (and in the values of let bindings in the environment)
           addFixed . nub . concat =<< traverse bodyLevels pats
           -- The universes of the left hand sides (and of the types of the
           -- pattern variables) are this definition's own, so they are
           -- renamed too
           lhsls <- nub . concat <$> traverse lhsLevels pats
           complete n [n] n lhsls []
  where
    checkEnv : {vs : _} -> {auto s : Ref UCK UCState} ->
               Env Term vs -> Core ()
    checkEnv [] = pure ()
    checkEnv (b :: env)
        = do checkEnv env
             case b of
                  Let _ _ val ty => checkVal env val ty
                  PLet _ _ val ty => checkVal env val ty
                  _ => ignore $ sortOf env (binderType b)

    envLevels : Env Term vs -> List Name -> List Name
    envLevels [] acc = acc
    envLevels (Let _ _ val ty :: env) acc
        = levelsOf val (levelsOf ty (envLevels env acc))
    envLevels (PLet _ _ val ty :: env) acc
        = levelsOf val (levelsOf ty (envLevels env acc))
    envLevels (_ :: env) acc = envLevels env acc

    envTypeLevels : Env Term vs -> List Name -> List Name
    envTypeLevels [] acc = acc
    envTypeLevels (b :: env) acc = levelsOf (binderType b) (envTypeLevels env acc)

    lhsLevels : (vs ** (Env Term vs, Term vs, Term vs)) -> Core (List Name)
    lhsLevels (_ ** (env, lhs, rhs))
        = do ls <- traverse canonical (levelsOf lhs (envTypeLevels env []))
             ms <- metaLevels lhs
             pure (filter (\ l => not (elem l ms)) ls)

    bodyLevels : (vs ** (Env Term vs, Term vs, Term vs)) -> Core (List Name)
    bodyLevels (_ ** (env, lhs, rhs))
        = do els <- traverse canonical (envLevels env [])
             pure (els ++ !(evalLevels rhs))

    checkClause : {auto s : Ref UCK UCState} ->
                  (vs ** (Env Term vs, Term vs, Term vs)) -> Core ()
    checkClause (_ ** (env, lhs, rhs))
        = do checkEnv env
             lhsty <- inferPat True env lhs
             rhsty <- infer env rhs
             defs <- get Ctxt
             subtypeU True env !(nf defs env rhsty) !(nf defs env lhsty)

-- The universe at the end of the type of a type constructor
resultUniverse : {auto c : Ref Ctxt Defs} ->
                 {vars : _} ->
                 Env Term vars -> NF vars -> Core (Maybe Name)
resultUniverse env (NBind fc x b@(Pi {}) sc)
    = do defs <- get Ctxt
         resultUniverse env !(sc defs (toClosure defaultOpts env (Erased fc Placeholder)))
resultUniverse env (NType _ u) = pure (Just u)
resultUniverse env _ = pure Nothing

-- The universes in the fields of a constructor (not in its parameters)
fieldLevels : List Nat -> Nat -> Term vs -> List Name -> List Name
fieldLevels params i (Bind _ _ (Pi _ _ _ ty) sc) acc
    = fieldLevels params (S i) sc
          (if i `elem` params then acc else levelsOf ty acc)
fieldLevels params i tm acc = levelsOf tm acc

||| Check a data type: the type of its type constructor, the types of its
||| constructors, and that each field of a constructor is in a universe no
||| bigger than the data type's.
export
checkDataUniverses : {auto c : Ref Ctxt Defs} ->
                     FC -> Name -> ClosedTerm -> List (Name, ClosedTerm) ->
                     Core ()
checkDataUniverses fc tn tty_in cons_in
    = whenChecking $
        do defs <- get Ctxt
           -- the solved metavariables of the types are part of them (see
           -- 'globalType')
           tty <- normaliseHoles defs Env.empty tty_in
           cons <- traverse (\ (cn, cty) => pure (cn, !(normaliseHoles defs Env.empty cty))) cons_in
           Just tdef <- lookupCtxtExact tn (gamma defs)
                | Nothing => throw (InternalError "Universe check: undefined data type")
           let TCon _ ps _ _ _ _ _ = definition tdef
                | _ => throw (InternalError "Universe check: not a type constructor")
           addTypeOwner tn tty
           traverse_ (\ (cn, cty) => addTypeOwner cn cty) cons
           runCheck fc tn $ \ s =>
             do ignore $ sortOf Env.empty tty
                defs <- get Ctxt
                case !(resultUniverse Env.empty !(nf defs Env.empty tty)) of
                     Nothing => gap "the type of the data type does not end in a universe"
                     Just u => traverse_ (checkCon u ps) cons
           -- What evaluating the types of the constructors can produce is
           -- fixed
           addFixed . nub . concat =<< traverse (\ (_, cty) => metaLevels cty) cons
           -- The universes in the fields: the contents of the data type. A
           -- use of the type constructor says at which universes they are
           -- (its universe instance, see TyCon in Core.TT.Term), and a
           -- conversion between two uses makes them equal, so they are
           -- renamed only through an instance
           fieldls <- nub . concat <$>
                        traverse (\ (_, cty) =>
                                    traverse canonical
                                      (fieldLevels (paramBinders ps 0 cty) 0 cty []))
                                 cons
           -- The universes of the type constructor and of the constructors
           -- are renamed together (the parameters' are made equal)
           tyls <- canonicalLevels tty
           conls <- concat <$> traverse (\ (_, cty) => canonicalLevels cty) cons
           let famls = tyls ++ conls
           let family = tn :: map fst cons
           complete tn family tn famls fieldls
           traverse_ (\ (cn, _) => complete tn family cn famls fieldls) cons
           -- If the data type is not polymorphic, its uses have no instance,
           -- and the contents are fixed, as they are the same at every use
           defs <- get Ctxt
           ftn <- getFullName tn
           when (isNothing (lookup ftn (schemas (universes defs)))) $
             addFixed fieldls
  where
    -- The return type `T a1 ... an` of a constructor. The universes of a
    -- parameter are those of the data type's type (they are made equal, so
    -- that the data type and its constructors are renamed together). An
    -- index can be in a universe below that of the data type's argument
    -- (cumulativity, as anywhere else in a term): an index is not stored in
    -- the value, so it does not count in the universe of the data type,
    -- whose fields are bounded on their own (see 'fields').
    retType : {vs : _} -> {auto s : Ref UCK UCState} ->
              NatSet -> Env Term vs -> Term vs -> Core ()
    retType ps env ret
        = do let (f, args) = getFnArgs ret
             fty <- infer env f
             defs <- get Ctxt
             go 0 !(nf defs env fty) args
      where
        go : Nat -> NF vs -> List (Term vs) -> Core ()
        go i (NBind _ _ (Pi _ _ _ aty) sc) (a :: as)
            = do defs <- get Ctxt
                 let param = i `elem` ps
                 aT <- if param then inferPat False env a else infer env a
                 subtypeU (not param) env !(nf defs env aT) !(evalClosure defs aty)
                 go (S i) !(sc defs (toClosure defaultOpts env a)) as
        go _ _ [] = pure ()
        go _ _ _ = gap "the return type of a constructor is not an application of its data type"

    fields : {vs : _} -> {auto s : Ref UCK UCState} ->
             NatSet -> Name -> List Nat -> Nat -> Env Term vs -> Term vs -> Core ()
    fields ps u params i env (Bind _ x b@(Pi _ _ _ ty) sc)
        = do unless (i `elem` params) $
               whenJust !(sortOf env ty) $ \ a => addLE a u
             fields ps u params (S i) (b :: env) sc
    fields ps u params i env ret = retType ps env ret

    checkCon : {auto s : Ref UCK UCState} ->
               Name -> NatSet -> (Name, ClosedTerm) -> Core ()
    checkCon u ps (cn, cty)
        = do ignore $ sortOf Env.empty cty
             fields ps u (paramBinders ps 0 cty) 0 Env.empty cty

||| At the end of a module: check the solutions of the metavariables which
||| were unsolved when a definition using them was checked, and warn about
||| the imports whose universe constraints are not known.
export
finishModuleUniverses : {auto c : Ref Ctxt Defs} -> FC -> Core ()
finishModuleUniverses fc
    = whenChecking $
        do runCheck fc (UN (Basic "<module>")) $ \ s => checkPendingMetas
           defs <- get Ctxt
           let ics = nub (incompleteDefs (universes defs))
           unless (null ics) $
             recordWarning (UniverseIncomplete fc ics)
           let ms = nub (uncheckedImports (universes defs))
           unless (null ms) $
             recordWarning (UniverseUncheckedImports fc ms)

||| When checking universes, give the universes in the type of a global a
||| fresh name at each use the elaborator makes of it. The elaborator does not
||| care about universes, but it copies parts of the types it uses into the
||| terms it builds (in the solutions of metavariables, for instance), and
||| copying the global's own universe names into another definition would
||| make the uses of the global share them, defeating universe polymorphism.
-- A fresh name for a copy of a universe. These names are not added to the
-- context: elaboration backtracks by restoring the context, and a copy could
-- outlive its definition. The counter is in an IORef so that restoring the
-- context does not reuse a name.
freshCopy : {auto c : Ref Ctxt Defs} -> Name -> Core (Name, Name)
freshCopy l
    = do defs <- get Ctxt
         i <- coreLift $ readIORef (ufresh defs)
         coreLift $ writeIORef (ufresh defs) (i + 1)
         n <- inModuleNS (MN "uf" i)
         pure (l, n)

-- Rename the universes in a term: with 'ren' for those it renames, to fresh
-- names for the others
freshenWith : {auto c : Ref Ctxt Defs} ->
              NameMap Name -> Term vars -> Core (Term vars)
freshenWith ren tm
    = do ls <- canonicalLevels tm
         let new = filter (\ l => isNothing (lookup l ren)) ls
         if null new && null (NameMap.toList ren) then pure tm else
           do fs <- traverse freshCopy new
              renameLevels (insertFrom fs ren) tm

export
freshenLevels : {auto c : Ref Ctxt Defs} ->
                Term vars -> Core (Term vars)
freshenLevels tm
    = do sess <- getSession
         if not (checkUniverses sess) then pure tm else freshenWith empty tm

||| When checking universes, the elaborator's use of a global: a fresh
||| universe instance for a type constructor (whose universe schema is
||| known), and its type with these universes and fresh ones for the others
||| (see 'freshenLevels'). Without the option, the use and the type as they
||| are.
export
freshenUse : {auto c : Ref Ctxt Defs} ->
             NameType -> Name -> ClosedTerm -> Core (NameType, ClosedTerm)
freshenUse nt n ty
    = do sess <- getSession
         if not (checkUniverses sess) then pure (nt, ty) else
           case nt of
                TyCon a [] =>
                  do defs <- get Ctxt
                     fn <- canonical n
                     case lookup fn (schemas (universes defs)) of
                          Nothing => pure (nt, !(freshenWith empty ty))
                          Just (MkUSchema _ _ [] _) => pure (nt, !(freshenWith empty ty))
                          Just sch =>
                            do inst <- traverse freshCopy (instOnly sch)
                               ty' <- freshenWith (fromList inst) ty
                               pure (TyCon a (map snd inst), ty')
                _ => pure (nt, !(freshenWith empty ty))

||| When checking universes, give each binder of a declared type whose type
||| is a universe (`{0 a : Type}`) a universe of its own. The elaborator
||| infers the type of an implicitly bound type variable by unification, so
||| in `empty : f a` the type of `a` is the very universe of the domain of
||| `f`, where the use `f a` needs only `a`'s universe to be no bigger
||| (which the universe checker checks, cumulatively). Without this, an
||| implementation of the interface would need its methods at a type variable
||| as big as the domain of `f`, which can be bigger than what the
||| implementation's data type can store (the index universe of `Elab` is
||| above `Elab`'s own, because of `Join`). Without the option, the type as
||| it is.
export
decoupleBinderUniverses : {auto c : Ref Ctxt Defs} ->
                          Term vars -> Core (Term vars)
decoupleBinderUniverses tm
    = do sess <- getSession
         if not (checkUniverses sess) then pure tm else go tm
  where
    go : Term vs -> Core (Term vs)
    go (Bind fc x (Pi pfc c p (TType tfc u)) sc)
        = do (_, u') <- freshCopy u
             pure (Bind fc x (Pi pfc c p (TType tfc u')) !(go sc))
    go (Bind fc x b sc)
        = pure (Bind fc x !(traverse go b) !(go sc))
    go (App fc f a) = pure (App fc !(go f) !(go a))
    go t = pure t

||| The type of a global, with fresh universe names when checking universes
||| (see 'freshenLevels')
export
lookupTyFresh : {auto c : Ref Ctxt Defs} ->
                Name -> Context -> Core (Maybe ClosedTerm)
lookupTyFresh n gam
    = do Just ty <- lookupTyExact n gam
              | Nothing => pure Nothing
         Just <$> freshenLevels ty
