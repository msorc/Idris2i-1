module Compiler.Inline

import Compiler.CaseOpts
import Compiler.CompileExpr
import Compiler.Opts.ConstantFold
import Compiler.Opts.EtaIO
import Compiler.Opts.Identity
import Compiler.Opts.InlineHeuristics

import Core.Context.Log
import Core.Hash
import Core.Options

import Data.List.Quantifiers
import Data.Vect

import Libraries.Data.IntMap
import Libraries.Data.List.LengthMatch
import Libraries.Data.NameMap
import Libraries.Data.WithDefault
import Libraries.Data.List.SizeOf

%default covering

-- The code that `eval` makes (a `Val`) refers to its variables by name, not
-- by de Bruijn index: to the variables it binds by the names that `genVar`
-- makes, and to the arguments of the definition by the names of `paramVar`.
-- It has no `CLocal`, so it is the same code in every scope (`anyScope`), and
-- `finalise` gives the variables their indices at the end, in one pass.
-- (Each binder used to be closed over its scope as soon as it was made, by a
-- pass over the scope: time quadratic in the depth of the code, and cubic in
-- the length of a chain of binds, as the code of the continuation of an
-- `io_bind` is evaluated again where it is applied.)
--
-- `eval` also evaluates code that it made, the values of variables applied
-- to arguments for example (`named`).  Its binders bind the names of their
-- variables, so the values of those variables are in a map by name
-- (`Subst`), not in the environment.  `eval` does the same on that code as
-- it did on the same code with de Bruijn indices: the code it makes is the
-- same, fresh names included.
Val : Type
Val = CExp []

-- There is no `CLocal` in a `Val`: it is the same code in every scope.
anyScope : CExp [] -> CExp vs
anyScope = believe_me

EEnv : Scope -> Type
EEnv = All (\_ => Val)

-- (by the numbers of the variables, see `varNum`)
Subst : Type
Subst = IntMap Val

-- The namespace-free `Nested` names of the variables of a `Val`: the first
-- number is in no name of a nested function.
inlVarTag : Int
inlVarTag = -0x1D2E

paramTag : Int
paramTag = -0x1D2F

-- The variable made by the fresh number `i` that is shown as `x` in the end.
inlVar : Int -> Name -> Name
inlVar i x = Nested (inlVarTag, i) x

-- The number of a variable
varNum : Name -> Maybe Int
varNum (Nested (t, i) _) = if t == inlVarTag then Just i else Nothing
varNum _ = Nothing

isInlVar : Name -> Bool
isInlVar n = isJust (varNum n)

-- Bind a variable (by its number)
bindNum : Name -> a -> IntMap a -> IntMap a
bindNum x v m = maybe m (\i => insert i v m) (varNum x)

-- What a variable is shown as in the end.  (The binders of the code of a
-- definition are not variables of a `Val`: they are shown as they are.)
shownAs : Name -> Name
shownAs n@(Nested (t, _) x) = if t == inlVarTag then x else n
shownAs n = n

-- The argument `i` of the definition (the variable `i` of its scope).
paramVar : Nat -> Name
paramVar i = Nested (paramTag, cast i) (UN (Basic "arg"))

isParam : Name -> Maybe Nat
isParam (Nested (t, i) _) = if t == paramTag then Just (integerToNat (cast i)) else Nothing
isParam _ = Nothing

extend : EEnv vars -> (args : List Val) -> (args' : List Name) ->
         LengthMatch args args' -> EEnv (Scope.addInner vars args')
extend env [] [] NilMatch = env
extend env (a :: xs) (n :: ns) (ConsMatch w)
    = a :: extend env xs ns w

extendSubst : Subst -> List Val -> List Name -> Subst
extendSubst s (a :: as) (n :: ns) = extendSubst (bindNum n a s) as ns
extendSubst s _ _ = s

Stack : Type
Stack = List Val

unload : List (CExp vs) -> CExp vs -> CExp vs
unload [] e = e
unload (a :: args) e = unload args (CApp (getFC e) e [a])

unloadApp : Nat -> List (CExp vs) -> CExp vs -> CExp vs
unloadApp n args e = unload (drop n args) (CApp (getFC e) e (take n args))

getArity : CDef -> Nat
getArity (MkFun args _) = length args
getArity (MkCon _ arity _) = arity
getArity (MkForeign _ args _) = length args
getArity (MkError _) = 0

takeFromStack : EEnv vars -> Stack -> (args : Scope) ->
                Maybe (EEnv (Scope.addInner vars args), Stack)
takeFromStack env (e :: es) (a :: as)
  = do (env', stk') <- takeFromStack env es as
       pure (e :: env', stk')
takeFromStack env stk [] = pure (env, stk)
takeFromStack env [] args = Nothing

data LVar : Type where

-- A fresh variable, shown as `shown` (by default as `MN root i`) in the end.
genVar : {auto l : Ref LVar Int} ->
         String -> Maybe Name -> Core Name
genVar root shown
    = do i <- get LVar
         put LVar (i + 1)
         pure (inlVar i (fromMaybe (MN root i) shown))

largest : Ord a => a -> List a -> a
largest x [] = x
largest x (y :: ys)
    = if y > x
         then largest y ys
         else largest x ys

