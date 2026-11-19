module Core.Transform

import Core.Context
import Core.Env
import Core.Context.Log
import Core.Normalise

import Libraries.Data.NameMap

%default total

unload : List (FC, Term vars) -> Term vars -> Term vars
unload [] fn = fn
unload ((fc, arg) :: args) fn = unload args (App fc fn arg)

-- List of matches on LHS
data MatchVars : Scope -> Scope -> Type where
     None : MatchVars lhsvars vs
     Match : (idx : Nat) -> (0 p : IsVar n idx lhsvars) -> Term vs ->
             MatchVars lhsvars vs -> MatchVars lhsvars vs

lookupMatch : (idx : Nat) -> (0 p : IsVar n idx lhsvars) -> MatchVars lhsvars vs ->
              Maybe (Term vs)
lookupMatch idx p None = Nothing
lookupMatch idx p (Match v _ val rest)
    = if idx == v
         then Just val
         else lookupMatch idx p rest

addMatch : (idx : Nat) -> (0 p : IsVar n idx lhsvars) -> Term vs ->
           MatchVars lhsvars vs -> Maybe (MatchVars lhsvars vs)
addMatch idx p val ms
    = case lookupMatch idx p ms of
           Nothing => Just (Match idx p val ms)
           Just val' => if eqTerm val val'
                           then Just ms
                           else Nothing

-- The matches under a binder of the rule: its variables are one further out,
-- and so are the variables of the terms.
weakenMatch : MatchVars lhsvars vs -> MatchVars (x :: lhsvars) (x :: vs)
weakenMatch None = None
weakenMatch (Match idx p val rest)
    = Match (S idx) (Later p) (weaken val) (weakenMatch rest)

-- LHS of a rule must be a function application, so there's not much work
-- to do here!
match : MatchVars vars vs ->
        Term vars -> Term vs -> Maybe (MatchVars vars vs)
match ms (Local _ _ idx p) val
    = addMatch idx p val ms
match ms (App _ f a) (App _ f' a')
    = do ms' <- match ms f f'
         match ms' a a'
match ms x y
    = if eqTerm x y
         then Just ms
         else Nothing

