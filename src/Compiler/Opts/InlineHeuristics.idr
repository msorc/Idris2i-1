module Compiler.Opts.InlineHeuristics

import Core.CompileExpr
import Core.Context.Log
import Data.Vect
import Libraries.Data.WithDefault

parameters (fn : Name)
    isVar : CExp vars -> Bool
    isVar (CLocal {}) = True
    isVar (CRef {}) = True
    isVar (CForce _ _ x) = isVar x
    isVar (CDelay _ _ x) = isVar x
    isVar _ = False

    simple : CExp vars -> Bool
    simple (CLocal {}) = True
    simple (CRef {}) = True
    simple (CLam {}) = False
    simple (CLet {}) = False
    simple (CApp _ (CRef _ fn') xs) = not (fn == fn') && all isVar xs
    simple (CApp _ fn xs) = isVar fn && all isVar xs
    simple (CCon _ _ _ _ xs) = all isVar xs
    simple (COp _ _ xs) = all isVar xs
    simple (CExtPrim _ _ xs) = all isVar xs
    simple (CForce _ _ y) = simple y
    simple (CDelay _ _ y) = simple y
    simple (CConCase {}) = False
    simple (CConstCase {}) = False
    simple (CPrimVal {}) = True
    simple (CErased {}) = True
    simple (CCrash {}) = False

    mutual
      -- A small body, which costs less to inline than to call: primitive
      -- operations, calls and constructors on small arguments (`x == y` on
      -- `Int` is `intToBool (prim__eq_Int x y)`), and cases on small
      -- expressions with small alternatives (`div` on `Int` checks for 0).
      -- `small k e` is the budget (in nodes) that is left once `e` is
      -- counted, if it fits in `k`.
      small : Nat -> CExp vars -> Maybe Nat
      small Z _ = Nothing
      small (S k) (CLocal {}) = Just k
      small (S k) (CRef _ fn') = if fn == fn' then Nothing else Just k
      small (S k) (CPrimVal {}) = Just k
      small (S k) (CErased {}) = Just k
      small (S k) (CCrash {}) = Just k
      small (S k) (COp _ _ xs) = smalls k (toList xs)
      small (S k) (CCon _ _ _ _ xs) = smalls k xs
      small (S k) (CApp _ (CRef _ fn') xs)
          = if fn == fn' then Nothing else smalls k xs
      small (S k) (CConstCase _ sc alts def)
          = do k <- small k sc
               k <- constAlts k alts
               maybe (Just k) (small k) def
      small (S k) (CConCase _ sc alts def)
          = do k <- small k sc
               k <- conAlts k alts
               maybe (Just k) (small k) def
      small _ _ = Nothing

      smalls : Nat -> List (CExp vars) -> Maybe Nat
      smalls k [] = Just k
      smalls k (x :: xs) = small k x >>= \k => smalls k xs

      constAlts : Nat -> List (CConstAlt vars) -> Maybe Nat
      constAlts k [] = Just k
      constAlts k (MkConstAlt _ e :: as) = small k e >>= \k => constAlts k as

      conAlts : Nat -> List (CConAlt vars) -> Maybe Nat
      conAlts k [] = Just k
      conAlts k (MkConAlt _ _ _ _ e :: as) = small k e >>= \k => conAlts k as

    inlineCDef : CDef -> Bool
    inlineCDef (MkFun args exp) =
        simple exp || isJust (small 12 exp)
    inlineCDef _ = False

export
inlineHeuristics : Ref Ctxt Defs => Name -> Core ()
inlineHeuristics fn = do
    defs <- get Ctxt
    Just (fnIdx, gdef) <- lookupCtxtExactI fn defs.gamma
        | Nothing => pure ()
    let Just cdef = gdef.compexpr
        | Nothing => pure ()
    let True = inlineCDef fn cdef
        | False => pure ()
    -- We can't determine based on heuristics that something should be inlined unless
    -- it is publicly exported because we may be crossing module boundaries and changes
    -- to the given def will not modify the source module's interface hash so you can get
    -- stuck with an old def inlined into the destination module. This is only a problem
    -- when determining to inline based on heuristics, though -- if the definition was
    -- explicitly marked for inlining by the programmer, it will be inlined without any
    -- intervention by this function.
    -- We could lift this public restriction if we checked that the source def was _either
    -- public OR the destination was the same module as the source_.
    let Public = collapseDefault $ gdef.visibility
        | _ => pure ()
    unless (NoInline `elem` gdef.flags) $ do
      log "compiler.inline.heuristic" 25 $ "inlining heuristic decided to inline: " ++ show fn
      setFlag EmptyFC (Resolved fnIdx) Inline