mutual
  -- How many times the variable is used: the sum over the parts of a term,
  -- the largest over the alternatives of a case.  With `guarded`, a use
  -- under a non-inlinable let counts as many (1000), so that the name is not
  -- inlined there.
  countUses : {0 free : Scope} -> (guarded : Bool) ->
              {idx : Nat} -> (0 p : IsVar n idx free) -> CExp free -> Int
  countUses g {idx} n (CLocal _ {idx=pidx} prf) = if idx == pidx then 1 else 0
  countUses g n (CLam _ _ sc) = countUses g (Later n) sc
  countUses g n (CLet _ _ NotInline val sc)
      = let usedl = countUses g n val + countUses g (Later n) sc in
            if g && usedl > 0
               then 1000 -- Don't do any inlining of the name, because if it's
                         -- used under a non-inlinable let things might go wrong
               else usedl
  countUses g n (CLet _ _ YesInline val sc)
      = countUses g n val + countUses g (Later n) sc
  countUses g n (CApp _ x args)
      = foldr (+) (countUses g n x) (map (countUses g n) args)
  countUses g n (CCon _ _ _ _ args) = foldr (+) 0 (map (countUses g n) args)
  countUses g n (COp _ _ args) = foldr (+) 0 (map (countUses g n) args)
  countUses g n (CExtPrim _ _ args) = foldr (+) 0 (map (countUses g n) args)
  countUses g n (CForce _ _ x) = countUses g n x
  countUses g n (CDelay _ _ x) = countUses g n x
  countUses g n (CConCase fc sc alts def)
     = countUses g n sc +
          largest (maybe 0 (countUses g n) def) (map (usedCon g n) alts)
  countUses g n (CConstCase fc sc alts def)
     = countUses g n sc +
          largest (maybe 0 (countUses g n) def) (map (usedConst g n) alts)
  countUses _ _ tm = 0

  usedCon : {0 free : Scope} -> (guarded : Bool) ->
            {idx : Nat} -> (0 p : IsVar n idx free) -> CConAlt free -> Int
  usedCon g n (MkConAlt _ _ _ args sc)
      = let MkVar n' = weakenNs (mkSizeOf args) (MkVar n) in
            countUses g n' sc

  usedConst : {0 free : Scope} -> (guarded : Bool) ->
              {idx : Nat} -> (0 p : IsVar n idx free) -> CConstAlt free -> Int
  usedConst g n (MkConstAlt _ sc) = countUses g n sc

used : {0 free : Scope} ->
       {idx : Nat} -> (0 p : IsVar n idx free) -> CExp free -> Int
used = countUses True

