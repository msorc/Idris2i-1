module Core.Termination.TypeCase

import Core.Case.CaseTree
import Core.Context
import Core.Env
import Core.Normalise

import Libraries.Data.NameMap

%default covering

-- Matching on a type constructor and using its arguments makes the type
-- constructor injective *and* gives the function a left inverse of it. For an
-- argument that is itself a type (`List a` gives back `a`) this is harmless.
-- For an argument whose type is as large as `Type -> Type`, it is not:
--
--   data I : (Type -> Bool) -> Type where
--   J : Type -> (Type -> Bool)
--   J (I f) = f
--
-- embeds `Type -> Bool` in `Type` with `J` as its inverse, and the diagonal
-- argument gives a closed term of type `Void` (issues #1116 and #1326). The
-- same works with no data type at all, since a pattern `(a -> b)` binds `b`
-- as a function from `a`, which `Type -> b` makes a function over types.
--
-- So a function is not accepted as total when a clause takes a variable out
-- of a type pattern, uses it on the right hand side, and the type of the
-- variable is neither `Type` nor small. A type is small when no `Type`
-- occurs in it and nothing in it can hide one: variables standing for
-- arbitrary types, type constructors with a constructor that stores a type
-- or a value of a type that is not small, and functions that did not reduce.
-- A function from a small type to `Type` is also allowed, since it embeds no
-- function over types.

-- Free variables of a term, as de Bruijn indices in the scope `d` binders up.
locals : (dots : Bool) -> Nat -> Term vars -> List Nat -> List Nat
locals dots d (Local _ _ idx _) acc
    = if idx >= d then minus idx d :: acc else acc
locals dots d (Meta _ _ _ args) acc
    = foldr (locals dots d) acc args
locals dots d (Bind _ _ b sc) acc
    = let acc' = locals dots d (binderType b) (locals dots (S d) sc acc) in
          case b of
               Let _ _ val _ => locals dots d val acc'
               PLet _ _ val _ => locals dots d val acc'
               _ => acc'
locals dots d (App _ f a) acc = locals dots d f (locals dots d a acc)
locals dots d (As _ _ as pat) acc = locals dots d as (locals dots d pat acc)
locals dots d (TDelayed _ _ t) acc = locals dots d t acc
locals dots d (TDelay _ _ ty t) acc = locals dots d ty (locals dots d t acc)
locals dots d (TForce _ _ t) acc = locals dots d t acc
locals dots d (Erased _ (Dotted t)) acc
    = if dots then locals dots d t acc else acc
locals _ _ _ acc = acc

-- The constructors that a case tree matches on. A type that the clause
-- mentions on its left hand side is often not matched at all, because another
-- pattern forces it (`Refl` forces the type of both sides), and such terms
-- are not marked as dotted; the case tree knows.
treeCons : CaseTree vars -> List Name -> List Name
treeCons (Case _ _ _ alts) acc = foldr altCons acc alts
  where
    altCons : forall vars . CaseAlt vars -> List Name -> List Name
    altCons (ConCase n _ _ sc) acc = n :: treeCons sc acc
    altCons (DelayCase _ _ sc) acc = treeCons sc acc
    altCons (ConstCase _ sc) acc = treeCons sc acc
    altCons (DefaultCase sc) acc = treeCons sc acc
treeCons _ acc = acc

arrowName : Name
arrowName = UN (Basic "->")

-- The pattern variables bound inside type patterns: under a type constructor
-- or a function type that is matched on.
typePatVars : (matched : Name -> Bool) -> Term vars -> List Nat
typePatVars matched tm
    = case getFnArgs tm of
           (Ref _ (TyCon {}) n, args) =>
               if matched n
                  then foldr (locals False 0) [] args
                  else concatMap (typePatVars matched) args
           (Ref _ (DataCon {}) _, args) => concatMap (typePatVars matched) args
           (Bind _ _ (Pi _ _ _ ty) sc, _) =>
               if matched arrowName
                  then locals False 0 ty (locals False 1 sc [])
                  else []
           (As _ _ _ pat, _) => typePatVars matched pat
           (TDelay _ _ _ t, _) => typePatVars matched t
           _ => []

binderAt : {vars : _} -> Nat -> Env Term vars -> Maybe (Name, Binder (Term vars))
binderAt {vars = x :: _} Z (b :: env) = Just (x, map weaken b)
binderAt (S k) (b :: env) = map (map (map weaken)) (binderAt k env)
binderAt _ _ = Nothing

isTType : Term vars -> Bool
isTType (TType {}) = True
isTType _ = False

-- Is the variable `d` binders up an argument of the type that the
-- constructor type `tm` ends in?
paramIn : Nat -> Term vars -> Bool
paramIn d (Bind _ _ (Pi {}) sc) = paramIn (S d) sc
paramIn d tm = any isVar (snd (getFnArgs tm))
  where
    isVar : forall vars . Term vars -> Bool
    isVar (Local _ _ idx _) = idx == d
    isVar _ = False

parameters {auto c : Ref Ctxt Defs} (defs : Defs)
  mutual
    -- In the environment a `Lam` binder marks a type parameter of the data
    -- type being looked at: it counts as small there, because the arguments
    -- that the type is applied to are checked where it is used.
    small : {vars : _} -> List Name -> Env Term vars -> Term vars -> Core Bool
    small seen env (Local _ _ _ p)
        = case getBinder p env of
               Lam {} => pure True
               b => small seen env !(normalise defs env (binderType b))
    small seen env (Ref _ (TyCon {}) n) = smallTCon seen n
    small seen env (Ref _ (DataCon {}) _) = pure True
    small seen env (App _ f a)
        = do True <- small seen env f
                | False => pure False
             small seen env a
    small seen env (Bind fc x (Pi _ rig _ ty) sc)
        = do True <- small seen env ty
                | False => pure False
             small seen (Pi fc rig Explicit ty :: env) sc
    small seen env (Bind fc x (Lam _ rig _ ty) sc)
        = do True <- small seen env ty
                | False => pure False
             small seen (Pi fc rig Explicit ty :: env) sc
    small seen env (As _ _ _ pat) = small seen env pat
    small seen env (TDelayed _ _ t) = small seen env t
    small seen env (TDelay _ _ ty t)
        = do True <- small seen env ty
                | False => pure False
             small seen env t
    small seen env (TForce _ _ t) = small seen env t
    small seen env (PrimVal {}) = pure True
    small _ _ _ = pure False

    smallTCon : List Name -> Name -> Core Bool
    smallTCon seen n_in
        = do n <- getFullName n_in
             let False = n `elem` seen
                 | True => pure True -- assume it of the type being checked
             Just gdef <- lookupCtxtExact n (gamma defs)
                 | Nothing => pure False
             let TCon _ _ _ _ _ (Just cons) _ = definition gdef
                 | _ => pure False
             allM (smallCon (n :: seen)) cons

    smallCon : List Name -> Name -> Core Bool
    smallCon seen cn
        = do Just gdef <- lookupCtxtExact cn (gamma defs)
                 | Nothing => pure False
             smallArgs seen [] (type gdef)

    smallArgs : {vars : _} ->
                List Name -> Env Term vars -> Term vars -> Core Bool
    smallArgs seen env (Bind fc x (Pi _ rig _ ty) sc)
        = do ty' <- normalise defs env ty
             if isTType ty' && paramIn 0 sc
                then smallArgs seen (Lam fc rig Explicit ty' :: env) sc
                else do True <- small seen env ty'
                           | False => pure False
                        smallArgs seen (Pi fc rig Explicit ty' :: env) sc
    smallArgs _ _ _ = pure True

  -- Can a variable of this (normalised) type be taken out of a type pattern?
  extractable : {vars : _} -> Env Term vars -> Term vars -> Core Bool
  extractable env (TType {}) = pure True
  extractable env (Bind fc x (Pi _ rig _ ty) sc)
      = do True <- small [] env ty
              | False => pure False
           extractable (Pi fc rig Explicit ty :: env) sc
  extractable env ty = small [] env ty

  clauseEscape : (Name -> Bool) ->
                 (vs : Scope ** (Env Term vs, Term vs, Term vs)) ->
                 Core (Maybe Name)
  clauseEscape matched (vs ** (env, lhs, rhs))
      = case concatMap (typePatVars matched) (snd (getFnArgs lhs)) of
             [] => pure Nothing
             cands => let used = locals True 0 rhs [] in
                          check (filter (\i => i `elem` used) (nub cands))
    where
      check : List Nat -> Core (Maybe Name)
      check [] = pure Nothing
      check (i :: is)
          = do let Just (n, b) = binderAt i env
                   | Nothing => check is
               ty <- normalise defs env (binderType b)
               if !(extractable env ty)
                  then check is
                  else pure (Just n)

  ownEscape : GlobalDef -> Core (Maybe Name)
  ownEscape def
      = case definition def of
             PMDef _ _ tree _ pats =>
                 case treeCons tree [] of
                      [] => pure Nothing
                      cons => firstEscape (matched (mapMaybe nameId cons)
                                                   (any isArrow cons)) pats
             _ => pure Nothing
    where
      -- names in terms and trees may or may not be resolved
      nameId : Name -> Maybe Int
      nameId n = getNameID n (gamma defs)

      isArrow : Name -> Bool
      isArrow n = n == arrowName

      matched : List Int -> Bool -> Name -> Bool
      matched ids arr n
          = if isArrow n
               then arr
               else maybe False (\i => i `elem` ids) (nameId n)

      firstEscape : (Name -> Bool) ->
                    List (vs : Scope ** (Env Term vs, Term vs, Term vs)) ->
                    Core (Maybe Name)
      firstEscape matched [] = pure Nothing
      firstEscape matched (p :: ps)
          = do Nothing <- clauseEscape matched p
                  | res => pure res
               firstEscape matched ps

  ||| If a clause of the definition takes a variable out of a type by pattern
  ||| matching, uses it, and its type is neither `Type` nor small, return
  ||| the name of the variable. The case blocks of the definition count as
  ||| part of it: they are inlined, so the termination checker never sees
  ||| them as functions of their own.
  export
  typeCaseEscape : GlobalDef -> Core (Maybe Name)
  typeCaseEscape def
      = do Nothing <- ownEscape def
              | res => pure res
           caseBlocks [] (keys (refersTo def))
    where
      caseBlocks : List Name -> List Name -> Core (Maybe Name)
      caseBlocks seen [] = pure Nothing
      caseBlocks seen (n :: ns)
          = do fn <- getFullName n
               if not (caseFn fn) || (fn `elem` seen)
                  then caseBlocks seen ns
                  else do Just cdef <- lookupCtxtExact n (gamma defs)
                             | Nothing => caseBlocks seen ns
                          Nothing <- ownEscape cdef
                             | res => pure res
                          caseBlocks (fn :: seen) (keys (refersTo cdef) ++ ns)
