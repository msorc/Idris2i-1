||| Renaming the universes of terms, for universe instances
||| (`--check-universes`, see Core.UniverseCheck).
|||
||| A reference to a global with a universe instance (Func or TyCon in
||| NameType) stands for the copy of the global whose universes (those of its
||| universe schema) are renamed to the instance. Unfolding such a reference
||| gives the global's body renamed the same way ('instantiateDef'), and the
||| universe checker types it with the global's type renamed so.
module Core.UniverseInst

import Core.Case.CaseTree
import Core.Context
import Core.TT

import Data.List
import Libraries.Data.NameMap

%default covering

||| A renaming of universe names
public export
record URename where
  constructor MkURename
  ||| The new names, by full name and, for the universes which are in the
  ||| context, by resolved name too
  names : NameMap Name
  ||| Whether to put the solutions of solved metavariables in place, so that
  ||| they are renamed too (when unfolding: a solution is shared by every
  ||| copy otherwise)
  inlineMetas : Bool

||| A renaming from pairs of a (full) universe name and its new name
export
mkURename : Context -> (inlineMetas : Bool) -> List (Name, Name) -> URename
mkURename gam inl ps = MkURename (foldl add empty ps) inl
  where
    add : NameMap Name -> (Name, Name) -> NameMap Name
    add m (p, s)
        = let m' = insert p s m in
              case getNameID p gam of
                   Just i => insert (Resolved i) s m'
                   Nothing => m'

||| Whether a renaming renames nothing
export
isEmptyRename : URename -> Bool
isEmptyRename r = null (NameMap.toList r.names)

renameU : URename -> Name -> Name
renameU r u = fromMaybe u (lookup u r.names)

renamesAny : URename -> List Name -> Bool
renamesAny r = any (\ u => isJust (lookup u r.names))

mutual
  -- A reference without an instance stands for the global's own universes.
  -- When the renaming renames some of them (the reference is in the body or
  -- the type of a definition of the same group, or in the type of a
  -- constructor of the same family), it gets them as its instance first, so
  -- that it is renamed with them.
  renameNameType : Defs -> URename -> Name -> NameType -> Core NameType
  renameNameType defs r n (Func inst@(_ :: _)) = pure (Func (map (renameU r) inst))
  renameNameType defs r n (TyCon a inst@(_ :: _)) = pure (TyCon a (map (renameU r) inst))
  renameNameType defs r n nt@(Func [])
      = do fn <- full (gamma defs) n
           let Just sch = lookup fn (schemas (universes defs))
                | Nothing => pure nt
           pure (if renamesAny r (poly sch) && null (instOnly sch) && not (bodyFree sch)
                    then Func (map (renameU r) (poly sch))
                    else nt)
  renameNameType defs r n nt@(TyCon a [])
      = do fn <- full (gamma defs) n
           let Just sch = lookup fn (schemas (universes defs))
                | Nothing => pure nt
           pure (if renamesAny r (instOnly sch)
                    then TyCon a (map (renameU r) (instOnly sch))
                    else nt)
  renameNameType defs r n nt = pure nt

  ||| Rename the universes in a term (the universe of each `Type` and the
  ||| universe instances of references)
  export
  renameUnivs : Defs -> URename -> Term vars -> Core (Term vars)
  renameUnivs defs r tm@(Local {}) = pure tm
  renameUnivs defs r (Ref fc nt n) = pure (Ref fc !(renameNameType defs r n nt) n)
  renameUnivs defs r (Meta fc n i args)
      = do args' <- traverse (renameUnivs defs r) args
           if not (inlineMetas r) then pure (Meta fc n i args') else
             do Just gdef <- lookupCtxtExact (Resolved i) (gamma defs)
                     | Nothing => pure (Meta fc n i args')
                case definition gdef of
                     PMDef _ [] (STerm _ sol) _ _ =>
                       do sol' <- renameUnivs defs r (embed sol)
                          pure (apply fc sol' args')
                     _ => pure (Meta fc n i args')
  renameUnivs defs r (Bind fc x b sc)
      = pure (Bind fc x !(traverse (renameUnivs defs r) b) !(renameUnivs defs r sc))
  renameUnivs defs r (App fc f a)
      = pure (App fc !(renameUnivs defs r f) !(renameUnivs defs r a))
  renameUnivs defs r (As fc s a p) = As fc s a <$> renameUnivs defs r p
  renameUnivs defs r (TDelayed fc lr t) = TDelayed fc lr <$> renameUnivs defs r t
  renameUnivs defs r (TDelay fc lr t v)
      = pure (TDelay fc lr !(renameUnivs defs r t) !(renameUnivs defs r v))
  renameUnivs defs r (TForce fc lr t) = TForce fc lr <$> renameUnivs defs r t
  renameUnivs defs r tm@(PrimVal {}) = pure tm
  renameUnivs defs r (Erased fc (Dotted t)) = Erased fc . Dotted <$> renameUnivs defs r t
  renameUnivs defs r tm@(Erased {}) = pure tm
  renameUnivs defs r (TType fc u) = pure (TType fc (renameU r u))

mutual
  renameTree : Defs -> URename -> CaseTree vs -> Core (CaseTree vs)
  renameTree defs r (Case idx p scTy alts)
      = pure (Case idx p !(renameUnivs defs r scTy) !(traverse (renameAlt defs r) alts))
  renameTree defs r (STerm i tm) = STerm i <$> renameUnivs defs r tm
  renameTree defs r t = pure t

  renameAlt : Defs -> URename -> CaseAlt vs -> Core (CaseAlt vs)
  renameAlt defs r (ConCase n t args sc) = ConCase n t args <$> renameTree defs r sc
  renameAlt defs r (DelayCase ty arg sc) = DelayCase ty arg <$> renameTree defs r sc
  renameAlt defs r (ConstCase c sc) = ConstCase c <$> renameTree defs r sc
  renameAlt defs r (DefaultCase sc) = DefaultCase <$> renameTree defs r sc

||| The definition of a global (with full name 'fn') at a universe instance:
||| its universes renamed to the instance. A definition without a universe
||| schema, or an instance which does not fit it, gives the definition as it
||| is (its own universes).
export
instantiateDef : Defs -> (fn : Name) -> (inst : List Name) -> Def -> Core Def
instantiateDef defs fn inst d@(PMDef pminfo args tree rt pats)
    = do let Just sch = lookup fn (schemas (universes defs))
              | Nothing => pure d
         if length (poly sch) /= length inst || not (null (instOnly sch))
            then pure d
            else do let r = mkURename (gamma defs) True (instPairs sch inst)
                    tree' <- renameTree defs r tree
                    pure (PMDef pminfo args tree' rt pats)
instantiateDef defs fn inst d = pure d
