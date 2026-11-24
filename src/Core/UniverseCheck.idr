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
||| Universe polymorphism. Every definition checked completely is universe
||| polymorphic: a reference to it with a universe instance (Func and TyCon
||| in NameType) stands for the copy of it whose universes (those of its
||| universe schema) are renamed to the instance. The elaborator gives each
||| reference a fresh instance ('freshenUse'), the checker types it with the
||| definition's type renamed so and copies the definition's constraints
||| renamed ('globalType'), unfolding it gives the definition's body renamed
||| so (Core.UniverseInst), and conversion makes the instances of two
||| references to the same definition equal (Core.Normalise.Convert). The
||| schema of a function covers the universes of its type and clauses, those
||| of the instances of the references in them included ('completeGroup'),
||| fewer those which another definition has too, and fewer again by
||| 'minimise'; that of a data type covers the universes of its fields
||| (renamed only through an instance, 'instOnly'), and the others are renamed
||| afresh at each use. A reference without an instance stands for the
||| definition's own universes. A definition and the definitions lifted out of
||| it, an implementation and its methods, and a mutual block are one group,
||| which shares a schema: references within it have no instance, and are
||| renamed with the definition they are in. A definition is used with its own
||| universes until it has been checked completely, and so are definitions
||| which met an unsolved metavariable or something the check could not handle
||| (see 'gap'). docs/source/reference/universes.rst says why this is sound.
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
import Core.UniverseInst
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
levelsOf (Ref _ (Func inst) _) acc = inst ++ acc
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
canonicalLevels tm = nubNames <$> traverse canonical (levelsOf tm [])

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
evalLevels tm = nubNames <$> evalLevelsFrom True tm

||| The universes in the solutions of the metavariables in a term
metaLevels : {auto c : Ref Ctxt Defs} -> Term vars -> Core (List Name)
metaLevels tm = nubNames <$> evalLevelsFrom False tm

-- Rename universes ('ren' is by canonical name), also in the instances of
-- references (see Core.UniverseInst)
renameLevels : {auto c : Ref Ctxt Defs} ->
               NameMap Name -> Term vars -> Core (Term vars)
renameLevels ren tm
    = do defs <- get Ctxt
         renameUnivs defs (mkURename (gamma defs) False (NameMap.toList ren)) tm

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

-- Record that universes belong to a definition (they are in its type or its
-- clauses)
addOwners : {auto c : Ref Ctxt Defs} -> Name -> List Name -> Core ()
addOwners n ls
    = do fn <- getFullName n
         update Ctxt { universes->typeOwner $= \ m => foldl (addOwner fn) m ls,
                       universes->savedTypeOwner $= (map (\ l => (l, fn)) ls ++) }

-- Record which definition's type the universes of a type belong to (those
-- in the solutions of its metavariables too)
addTypeOwner : {auto c : Ref Ctxt Defs} -> Name -> ClosedTerm -> Core ()
addTypeOwner n ty = addOwners n !(evalLevels ty)

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

  -- The type of a global, renaming its polymorphic universes, and the
  -- constraints of its schema with them. A reference to a function with a
  -- universe instance renames them to the instance; one without stands for
  -- the function's own universes, and renames nothing. A use of a type
  -- constructor with an instance renames the universes of the fields to its
  -- instance, and the others to fresh ones; one without renames only the
  -- others. A constructor renames them all to fresh ones.
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
           ren <- the (Core (List (Name, Name))) $ case nt of
                       TyCon _ inst@(_ :: _) =>
                         if length inst == length (instOnly sch)
                            then pure (!(traverse (\ (p, u) => pure (p, !(canonical u)))
                                                  (zip (instOnly sch) inst))
                                       ++ !(traverse (\ p => pure (p, !freshU)) others))
                            else do gap ("the universe instance of " ++ show fn
                                         ++ " does not fit its schema")
                                    pure []
                       TyCon _ [] => traverse (\ p => pure (p, !freshU)) others
                       Func [] => if bodyFree sch
                                     then traverse (\ p => pure (p, !freshU)) (poly sch)
                                     else pure []
                       Func inst =>
                         if length inst == length (poly sch) && null (instOnly sch)
                            then traverse (\ (p, u) => pure (p, !(canonical u)))
                                          (instPairs sch inst)
                            else do gap ("the universe instance of " ++ show fn
                                         ++ " does not fit its schema")
                                    pure []
                       _ => traverse (\ p => pure (p, !freshU)) (poly sch)
           let False = null ren
                | True => pure ty
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
                       -- a schema is saved once for its group
                       universes->schemas $= insertFrom (concatMap (\ (n, s) => (n, s) :: map (\ m => (m, s)) s.group) schs),
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
              let sch = MkUSchema ps (filter (touches ps) es) (filter (\ u => elem u instOnly) ps) stamp [] [] False
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