mutual
  -- `countUses` of a variable of code that `eval` made, by its name
  countRefs : (guarded : Bool) -> Name -> CExp vs -> Int
  countRefs g n (CRef _ n') = if n == n' then 1 else 0
  countRefs g n (CLam _ _ sc) = countRefs g n sc
  countRefs g n (CLet _ _ NotInline val sc)
      = let usedl = countRefs g n val + countRefs g n sc in
            if g && usedl > 0
               then 1000
               else usedl
  countRefs g n (CLet _ _ YesInline val sc)
      = countRefs g n val + countRefs g n sc
  countRefs g n (CApp _ x args)
      = foldr (+) (countRefs g n x) (map (countRefs g n) args)
  countRefs g n (CCon _ _ _ _ args) = foldr (+) 0 (map (countRefs g n) args)
  countRefs g n (COp _ _ args) = foldr (+) 0 (map (countRefs g n) args)
  countRefs g n (CExtPrim _ _ args) = foldr (+) 0 (map (countRefs g n) args)
  countRefs g n (CForce _ _ x) = countRefs g n x
  countRefs g n (CDelay _ _ x) = countRefs g n x
  countRefs g n (CConCase fc sc alts def)
     = countRefs g n sc +
          largest (maybe 0 (countRefs g n) def) (map (refsCon g n) alts)
  countRefs g n (CConstCase fc sc alts def)
     = countRefs g n sc +
          largest (maybe 0 (countRefs g n) def) (map (refsConst g n) alts)
  countRefs _ _ tm = 0

  refsCon : (guarded : Bool) -> Name -> CConAlt vs -> Int
  refsCon g n (MkConAlt _ _ _ _ sc) = countRefs g n sc

  refsConst : (guarded : Bool) -> Name -> CConstAlt vs -> Int
  refsConst g n (MkConstAlt _ sc) = countRefs g n sc

mutual
  -- `params` is the scope of the definition: its arguments are variables of
  -- the code that `eval` makes (`paramVar`), below the binders of its code
  -- in `vars`.
  evalLocal : {0 vars, params : Scope} ->
              {auto c : Ref Ctxt Defs} ->
              {auto l : Ref LVar Int} ->
              FC -> List Name -> Stack ->
              EEnv vars ->
              {idx : Nat} -> (0 p : IsVar x idx (vars ++ params)) ->
              Core Val
  evalLocal fc rec stk [] {idx} p
      = pure $ unload stk (CRef fc (paramVar idx))
  evalLocal fc rec stk (v :: env) First = evalVar rec stk v
  evalLocal fc rec stk (_ :: env) (Later p) = evalLocal fc rec stk env p

  -- The value of a variable, applied to the stack
  evalVar : {auto c : Ref Ctxt Defs} ->
            {auto l : Ref LVar Int} ->
            List Name -> Stack -> Val -> Core Val
  evalVar rec [] v = pure v
  evalVar rec stk v = evalNamed rec stk v

  -- Evaluate code that `eval` made
  evalNamed : {auto c : Ref Ctxt Defs} ->
              {auto l : Ref LVar Int} ->
              List Name -> Stack -> Val -> Core Val
  evalNamed rec stk v = eval {vars = []} {params = []} True rec IntMap.empty [] stk v

  tryApply : {0 vars, params : Scope} ->
             {auto c : Ref Ctxt Defs} ->
             {auto l : Ref LVar Int} ->
             List Name -> Stack -> EEnv vars -> CDef ->
             Core (Maybe Val)
  tryApply {vars} {params} rec stk env (MkFun args exp)
      = do let Just (env', stk') = takeFromStack env stk args
               | Nothing => pure Nothing
           -- The arguments are substituted in the body, so those that it uses
           -- more than once are let-bound, not to duplicate their work.  (Not
           -- `used`, which counts a use under a non-inlinable let, such as
           -- the `let MkIORes x' w' = fn w` of io_bind, as many: an action
           -- of IO given to a bind would be let-bound, a closure.)
           let uses = map (\(MkVar p) => countUses False p exp) (allVars args)
           (env', shared) <- shareArgs uses env'
           res <- eval {params} False rec IntMap.empty env' stk'
                     (rewrite sym (appendAssociative args vars params) in
                              embed {outer = vars ++ params} exp)
           pure (Just (foldr (\(xn, e), sc =>
                                CLet (getFC e) xn NotInline e (anyScope sc))
                             res shared))
  tryApply rec stk env _ = pure Nothing

  -- Replace the arguments (the first entries of the environment) that are
  -- used more than once (`uses`) and compute something by fresh names, given
  -- with the arguments that they stand for.  A value (such as a lambda, which
  -- is then applied where it is used) is copied: that costs no work.
  shareArgs : {auto l : Ref LVar Int} ->
              List Int -> EEnv vs ->
              Core (EEnv vs, List (Name, Val))
  shareArgs (u :: us) (e :: env)
      = do (env, shared) <- shareArgs us env
           if u > 1 && not (isValue e)
              then do xn <- genVar "inlv" Nothing
                      pure (CRef (getFC e) xn :: env, (xn, e) :: shared)
              else pure (e :: env, shared)
    where
      isValue : Val -> Bool
      isValue (CLocal {}) = True
      isValue (CRef {}) = True
      isValue (CPrimVal {}) = True
      isValue (CErased {}) = True
      isValue (CLam {}) = True
      isValue (CDelay {}) = True
      isValue (CCon _ _ _ _ xs) = all isValue xs
      isValue _ = False
  shareArgs _ env = pure (env, [])

  -- Bind the variable `x` of the code to `v`: in the environment, and by name
  -- in code that `eval` made.
  bindVar : (named : Bool) -> Name -> Val -> Subst -> Subst
  bindVar named x v sub = if named then bindNum x v sub else sub

  -- A variable bound by code that `eval` made, which `sub` gives the value of
  -- (in the code with de Bruijn indices, a `CLocal`)
  boundVar : Subst -> Name -> Maybe Val
  boundVar sub n = varNum n >>= \i => lookup i sub

  -- An argument of the definition, or a variable bound by the code that is
  -- evaluated (in the code with de Bruijn indices, both are `CLocal`s)
  isLocal : Subst -> Name -> Bool
  isLocal sub n = isJust (isParam n) || isJust (boundVar sub n)

  eval : {0 vars, params : Scope} ->
         {auto c : Ref Ctxt Defs} ->
         {auto l : Ref LVar Int} ->
         (named : Bool) ->
         List Name -> -- TODO should be a set
         Subst -> EEnv vars -> Stack -> CExp (vars ++ params) ->
         Core Val
  eval named rec sub env stk (CLocal fc p) = evalLocal fc rec stk env p
  eval {vars} {params} named rec sub env stk (CRef fc n)
      = case boundVar sub n of
             Just v => evalVar rec stk v
             Nothing =>
               if isInlVar n || isJust (isParam n)
                  then pure $ unload stk (CRef fc n) -- a variable bound outside
                  else evalRef {vars} {params} rec env stk fc n

  eval named rec sub env [] (CLam fc x sc)
      = do xn <- genVar "lamv" (Just (shownAs x))
           let v = CRef fc xn
           sc' <- eval named rec (bindVar named x v sub) (v :: env) [] sc
           pure $ CLam fc xn (anyScope sc')
  eval named rec sub env (e :: stk) (CLam fc x sc)
      = eval named rec (bindVar named x e sub) (e :: env) stk sc
  eval named rec sub env stk (CLet fc x NotInline val sc)
      = do xn <- genVar "letv" (Just (shownAs x))
           let v = CRef fc xn
           sc' <- eval named rec (bindVar named x v sub) (v :: env) [] sc
           val' <- eval named rec sub env [] val
           pure (unload stk $ CLet fc xn NotInline val' (anyScope sc'))
  eval named rec sub env stk (CLet fc x YesInline val sc)
      = do let u = the Int (if named then countRefs True x sc else used First sc)
           if u < 1 -- TODO: Can make this <= as long as we know *all* inlinings
                    -- are guaranteed not to duplicate work. (We don't know
                    -- that yet).
              then do val' <- eval named rec sub env [] val
                      eval named rec (bindVar named x val' sub) (val' :: env) stk sc
              else do xn <- genVar "letv" (Just (shownAs x))
                      let v = CRef fc xn
                      sc' <- eval named rec (bindVar named x v sub) (v :: env) stk sc
                      val' <- eval named rec sub env [] val
                      pure (CLet fc xn YesInline val' (anyScope sc'))
  eval named rec sub env stk (CApp fc f@(CRef nfc n) args)
      = if isLocal sub n
           then eval named rec sub env
                     (!(traverse (eval named rec sub env []) args) ++ stk) f
           else do
           -- If we don't know 'n' leave the arity alone, because it's
           -- a name from another module where the job is already done
           defs <- get Ctxt
           Just gdef <- lookupCtxtExact n (gamma defs)
                | Nothing => do args' <- traverse (eval named rec sub env []) args
                                pure (unload stk
                                          (CApp fc (CRef nfc n) args'))
           eval named rec sub env
                (!(traverse (eval named rec sub env []) args) ++ stk) f
  eval named rec sub env stk (CApp fc f args)
      = eval named rec sub env
             (!(traverse (eval named rec sub env []) args) ++ stk) f
  eval named rec sub env stk (CCon fc n ci t args)
      = pure $ unload stk $ CCon fc n ci t !(traverse (eval named rec sub env []) args)
  eval named rec sub env stk (COp fc p args)
      = pure $ unload stk $ COp fc p !(traverseVect (eval named rec sub env []) args)
  eval named rec sub env stk (CExtPrim fc p args)
      = pure $ unload stk $ CExtPrim fc p !(traverse (eval named rec sub env []) args)
  eval named rec sub env stk (CForce fc lr e)
      = case !(eval named rec sub env [] e) of
             CDelay _ _ e' => evalNamed rec stk e'
             res => pure $ unload stk (CForce fc lr res) -- change this to preserve laziness semantics
  eval named rec sub env stk (CDelay fc lr e)
      = pure $ unload stk (CDelay fc lr !(eval named rec sub env [] e))
  eval {vars} {params} named rec sub env stk (CConCase fc sc alts def)
      = do sc' <- eval named rec sub env [] sc
           let env' = update sc env sc'
           Nothing <- pickAlt named rec sub env' stk sc' alts def | Just val => pure val
           def' <- traverseOpt (eval named rec sub env' stk) def
           pure $ caseOfCase $ CConCase fc sc'
                     !(traverse (evalAlt named fc rec sub env' stk) alts)
                     def'
    where
      updateLoc : {idx : _} ->
                  (0 p : IsVar x idx (vs ++ params)) ->
                  EEnv vs -> Val -> EEnv vs
      updateLoc p [] val = []
      updateLoc First (e :: env) val = val :: env
      updateLoc (Later p) (e :: env) val = e :: updateLoc p env val

      update : CExp (vs ++ params) -> EEnv vs -> Val -> EEnv vs
      update (CLocal _ p) env sc = updateLoc p env sc
      update _ env _ = env

  eval named rec sub env stk (CConstCase fc sc alts def)
      = do sc' <- eval named rec sub env [] sc
           Nothing <- pickConstAlt named rec sub env stk sc' alts def | Just val => pure val
           def' <- traverseOpt (eval named rec sub env stk) def
           pure $ caseOfCase $ CConstCase fc sc'
                         !(traverse (evalConstAlt named rec sub env stk) alts)
                         def'
  eval named rec sub env stk (CPrimVal fc c) = pure $ unload stk $ CPrimVal fc c
  eval named rec sub env stk (CErased fc) = pure $ unload stk $ CErased fc
  eval named rec sub env stk (CCrash fc str) = pure $ unload stk $ CCrash fc str

  -- This is hopefully a temporary hack, giving a special case for io_bind.
  -- Currently the elaborator is a bit cautious about inlining case blocks
  -- in case they duplicate work. We should fix that, to decide more accurately
  -- whether they're safe to inline, but until then this gives such a huge
  -- boost by removing unnecessary lambdas that we'll keep the special case.
  evalRef : {0 vars, params : Scope} ->
            {auto c : Ref Ctxt Defs} ->
            {auto l : Ref LVar Int} ->
            List Name -> EEnv vars -> Stack -> FC -> Name -> Core Val
  evalRef {vars} {params} rec env stk fc n = do
        when (n == NS primIONS (UN $ Basic "io_bind")) $
          log "compiler.inline.io_bind" 50 $
            "Attempting to inline io_bind, its stack is: \{show stk}"
        case (n == NS primIONS (UN $ Basic "io_bind"), stk) of
          (True, act :: cont :: world :: stk) =>
                 do xn <- genVar "act" Nothing
                    sc <- evalNamed rec [] (CApp fc cont [CRef fc xn, world])
                    pure $ unload stk $
                             CLet fc xn NotInline
                               (CApp fc act [world])
                               (anyScope sc)
          (True, [act, cont]) =>
                 do wn <- genVar "world" Nothing
                    xn <- genVar "act" Nothing
                    let world : Val := CRef fc wn
                    sc <- evalNamed rec [] (CApp fc cont [CRef fc xn, world])
                    pure $ CLam fc wn
                         $ anyScope
                         $ CLet fc xn NotInline (CApp fc act [world])
                         $ anyScope sc
          (_,_) =>
             do defs <- get Ctxt
                Just gdef <- lookupCtxtExact n (gamma defs)
                  | Nothing => pure (unload stk (CRef fc n))
                let Just def = compexpr gdef
                  | Nothing => pure (unload stk (CRef fc n))
                let arity = getArity def
                let gdefFlags = flags gdef
                if (Inline `elem` gdefFlags)
                    && (not (n `elem` rec))
                    && (not (NoInline `elem` gdefFlags))
                   then do ap <- tryApply {vars} {params} (n :: rec) stk env def
                           case ap of
                             Just v => pure v
                             Nothing =>
                               if gotWorld def && S (length stk) == arity
                                  then lacksWorld (n :: rec) arity def
                                  else pure $ unloadApp arity stk (CRef fc n)
                   else pure $ unloadApp arity stk (CRef fc n)
    where
      -- A function that was given the world (see Compiler.Opts.EtaIO),
      -- applied to all its arguments but the world, as it was inlined before
      -- it was given the world: it is inlined in a lambda of the world.  Its
      -- arguments are computed outside the lambda (unless they are cheap,
      -- `dupOk`), once, as they were by the application of before.
      lacksWorld : List Name -> Nat -> CDef -> Core Val
      lacksWorld rec arity def
          = do (stk', shared) <- bindArgs stk
               wn <- genVar "world" Nothing
               Just v <- tryApply {vars} {params} rec (stk' ++ [CRef fc wn]) env def
                    | Nothing => pure (unloadApp arity stk (CRef fc n))
               pure $ foldr (\(xn, e), sc => CLet fc xn YesInline e (anyScope sc))
                            (CLam fc wn (anyScope v)) shared
        where
          bindArgs : Stack -> Core (Stack, List (Name, Val))
          bindArgs [] = pure ([], [])
          bindArgs (a :: as)
              = do (as', shared) <- bindArgs as
                   if dupOk a
                      then pure (a :: as', shared)
                      else do xn <- genVar "parg" Nothing
                              pure (CRef fc xn :: as', (xn, a) :: shared)

  extendLoc : {auto l : Ref LVar Int} ->
              (named : Bool) -> FC -> Subst -> EEnv vars -> (args' : List Name) ->
              Core (List Name, Subst, EEnv (args' ++ vars))
  extendLoc named fc sub env [] = pure ([], sub, env)
  extendLoc named fc sub env (n :: ns)
      = do xn <- genVar "cv" (Just (shownAs n))
           (xns, sub', env') <- extendLoc named fc sub env ns
           let v = CRef fc xn
           pure (xn :: xns, bindVar named n v sub', v :: env')

  evalAlt : {0 vars, params : Scope} ->
            {auto c : Ref Ctxt Defs} ->
            {auto l : Ref LVar Int} ->
            (named : Bool) ->
            FC -> List Name -> Subst -> EEnv vars -> Stack -> CConAlt (vars ++ params) ->
            Core (CConAlt [])
  evalAlt {vars} {params} named fc rec sub env stk (MkConAlt n ci t args sc)
      = do (xns, sub', env') <- extendLoc named fc sub env args
           scEval <- eval {params} named rec sub' env' stk
                          (rewrite sym (appendAssociative args vars params) in sc)
           pure $ MkConAlt n ci t xns (anyScope scEval)

  evalConstAlt : {0 vars, params : Scope} ->
                 {auto c : Ref Ctxt Defs} ->
                 {auto l : Ref LVar Int} ->
                 (named : Bool) ->
                 List Name -> Subst -> EEnv vars -> Stack -> CConstAlt (vars ++ params) ->
                 Core (CConstAlt [])
  evalConstAlt named rec sub env stk (MkConstAlt c sc)
      = MkConstAlt c <$> eval named rec sub env stk sc

  pickAlt : {0 vars, params : Scope} ->
            {auto c : Ref Ctxt Defs} ->
            {auto l : Ref LVar Int} ->
            (named : Bool) ->
            List Name -> Subst -> EEnv vars -> Stack ->
            Val -> List (CConAlt (vars ++ params)) ->
            Maybe (CExp (vars ++ params)) ->
            Core (Maybe Val)
  pickAlt named rec sub env stk (CCon fc n ci t args) [] def
      = traverseOpt (eval named rec sub env stk) def
  pickAlt {vars} {params} named rec sub env stk con@(CCon fc n ci t args) (MkConAlt n' _ t' args' sc :: alts) def
      = if matches n t n' t'
           then case checkLengthMatch args args' of
                     Nothing => pure Nothing
                     Just m =>
                         do let env' : EEnv (args' ++ vars)
                                   = extend env args args' m
                            let sub' = if named then extendSubst sub args args' else sub
                            pure $ Just !(eval {params} named rec sub' env' stk
                                    (rewrite sym (appendAssociative args' vars params) in
                                             sc))
           else pickAlt named rec sub env stk con alts def
    where
      matches : Name -> Maybe Int -> Name -> Maybe Int -> Bool
      matches _ (Just t) _ (Just t') = t == t'
      matches n Nothing n' Nothing = n == n'
      matches _ _ _ _ = False
  pickAlt named rec sub env stk _ _ _ = pure Nothing

  pickConstAlt : {0 vars, params : Scope} ->
                 {auto c : Ref Ctxt Defs} ->
                 {auto l : Ref LVar Int} ->
                 (named : Bool) ->
                 List Name -> Subst -> EEnv vars -> Stack ->
                 Val -> List (CConstAlt (vars ++ params)) ->
                 Maybe (CExp (vars ++ params)) ->
                 Core (Maybe Val)
  pickConstAlt named rec sub env stk (CPrimVal fc c) [] def
      = traverseOpt (eval named rec sub env stk) def
  pickConstAlt named rec sub env stk (CPrimVal fc c) (MkConstAlt c' sc :: alts) def
      = if c == c'
           then Just <$> eval named rec sub env stk sc
           else pickConstAlt named rec sub env stk (CPrimVal fc c) alts def
  pickConstAlt named rec sub env stk _ _ _ = pure Nothing

-- Give the variables of code that `eval` made their de Bruijn indices, with
-- `d` binders in scope: the variable bound at depth `l` (in `lvls`) has the
-- index `d - l - 1`, the argument `i` of the definition the index `d + i`.
-- The binders get the names they are shown as.
mutual
  finalise : IntMap Nat -> Nat -> CExp ws -> CExp vs
  finalise lvls d (CLocal fc p)
      = CCrash fc "INTERNAL ERROR: a de Bruijn index in inlined code"
  finalise lvls d (CRef fc n)
      = case isParam n of
             Just i => mkLocal fc (d + i)
             Nothing =>
                case varNum n >>= \i => lookup i lvls of
                     Just l => mkLocal fc (minus d (S l))
                     Nothing => CRef fc n
    where
      mkLocal : FC -> Nat -> CExp vs
      mkLocal fc i = CLocal {x = n} {idx = i} fc (believe_me ())
  finalise lvls d (CLam fc x sc)
      = CLam fc (shownAs x) (finalise (bindNum x d lvls) (S d) sc)
  finalise lvls d (CLet fc x inl val sc)
      = CLet fc (shownAs x) inl (finalise lvls d val)
                                (finalise (bindNum x d lvls) (S d) sc)
  finalise lvls d (CApp fc f args)
      = CApp fc (finalise lvls d f) (map (finalise lvls d) args)
  finalise lvls d (CCon fc n ci t args)
      = CCon fc n ci t (map (finalise lvls d) args)
  finalise lvls d (COp fc op args) = COp fc op (map (finalise lvls d) args)
  finalise lvls d (CExtPrim fc p args)
      = CExtPrim fc p (map (finalise lvls d) args)
  finalise lvls d (CForce fc lr e) = CForce fc lr (finalise lvls d e)
  finalise lvls d (CDelay fc lr e) = CDelay fc lr (finalise lvls d e)
  finalise lvls d (CConCase fc sc alts def)
      = CConCase fc (finalise lvls d sc) (map (finaliseConAlt lvls d) alts)
                 (map (finalise lvls d) def)
  finalise lvls d (CConstCase fc sc alts def)
      = CConstCase fc (finalise lvls d sc) (map (finaliseConstAlt lvls d) alts)
                   (map (finalise lvls d) def)
  finalise lvls d (CPrimVal fc c) = CPrimVal fc c
  finalise lvls d (CErased fc) = CErased fc
  finalise lvls d (CCrash fc msg) = CCrash fc msg

  finaliseConAlt : IntMap Nat -> Nat -> CConAlt ws -> CConAlt vs
  finaliseConAlt lvls d (MkConAlt n ci t args sc)
      = let d' = d + length args in
            MkConAlt n ci t (map shownAs args)
                     (finalise (bindArgs (minus d' 1) lvls args) d' sc)
    where
      -- the first argument is the innermost binder
      bindArgs : Nat -> IntMap Nat -> List Name -> IntMap Nat
      bindArgs l lvls [] = lvls
      bindArgs l lvls (a :: as) = bindArgs (minus l 1) (bindNum a l lvls) as

  finaliseConstAlt : IntMap Nat -> Nat -> CConstAlt ws -> CConstAlt vs
  finaliseConstAlt lvls d (MkConstAlt c sc) = MkConstAlt c (finalise lvls d sc)


-- Inlining may have messed with function arity (e.g. by adding lambdas to
-- the LHS to avoid needlessly making a closure) so fix them up here. This
-- needs to be right because typically back ends need to know whether a
-- name is under- or over-applied
fixArityTm : {auto c : Ref Ctxt Defs} ->
             CExp vars -> List (CExp vars) -> Core (CExp vars)
fixArityTm (CRef fc n) args
    = do defs <- get Ctxt
         Just gdef <- lookupCtxtExact n (gamma defs)
              | Nothing => pure (unload args (CRef fc n))
         let arity = case compexpr gdef of
                          Just def => getArity def
                          _ => 0
         -- A partial application lacks arguments, which `expandToArity` adds
         -- by lambdas, so that the arguments that it is given are computed
         -- when it is applied, every time.  When the function was given the
         -- world (see Compiler.Opts.EtaIO), it was a full application before,
         -- whose arguments were computed once, and an action made by it (`let
         -- act = loop (expensive x) in act >> act`) shares them: they are
         -- computed outside the lambda (unless they are cheap, `dupOk`).
         if length args < arity && maybe False gotWorld (compexpr gdef)
            then pure $ shareArgs 0 arity (CRef fc n) [] args
            else pure $ expandToArity arity (CApp fc (CRef fc n) []) args
  where
    -- `f` applied to the arguments `done` (reversed) and `rest`, whose
    -- arguments that are not values are let bound
    shareArgs : Int -> Nat -> CExp vs -> List (CExp vs) -> List (CExp vs) -> CExp vs
    shareArgs i arity f done [] = expandToArity arity (CApp fc f []) (reverse done)
    shareArgs i arity f done (a :: rest)
        = if dupOk a
             then shareArgs i arity f (a :: done) rest
             else CLet fc (MN "parg" i) YesInline a
                    (shareArgs (i + 1) arity (weaken f) (CLocal fc First :: map weaken done)
                               (map weaken rest))
fixArityTm (CLam fc x sc) args
    = pure $ expandToArity Z (CLam fc x !(fixArityTm sc [])) args
fixArityTm (CLet fc x inl val sc) args
    = pure $ expandToArity Z
                 (CLet fc x inl !(fixArityTm val []) !(fixArityTm sc [])) args
fixArityTm outf@(CApp fc f@(CRef _ n) fargs) args
    = do defs <- get Ctxt
         -- If we don't know 'n' leave the arity alone, because it's
         -- a name from another module where the job is already done
         Just gdef <- lookupCtxtExact n (gamma defs)
              | Nothing => pure (unload args outf)
         fixArityTm f (!(traverse (\tm => fixArityTm tm []) fargs) ++ args)
fixArityTm (CApp fc f fargs) args
    = fixArityTm f (!(traverse (\tm => fixArityTm tm []) fargs) ++ args)
fixArityTm (CCon fc n ci t args) []
    = pure $ CCon fc n ci t !(traverse (\tm => fixArityTm tm []) args)
fixArityTm (COp fc op args) []
    = pure $ COp fc op !(traverseArgs args)
  where
    traverseArgs : Vect n (CExp vs) -> Core (Vect n (CExp vs))
    traverseArgs [] = pure []
    traverseArgs (a :: as) = pure $ !(fixArityTm a []) :: !(traverseArgs as)
fixArityTm (CExtPrim fc p args) []
    = pure $ CExtPrim fc p !(traverse (\tm => fixArityTm tm []) args)
fixArityTm (CForce fc lr tm) args
    = pure $ expandToArity Z (CForce fc lr !(fixArityTm tm [])) args
fixArityTm (CDelay fc lr tm) args
    = pure $ expandToArity Z (CDelay fc lr !(fixArityTm tm [])) args
fixArityTm (CConCase fc sc alts def) args
    = pure $ expandToArity Z
              (CConCase fc !(fixArityTm sc [])
                           !(traverse fixArityAlt alts)
                           !(traverseOpt (\tm => fixArityTm tm []) def)) args
  where
    fixArityAlt : CConAlt vars -> Core (CConAlt vars)
    fixArityAlt (MkConAlt n ci t a sc)
        = pure $ MkConAlt n ci t a !(fixArityTm sc [])
fixArityTm (CConstCase fc sc alts def) args
    = pure $ expandToArity Z
              (CConstCase fc !(fixArityTm sc [])
                             !(traverse fixArityConstAlt alts)
                             !(traverseOpt (\tm => fixArityTm tm []) def)) args
  where
    fixArityConstAlt : CConstAlt vars -> Core (CConstAlt vars)
    fixArityConstAlt (MkConstAlt c sc)
        = pure $ MkConstAlt c !(fixArityTm sc [])
fixArityTm t [] = pure t
fixArityTm t args = pure $ expandToArity Z t args

export
fixArityExp : {auto c : Ref Ctxt Defs} ->
              CExp vars -> Core (CExp vars)
fixArityExp tm = fixArityTm tm []

fixArity : {auto c : Ref Ctxt Defs} ->
           CDef -> Core CDef
fixArity (MkFun args exp) = pure $ MkFun args !(fixArityTm exp [])
fixArity (MkError exp) = pure $ MkError !(fixArityTm exp [])
fixArity d = pure d

-- TODO: get rid of this `done` by making the return `args'` runtime irrelevant?
getLams : {done : _} -> SizeOf done ->
          Int -> SubstCEnv done args -> CExp (done ++ args) ->
          (args' ** (SizeOf args', SubstCEnv args' args, CExp (args' ++ args)))
getLams {done} d i env (CLam fc x sc)
    = getLams {done = x :: done} (suc d) (i + 1) (CRef fc (MN "ext" i) :: env) sc
getLams {done} d i env sc = (done ** (d, env, sc))

mkBounds : (xs : _) -> Bounds xs
mkBounds [] = None
mkBounds (x :: xs) = Add x x (mkBounds xs)

-- TODO `getNewArgs` is always used in reverse, revisit!
getNewArgs : {done : _} ->
             SubstCEnv done args -> Scope
getNewArgs [] = []
getNewArgs (CRef _ n :: xs) = n :: getNewArgs xs
getNewArgs {done = x :: xs} (_ :: sub) = x :: getNewArgs sub

-- Move any lambdas in the body of the definition into the lhs list of vars.
-- Annoyingly, the indices will need fixing up because the order in the top
-- level definition goes left to right (i.e. first argument has lowest index,
-- not the highest, as you'd expect if they were all lambdas).
mergeLambdas : (args : Scope) -> CExp args -> (args' ** CExp args')
mergeLambdas args (CLam fc x sc)
    = let (args' ** (s, env, exp')) = getLams zero 0 Subst.empty (CLam fc x sc)
          expNs = substs s env exp'
          newArgs = reverse $ getNewArgs env
          expLocs = mkLocals (mkSizeOf args) {vars = []} (mkBounds newArgs)
                             (rewrite appendNilRightNeutral args in expNs) in
          (_ ** expLocs)
mergeLambdas args exp = (args ** exp)

||| Inline all inlinable functions into the given expression.
||| @ n the function name
||| @ exp the body of the function
-- The function itself is not inlined into its body: in a group of inlinable
-- functions that call each other, its body would get a copy of itself
-- through the others in every round of the transformations, and every
-- function that calls it a copy of all that.
doEval : {args : _} ->
         {auto c : Ref Ctxt Defs} ->
         (n : Name) -> (exp : CExp args) -> Core (CExp args)
doEval n exp
    = do l <- newRef LVar (the Int 0)
         log "compiler.inline.eval" 10 (show n ++ ": " ++ show exp)
         fn <- toFullNames n
         res <- eval {vars = []} {params = args} False [fn] IntMap.empty [] [] exp
         let exp' = finalise IntMap.empty 0 res
         log "compiler.inline.eval" 10 ("Inlined: " ++ show exp')
         pure exp'

inline : {auto c : Ref Ctxt Defs} ->
         Name -> CDef -> Core CDef
inline n (MkFun args def)
    = pure $ MkFun args !(doEval n def)
inline n d = pure d

-- merge lambdas from expression into top level arguments
mergeLam : {auto c : Ref Ctxt Defs} ->
           CDef -> Core CDef
mergeLam (MkFun args def)
    = do let (args' ** exp') = mergeLambdas args def
         pure $ MkFun args' exp'
mergeLam d = pure d

mutual
  addRefs : NameMap Bool -> CExp vars -> NameMap Bool
  addRefs ds (CRef _ n) = insert n False ds
  addRefs ds (CLam _ _ sc) = addRefs ds sc
  addRefs ds (CLet _ _ _ val sc) = addRefs (addRefs ds val) sc
  addRefs ds (CApp _ f args) = addRefsArgs (addRefs ds f) args
  addRefs ds (CCon _ n _ _ args) = addRefsArgs (insert n False ds) args
  addRefs ds (COp _ _ args) = addRefsArgs ds (toList args)
  addRefs ds (CExtPrim _ _ args) = addRefsArgs ds args
  addRefs ds (CForce _ _ e) = addRefs ds e
  addRefs ds (CDelay _ _ e) = addRefs ds e
  addRefs ds (CConCase _ sc alts def)
      = let ds' = maybe ds (addRefs ds) def in
            addRefsConAlts (addRefs ds' sc) alts
  addRefs ds (CConstCase _ sc alts def)
      = let ds' = maybe ds (addRefs ds) def in
            addRefsConstAlts (addRefs ds' sc) alts
  addRefs ds tm = ds

  addRefsArgs : NameMap Bool -> List (CExp vars) -> NameMap Bool
  addRefsArgs ds [] = ds
  addRefsArgs ds (a :: as) = addRefsArgs (addRefs ds a) as

  addRefsConAlts : NameMap Bool -> List (CConAlt vars) -> NameMap Bool
  addRefsConAlts ds [] = ds
  addRefsConAlts ds (MkConAlt n _ _ _ sc :: rest)
      = addRefsConAlts (addRefs (insert n False ds) sc) rest

  addRefsConstAlts : NameMap Bool -> List (CConstAlt vars) -> NameMap Bool
  addRefsConstAlts ds [] = ds
  addRefsConstAlts ds (MkConstAlt _ sc :: rest)
      = addRefsConstAlts (addRefs ds sc) rest

getRefs : CDef -> NameMap Bool
getRefs (MkFun args exp) = addRefs empty exp
getRefs _ = empty

export
inlineDef : {auto c : Ref Ctxt Defs} ->
            Name -> Core ()
inlineDef n
    = do defs <- get Ctxt
         Just def <- lookupCtxtExact n (gamma defs) | Nothing => pure ()
         let Just cexpr = compexpr def              | Nothing => pure ()
         setCompiled n !(inline n cexpr)

-- Update the names a function refers to at runtime based on the transformation
-- results (saves generating code unnecessarily).
updateCallGraph : {auto c : Ref Ctxt Defs} ->
                  Name -> Core ()
updateCallGraph n
    = do defs <- get Ctxt
         Just def <- lookupCtxtExact n (gamma defs) | Nothing => pure ()
         let Just cexpr =  compexpr def             | Nothing => pure ()
         let refs = getRefs cexpr
         ignore $ addDef n ({ refersToRuntimeM := Just refs } def)

export
fixArityDef : {auto c : Ref Ctxt Defs} ->
              Name -> Core ()
fixArityDef n
    = do defs <- get Ctxt
         Just def <- lookupCtxtExact n (gamma defs) | Nothing => pure ()
         let Just cexpr =  compexpr def             | Nothing => pure ()
         setCompiled n !(fixArity cexpr)

export
mergeLamDef : {auto c : Ref Ctxt Defs} ->
              Name -> Core ()
mergeLamDef n
    = do defs <- get Ctxt
         Just def <- lookupCtxtExact n (gamma defs)
              | Nothing => pure ()
         let PMDef pi _ _ _ _ = definition def
              | _ => pure ()
         if not (isNil (incrementalCGs !getSession)) &&
                externalDecl pi -- better keep it at arity 0
            then pure ()
            else do let Just cexpr =  compexpr def
                             | Nothing => pure ()
                    setCompiled n !(mergeLam cexpr)

export
addArityHash : {auto c : Ref Ctxt Defs} ->
               Name -> Core ()
addArityHash n
    = do defs <- get Ctxt
         Just def <- lookupCtxtExact n (gamma defs) | Nothing => pure ()
         let Just cexpr =  compexpr def             | Nothing => pure ()
         let MkFun args _ = cexpr                   | _ => pure ()
         case collapseDefault $ visibility def of
              Private => pure ()
              _ => addHash (n, length args)

export
compileAndInlineAll : {auto c : Ref Ctxt Defs} ->
                      Core ()
compileAndInlineAll
    = do defs <- get Ctxt
         let ns = keys (toIR defs)
         cns <- filterM nonErased ns

         traverse_ compileDef cns
         traverse_ rewriteIdentityFlag cns
         transform 3 cns -- number of rounds to run transformations.
                         -- This seems to be the point where not much useful
                         -- happens any more.
         traverse_ updateCallGraph cns
         -- in incremental mode, add the arity of the definitions to the hash,
         -- because if these change we need to recompile dependencies
         -- accordingly
         unless (isNil (incrementalCGs !getSession)) $
           traverse_ addArityHash cns
  where
    transform : Nat -> List Name -> Core ()
    transform Z cns = pure ()
    transform (S k) cns
        = do traverse_ inlineDef cns
             traverse_ mergeLamDef cns
             traverse_ caseLamDef cns
             -- (in the last round, once the lambdas that the inliner makes
             -- are merged: see Compiler.Opts.EtaIO)
             when (k == Z) $ etaIO cns
             traverse_ fixArityDef cns
             traverse_ inlineHeuristics cns
             traverse_ constantFold cns
             traverse_ setIdentity cns
             transform k cns

    nonErased : Name -> Core Bool
    nonErased n
        = do defs <- get Ctxt
             Just gdef <- lookupCtxtExact n (gamma defs)
                  | Nothing => pure False
             pure (multiplicity gdef /= erased)