covering
tryReplace : MatchVars vars vs -> Term vars -> Maybe (Term vs)
tryReplace ms (Local _ _ idx p) = lookupMatch idx p ms
tryReplace ms (Ref fc nt n) = pure (Ref fc nt n)
tryReplace ms (Meta fc n i as)
    = do as' <- traverse (tryReplace ms) as
         pure (Meta fc n i as')
tryReplace ms (Bind fc x b sc)
    -- A binder in the rule (a lambda, or a function type in an implicit
    -- argument: `pure {a = b -> List b -> List1 b} (:::)`): its variable
    -- stands for itself, and the matched terms are weakened past it.
    = do b' <- traverse (tryReplace ms) b
         sc' <- tryReplace (Match 0 First (Local fc Nothing 0 First) (weakenMatch ms)) sc
         pure (Bind fc x b' sc')
tryReplace ms (App fc f a)
    = do f' <- tryReplace ms f
         a' <- tryReplace ms a
         pure (App fc f' a')
tryReplace ms (As fc s a p)
    = do a' <- tryReplace ms a
         p' <- tryReplace ms p
         pure (As fc s a' p')
tryReplace ms (TDelayed fc r tm)
    = do tm' <- tryReplace ms tm
         pure (TDelayed fc r tm')
tryReplace ms (TDelay fc r ty tm)
    = do ty' <- tryReplace ms ty
         tm' <- tryReplace ms tm
         pure (TDelay fc r ty' tm')
tryReplace ms (TForce fc r tm)
    = do tm' <- tryReplace ms tm
         pure (TForce fc r tm')
tryReplace ms (PrimVal fc c) = pure (PrimVal fc c)
tryReplace ms (Erased fc Impossible) = pure (Erased fc Impossible)
tryReplace ms (Erased fc Placeholder) = pure (Erased fc Placeholder)
tryReplace ms (Erased fc (Dotted t)) = Erased fc . Dotted <$> tryReplace ms t
tryReplace ms (TType fc u) = pure (TType fc u)

covering
tryApply : Transform -> Term vs -> Maybe (Term vs)
tryApply trans@(MkTransform {vars} n _ lhs rhs) tm
   = case match None lhs tm of
          Just ms => tryReplace ms rhs
          Nothing =>
            case tm of
                 App fc f a =>
                     do f' <- tryApply trans f
                        Just (App fc f' a)
                 _ => Nothing

data Upd : Type where

-- An application whose implicit arguments were found late (the monad of
-- `traverse f xs` in `runState s (traverse f xs)`, say) can still have solved
-- holes in them, which match no rule, and a rule that only looks at the
-- implementation (the one that makes a method of a known implementation a
-- call of the implementation's function) would take it first.  So a rule that
-- does not match the application as it is is tried again on the application
-- with the holes replaced by their solutions (and the names resolved, as they
-- are in the rules), before the next rule is.
covering
applyHoles : {vars : _} ->
             {auto c : Ref Ctxt Defs} ->
             Env Term vars -> List Transform -> Term vars -> Core (Bool, Term vars)
applyHoles env ts tm = go Nothing ts
  where
    solved : Maybe (Term vars) -> Core (Term vars)
    solved (Just tm') = pure tm'
    solved Nothing
        = do defs <- get Ctxt
             toResolvedNames !(normaliseHoles defs env tm)

    go : Maybe (Term vars) -> List Transform -> Core (Bool, Term vars)
    go _ [] = pure (False, tm)
    go cache (t :: ts)
        = case tryApply t tm of
               Just res => pure (True, res)
               Nothing =>
                   do tm' <- solved cache
                      case tryApply t tm' of
                           Just res =>
                               do logTerm "transform.holes" 5 "Matched with its holes solved" tm'
                                  pure (True, res)
                           Nothing => go (Just tm') ts

covering
trans : {vars : _} ->
        {auto c : Ref Ctxt Defs} ->
        {auto u : Ref Upd Bool} ->
        Env Term vars -> List (FC, Term vars) -> Term vars ->
        Core (Term vars)
trans env stk (Ref fc Func fn)
    = do defs <- get Ctxt
         case lookup fn (transforms defs) of
              Nothing => pure (unload stk (Ref fc Func fn))
              Just ts => do let fullapp = unload stk (Ref fc Func fn)
                            (u, tm') <- applyHoles env ts fullapp
                            update Upd (|| u)
                            pure tm'
trans env stk (Meta fc n i args)
    = do args' <- traverse (trans env []) args
         pure $ unload stk (Meta fc n i args')
trans env stk (Bind fc x b sc)
    = do b' <- traverse (trans env []) b
         sc' <- trans (b' :: env) [] sc
         pure $ unload stk (Bind fc x b' sc')
trans env stk (App fc fn arg)
    = do arg' <- trans env [] arg
         trans env ((fc, arg') :: stk) fn
trans env stk (TDelayed fc r tm)
    = do tm' <- trans env [] tm
         pure $ unload stk (TDelayed fc r tm')
trans env stk (TDelay fc r ty tm)
    = do ty' <- trans env [] ty
         tm' <- trans env [] tm
         pure $ unload stk (TDelay fc r ty' tm')
trans env stk (TForce fc r tm)
    = do tm' <- trans env [] tm
         pure $ unload stk (TForce fc r tm')
trans env stk tm = pure $ unload stk tm

covering
transLoop : {vars : _} ->
            {auto c : Ref Ctxt Defs} ->
            Nat -> Env Term vars -> Term vars -> Core (Term vars)
transLoop Z env tm = pure tm
transLoop (S k) env tm
    = do u <- newRef Upd False
         tm' <- trans env [] tm
         upd <- get Upd
         if upd -- If there was a transform applied, go around again until
                -- we hit the threshold
            then transLoop k env tm'
            else pure tm'

export
covering
applyTransforms : {vars : _} ->
                  {auto c : Ref Ctxt Defs} ->
                  Env Term vars -> Term vars -> Core (Term vars)
applyTransforms env tm
    = do resolveTransforms
         transLoop 5 env tm