||| Check that two types given to the same name (a forward declaration and
||| the definition) have the same universes
export
checkSameTypeUniverses : {auto c : Ref Ctxt Defs} ->
                         FC -> Name -> ClosedTerm -> ClosedTerm -> Core ()
checkSameTypeUniverses fc n ty ty'
    = whenChecking $ runCheck fc n $ \ s =>
          do defs <- get Ctxt
             convertU Env.empty !(nf defs Env.empty ty) !(nf defs Env.empty ty')

-- Classes of universes, with each universe mapped straight to the
-- representative of its class
record UClasses where
  constructor MkUClasses
  repOf : NameMap Name
  members : NameMap (List Name)

findRep : UClasses -> Name -> Name
findRep cl n = fromMaybe n (lookup n cl.repOf)

-- Put the class of 'b' into the class of 'a' (whose representative stays)
mergeInto : Name -> Name -> UClasses -> UClasses
mergeInto a b cl
    = let ra = findRep cl a
          rb = findRep cl b in
          if ra == rb then cl else
            let ms = fromMaybe [rb] (lookup rb cl.members)
                ma = fromMaybe [ra] (lookup ra cl.members) in
                MkUClasses (foldl (\ m, x => insert x ra m) cl.repOf ms)
                           (insert ra (ms ++ ma) (delete rb cl.members))

-- The universes of a function which its copies rename: the universes 'ps'
-- of its types and clauses, fewer. Each universe which is made equal to
-- another one goes with it, and each universe which is not in the types of
-- the definitions ('keep') and has one lower bound, which it may equal, is
-- set to it in the copies. (One without a lower bound is not set to the
-- lowest universe: `T = Type` would then be `Type` of the lowest universe
-- in every copy, so not polymorphic.) Then the universes which no
-- constraint connects, through universes of the definition, to a universe of
-- its type are not renamed at all: the copies share them (they are in the
-- body only, and mostly in the instances of the references there, which
-- would otherwise make the universes of a definition all those of the
-- definitions it uses).
-- This keeps the instances small: a reference inside a function to another
-- function has an instance of the other's universes, and they would all be
-- the first function's universes too. Sound because setting universes of a
-- definition to values which satisfy the constraints on them gives a copy of
-- it (all its constraints hold for the copy), and the definition's own
-- universes (a reference without an instance) are not changed.
-- Returns the universes renamed by an instance, those which follow one of
-- them or are set to a universe which is not renamed, and the constraints
-- on them.
minimise : (keep : NameMap ()) -> List Name -> List UEdge ->
           (List Name, List (Name, Name), List UEdge)
minimise keep ps es
    = let psSet = nameSet ps
          leq = foldl (\ m, e => if e.strict then m
                                       else insert e.lo (insert e.hi () (fromMaybe empty (lookup e.lo m))) m)
                      (the (NameMap (NameMap ())) empty) es
          eqs = filter (\ e => not e.strict && isJust (lookup e.lo psSet) && isJust (lookup e.hi psSet)
                               && maybe False (\ s => isJust (lookup e.lo s)) (lookup e.hi leq))
                       es
          cl0 = foldl union (MkUClasses empty empty) eqs
          cl = lowerAll (the Nat 0) cl0
          reps0 = filter (\ u => findRep cl u == u) ps
          reps0Set = nameSet reps0
          mapped = mapMaybe (mapEdge cl) es
          adj = foldl (\ m, e => if isJust (lookup e.lo reps0Set) && isJust (lookup e.hi reps0Set)
                                     then insert e.lo (e.hi :: fromMaybe [] (lookup e.lo m))
                                            (insert e.hi (e.lo :: fromMaybe [] (lookup e.hi m)) m)
                                     else m)
                      (the (NameMap (List Name)) empty) mapped
          reached = reach adj (filter (\ u => isJust (lookup u keep)) reps0) empty
          reps = filter (\ u => isJust (lookup u reached)) reps0
          repSet = nameSet reps
          as = mapMaybe (\ u => let r = findRep cl u in
                                    if r == u then Nothing else Just (u, r)) ps
          es' = dedup (filter (\ e => isJust (lookup e.lo repSet) || isJust (lookup e.hi repSet))
                              mapped) in
          (reps, as, es')
  where
    -- the universes connected to the given ones
    reach : NameMap (List Name) -> List Name -> NameMap () -> NameMap ()
    reach adj [] seen = seen
    reach adj (u :: us) seen
        = if isJust (lookup u seen) then reach adj us seen
             else reach adj (fromMaybe [] (lookup u adj) ++ us) (insert u () seen)

    -- the representative of a class with a universe of 'keep' is one of them
    union : UClasses -> UEdge -> UClasses
    union cl e
        = let a = findRep cl e.lo
              b = findRep cl e.hi in
              if isJust (lookup b keep) then mergeInto b a cl else mergeInto a b cl

    -- the one lower bound of a class (from outside it), if it has exactly one
    -- and it is not strict
    oneLower : UClasses -> Name -> List (Name, Bool) -> Maybe Name -> Maybe Name
    oneLower cl u [] acc = acc
    oneLower cl u ((l, st) :: ls) acc
        = let l' = findRep cl l in
              if l' == u then oneLower cl u ls acc
              else if st then Nothing
              else case acc of
                        Nothing => oneLower cl u ls (Just l')
                        Just a => if a == l' then oneLower cl u ls acc else Nothing

    -- one round of setting classes to their lower bound
    lowerRound : UClasses -> (Bool, UClasses)
    lowerRound cl
        = let inc = foldl (\ acc, e =>
                             let hi = findRep cl e.hi in
                                 insert hi ((e.lo, e.strict) :: fromMaybe [] (lookup hi acc)) acc)
                          (the (NameMap (List (Name, Bool))) empty) es in
              foldl (\ (ch, cl), u =>
                       if findRep cl u /= u || isJust (lookup u keep) then (ch, cl) else
                         case oneLower cl u (fromMaybe [] (lookup u inc)) Nothing of
                              Just l => (True, mergeInto l u cl)
                              Nothing => (ch, cl))
                    (False, cl) ps

    lowerAll : Nat -> UClasses -> UClasses
    lowerAll k cl
        = if k >= 20 then cl else
            let (ch, cl') = lowerRound cl in
                if ch then lowerAll (S k) cl' else cl'

    mapEdge : UClasses -> UEdge -> Maybe UEdge
    mapEdge cl e
        = let lo = findRep cl e.lo
              hi = findRep cl e.hi in
              if lo == hi && not e.strict then Nothing
                 else Just ({ lo := lo, hi := hi } e)

    addE : NameMap (NameMap UEdge) -> UEdge -> NameMap (NameMap UEdge)
    addE m e
        = let inner = fromMaybe empty (lookup e.lo m)
              st = e.strict || maybe False strict (lookup e.hi inner) in
              insert e.lo (insert e.hi ({ strict := st } e) inner) m

    dedup : List UEdge -> List UEdge
    dedup es
        = concatMap (\ p => map snd (NameMap.toList (snd p)))
                    (NameMap.toList (foldl addE empty es))

-- The most universes a group of definitions is polymorphic in (see
-- 'completeGroup')
maxPolyUniverses : Nat
maxPolyUniverses = 256

-- A group of definitions checked completely: make each polymorphic in the
-- universes of the types and clauses of them all ('ms' gives the universes
-- of each one's clauses), which no definition outside the group has. They
-- share the schema: a reference from one of them to another has no
-- instance, and is renamed with the one it is in (see Core.UniverseInst).
-- A reference to a definition which has a schema gets a fresh instance of
-- it (see 'freshenUse'), and unfolds to its body renamed to the instance.
completeGroup : {auto c : Ref Ctxt Defs} ->
                List (Name, List Name) -> Core ()
completeGroup [] = pure ()
completeGroup ms
    = do defs <- get Ctxt
         let names = map fst ms
         tyls <- traverse typeLevels names
         let info = universes defs
         let ls = nubNames (concat tyls ++ concatMap snd ms)
         let memberSet = nameSet names
         let found = map (\ n => fromMaybe ([], False) (lookup n (defEdges info))) names
         let pending = any snd found
         let start = foldl min (completions info)
                           (mapMaybe (\ n => lookup n (defStart info)) names)
         -- the definitions which are data types or constructors
         dataDefs <- nameSet . map fst <$>
                       filterM (\ (o, _) => isDataDef o)
                               (concatMap (\ u => map (\ o => (o, ())) (fromMaybe [] (lookup u (typeOwner info)))) ls)
         let ps = filter (\ u => not (isJust (lookup u (fixed info)))
                                 && all (ownedOk info memberSet dataDefs start u)
                                        (fromMaybe [] (lookup u (typeOwner info))))
                         ls
         log "universe" 5 $ "Universes of " ++ show names ++ ": " ++ show ls
                ++ "; polymorphic in " ++ show ps
                ++ (if pending then " (but met an unsolved metavariable)" else "")
         let psSet = nameSet ps
         let (reps, as, es) = minimise (nameSet (concat tyls)) ps
                                       (filter (touches psSet) (concatMap fst found))
         log "universe" 5 $ "Renamed by an instance: " ++ show (length reps)
                ++ " of " ++ show (length ps)
         -- A group with very many universes is not made polymorphic: every
         -- reference to it would carry an instance of them all (and the
         -- references in a definition's body make its universes; see
         -- 'minimise'). Its uses are at its own universes, which is sound.
         let tooMany = length reps > maxPolyUniverses
         when tooMany $
           log "universe" 2 $ "Not polymorphic, too many universes ("
                 ++ show (length reps) ++ "): " ++ show names
         unless (pending || null reps || tooMany) $
           do let fn = fromMaybe (UN (Basic "<group>")) (head' names)
              let stamp = completions info
              -- (no clause has a universe the copies rename: see 'bodyFree')
              let repSet = nameSet reps
              let asMap = the (NameMap Name) (fromList as)
              let bodyFree = not (any (\ u => isJust (lookup (fromMaybe u (lookup u asMap)) repSet))
                                      (concatMap snd ms))
              let sch = MkUSchema reps es [] stamp names as bodyFree
              update Ctxt { universes->completions := stamp + 1,
                            universes->schemas $= insertFrom (map (\ n => (n, sch)) names),
                            -- (saved once: the group's other members get it
                            -- when it is imported, see 'addImportedUniverses')
                            universes->savedSchemas $= ((fn, sch) ::) }
  where
    touches : NameMap () -> UEdge -> Bool
    touches ps e = isJust (lookup e.lo ps) || isJust (lookup e.hi ps)

    -- A universe which another definition has too can be renamed only if
    -- that one is in the group, or is a data type or a constructor which is
    -- polymorphic in it, not through an instance (its every use renames the
    -- universe afresh, see 'globalType', so a definition which has the
    -- universe itself has it from a copy of the type it made), and which was
    -- complete before the group was started.
    ownedOk : UniverseInfo -> NameMap () -> NameMap () -> Int -> Name -> Name -> Bool
    ownedOk info members dataDefs start u o
        = isJust (lookup o members) ||
          (isJust (lookup o dataDefs) &&
           case lookup o (schemas info) of
                Just sch => elem u (poly sch) && not (elem u (instOnly sch))
                              && stamp sch < start
                Nothing => False)

    isDataDef : Name -> Core Bool
    isDataDef o
        = do defs <- get Ctxt
             Just gdef <- lookupCtxtExact o (gamma defs)
                  | Nothing => pure False
             pure $ case definition gdef of
                         TCon {} => True
                         DCon {} => True
                         _ => False

    -- the solved metavariables of the type are renamed with it (see
    -- 'globalType')
    typeLevels : Name -> Core (List Name)
    typeLevels n
        = do defs <- get Ctxt
             Just ty <- lookupTyExact n (gamma defs)
                  | Nothing => pure []
             canonicalLevels !(normaliseHoles defs Env.empty ty)

-- The group the definition being checked belongs to: the implementation
-- being elaborated, or the outermost definition being elaborated (case
-- blocks, with blocks and local definitions are elaborated inside the
-- definition they are lifted out of)
currentGroup : {auto c : Ref Ctxt Defs} -> Core (Maybe Name)
currentGroup
    = do defs <- get Ctxt
         case implGroup (universes defs) of
              Just g => pure (Just g)
              Nothing => case Prelude.toList (defsStack defs) of
                              (outer :: _ :: _) => Just <$> getFullName outer
                              _ => pure Nothing

-- The schemas of a group are made when the group is done
finishGroup : {auto c : Ref Ctxt Defs} -> Name -> Core ()
finishGroup g
    = do defs <- get Ctxt
         let ms = fromMaybe [] (lookup g (deferred (universes defs)))
         update Ctxt { universes->deferred $= delete g }
         completeGroup (reverse ms)

||| Elaborate an implementation, with its methods: when checking universes,
||| the definitions checked meanwhile are one group (the record of the
||| implementation refers to the methods before they are checked). Inside
||| another definition, they are in that one's group already.
export
withUniverseGroup : {auto c : Ref Ctxt Defs} -> Name -> Core a -> Core a
withUniverseGroup n act
    = do sess <- getSession
         defs <- get Ctxt
         if not (checkUniverses sess) || isJust (implGroup (universes defs))
              || not (null (Prelude.toList (defsStack defs)))
            then act
            else do fn <- getFullName n
                    update Ctxt { universes->implGroup := Just fn }
                    r <- catch act (\ err => do update Ctxt { universes->implGroup := Nothing }
                                                throw err)
                    update Ctxt { universes->implGroup := Nothing }
                    finishGroup fn
                    pure r

||| Check the type of a global definition
export
checkTypeUniverses : {auto c : Ref Ctxt Defs} ->
                     FC -> Name -> ClosedTerm -> Core ()
checkTypeUniverses fc n ty
    = whenChecking $
        do addTypeOwner n ty
           runCheck fc n $ \ s => ignore $ sortOf Env.empty ty
           -- A primitive (an `%extern` or `%foreign` function, or a builtin)
           -- has no body: it is complete once its type is checked, and
           -- polymorphic in the universes of its type, which a use renames
           -- afresh (it is body free, see 'completeGroup'). Its declared type
           -- is an assumption, as for any primitive. A function declared
           -- before its clauses, or a hole, is not one of these.
           defs <- get Ctxt
           Just gdef <- lookupCtxtExact n (gamma defs)
                | Nothing => pure ()
           when (isPrimitive (definition gdef)) $
             do fn <- getFullName n
                completeGroup [(fn, [])]
  where
    isPrimitive : Def -> Bool
    isPrimitive (ExternDef {}) = True
    isPrimitive (ForeignDef {}) = True
    isPrimitive (Builtin {}) = True
    isPrimitive _ = False

||| Check the clauses of a definition by pattern matching
export
checkClauseUniverses : {auto c : Ref Ctxt Defs} ->
                       FC -> Name ->
                       List (vs ** (Env Term vs, Term vs, Term vs)) -> Core ()
checkClauseUniverses fc n pats
    = whenChecking $
        do runCheck fc n $ \ s => traverse_ checkClause pats
           -- The universes of the clauses (those of the left hand sides,
           -- of the types of the pattern variables, of the right hand sides
           -- and of the solutions of the metavariables in them) are this
           -- definition's own: a copy of it renames them, and unfolding a
           -- reference with a universe instance gives the right hand side
           -- renamed so (see Core.UniverseInst)
           ls <- nubNames . concat <$> traverse clauseLevels pats
           addOwners n ls
           fn <- getFullName n
           -- In a group, the schema waits for the group to be done
           g <- currentGroup
           update Ctxt { universes->deferred $=
                           \ m => let k = fromMaybe fn g in
                                       insert k ((fn, ls) :: fromMaybe [] (lookup k m)) m }
           when (isNothing g) $ finishGroup fn
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

    envLevels : {vs : _} -> Env Term vs -> Core (List Name)
    envLevels [] = pure []
    envLevels (b :: env)
        = do bs <- case b of
                        Let _ _ val ty => pure (!(evalLevels val) ++ !(evalLevels ty))
                        PLet _ _ val ty => pure (!(evalLevels val) ++ !(evalLevels ty))
                        _ => evalLevels (binderType b)
             pure (bs ++ !(envLevels env))

    clauseLevels : (vs ** (Env Term vs, Term vs, Term vs)) -> Core (List Name)
    clauseLevels (_ ** (env, lhs, rhs))
        = pure (!(envLevels env) ++ !(evalLevels lhs) ++ !(evalLevels rhs))

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
           -- groups which were not done (a definition was left out by an
           -- error, say)
           defs <- get Ctxt
           traverse_ finishGroup (keys (deferred (universes defs)))
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
                          Just (MkUSchema _ _ [] _ _ _ _) => pure (nt, !(freshenWith empty ty))
                          Just sch =>
                            do inst <- traverse freshCopy (instOnly sch)
                               ty' <- freshenWith (fromList inst) ty
                               pure (TyCon a (map snd inst), ty')
                Func [] =>
                  do defs <- get Ctxt
                     fn <- canonical n
                     case lookup fn (schemas (universes defs)) of
                          Just sch@(MkUSchema ps@(_ :: _) _ [] _ _ _ False) =>
                            do inst <- traverse freshCopy ps
                               ty' <- freshenWith (fromList (instPairs sch (map snd inst))) ty
                               pure (Func (map snd inst), ty')
                          _ => pure (nt, !(freshenWith empty ty))
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
