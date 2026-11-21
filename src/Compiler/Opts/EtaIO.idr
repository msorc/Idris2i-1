module Compiler.Opts.EtaIO

-- Give the functions in IO the world as a parameter.
--
-- An action of `IO a` is, at run time, a function of the world (`IO a` is a
-- newtype over `PrimIO a = (1 w : %World) -> IORes a`).  A function whose
-- body starts with a bind (`f x = do ...`) gets the world as its last
-- parameter from the inliner (`io_bind` gives a lambda, which `mergeLambdas`
-- moves into the parameters), and so does a function whose body is a case
-- whose every alternative is a lambda (`caseLam`).  A function whose body
-- gives an action without a lambda first does not:
--
--     loop acc n = if n == 0 then pure acc else loop (acc + n) (n - 1)
--
-- is a case whose alternatives are a lambda (`pure acc`) and a call that gives
-- an action.  It is compiled to a function of two parameters, which makes a
-- closure for the world to be given to, and its result is that closure, which
-- holds the result boxed.  Here such a function is given the world as one more
-- parameter, and the world is pushed into its body, to where the actions are:
--
--     loop acc n w = if n == 0 then MkIORes acc w else loop (acc + n) (n - 1) w
--
-- When it is safe
-- ---------------
-- `f x w = e w` is the same as `f x = e` when `f x` is applied to the world
-- at once.  It differs when the partial application `f x` (an action) is made
-- once and run many times, or never: what `e` computes before it gives its
-- action (before the lambda of the world) was computed once, when `f x` was
-- made, and is computed at every run once `f` takes the world.  In
--
--     f x = let y = expensive x in \w => ...
--
-- `let act = f x in act >> act` would compute `expensive x` twice.  So a
-- function is given the world only when what its body does before it gives
-- its action is cheap (see `cheap`): its value is bounded work with no effect,
-- primitive operations on fixed width numbers and on variables, constructors
-- and closures of such values, partial applications of known functions, and
-- cases and lets of such values.  The actions it gives (in tail position, see
-- `pushable`) are lambdas (of the world), variables, partial applications of
-- functions that take the world after the arguments given (such as `loop
-- (acc + n) (n - 1)`, which this pass gives the world to) and crashes.  A
-- function that calls a function of which a variable is the value (`k x`, a
-- callback), or a function that is not known to take more arguments, before
-- the world, is not given it: that call could do any work.  So is a function
-- whose body forces a lazy value, delays one (its thunk would be one per run,
-- so its value would be computed at every run) or calls a foreign function.
-- So the work that is repeated at every run of a shared action is a constant
-- number of cheap operations, as for any closure of the language.  A crash
-- that `f x` gave when it was made is given when the action is run.
--
-- The functions of a module that call each other are given the world
-- together: a call `g a b` that gives an action is cheap when `g` is given
-- the world (it is then a partial application), which is decided for all of
-- them at once (the largest set of such functions whose bodies are cheap when
-- the calls of the functions of the set are; see `etaIO`).  A function of
-- another module was given the world when that module was compiled, and its
-- arity says so.
--
-- The partial applications of a function given the world
-- ------------------------------------------------------
-- A call `loop (expensive x) 3` that was a full application (an action,
-- computed once) lacks the world once `loop` takes it.  `fixArityTm`
-- (Compiler.Inline) makes a lambda of a partial application, in which the
-- arguments would be computed at every run: for a function given the world
-- here (whose last parameter is `ioetaWorld`), the arguments that are not
-- cheap (`dupOk`) are let bound outside the lambda, so that they are computed
-- once, as before.  The inliner inlines such a function (when it is to be
-- inlined) when it lacks only the world, in a lambda of the world, with the
-- same lets.  (A partial application of a function whose world is a parameter
-- for another reason, `f x = do ...`, is a lambda in which the arguments are
-- computed at every run, as it was before this pass.)
--
-- This pass runs in the last round of the transformations (see
-- `compileAndInlineAll`), once the lambdas that the inliner makes (of
-- `io_bind`, `pure`, of lets that it inlines) are merged into the parameters,
-- so that it gives the world only to the functions that would not have got it
-- otherwise.

import Core.CompileExpr
import Core.Context
import Core.Context.Log
import Core.Env
import Core.Normalise
import Core.Options
import Core.Value

import Data.Vect

import Libraries.Data.NameMap
import Libraries.Data.NatSet
import Libraries.Data.List.SizeOf

%default covering

||| The name of the parameter of the world that this pass gives a function
export
ioetaWorld : Name
ioetaWorld = MN "ioeta" 0

||| Whether the function was given the world by this pass (its last parameter
||| is `ioetaWorld`).  A partial application of such a function that lacks
||| only the world was a full application before, which computed its
||| arguments once: see `fixArityTm` in Compiler.Inline.  (A function whose
||| actions are all lambdas, after cases and no let, is given a parameter of
||| another name: it is one that the inliner gives the world to, by
||| `caseLam` and `mergeLambdas`, and its partial applications are as those
||| of the functions that it gives the world to.)
export
gotWorld : CDef -> Bool
gotWorld (MkFun args _) = last' args == Just ioetaWorld
gotWorld _ = False

arityOf : CDef -> Nat
arityOf (MkFun args _) = length args
arityOf (MkCon _ arity _ _) = arity
arityOf (MkForeign _ args _) = length args
arityOf (MkError _) = 0

-- The head of an application and all its arguments (`(f a) b` is `f a b`).
spine : CExp vs -> List (CExp vs) -> (CExp vs, List (CExp vs))
spine (CApp _ f args) acc = spine f (args ++ acc)
spine f acc = (f, acc)

-- A primitive operation that does a constant amount of work and allocates no
-- string.  (A crash, the missing case of a `div` or `mod` for instance, is
-- not work that is computed again.)
cheapOp : PrimFn ar -> Bool
cheapOp StrTail = False
cheapOp StrCons = False
cheapOp StrAppend = False
cheapOp StrReverse = False
cheapOp StrSubstr = False
cheapOp (Cast StringType _) = False
cheapOp (Cast _ StringType) = False
cheapOp _ = True

||| Whether computing the expression again, at every run of an action that
||| it is an argument of, costs little and has no effect: a variable, a
||| constant, a lambda, a primitive operation that does a constant amount of
||| work, a constructor, of such values.
export
dupOk : CExp vs -> Bool
dupOk (CLocal {}) = True
dupOk (CRef {}) = True
dupOk (CPrimVal {}) = True
dupOk (CErased {}) = True
dupOk (CLam {}) = True
dupOk (COp _ op args) = cheapOp op && all dupOk args
dupOk (CCon _ _ _ _ args) = all dupOk args
dupOk _ = False

-- What is known of a function called in a body: its arity, and whether it is
-- one of the functions of the module that may be given the world (by its
-- full name).
record Callee where
  constructor MkCallee
  arity : Nat
  candidate : Maybe Name

-- The conditions on the functions of the module that are given the world for
-- an expression to be what is needed (cheap, or pushable), or Nothing if it
-- never is.
Deps : Type
Deps = Maybe (List Name)

both : Deps -> Deps -> Deps
both (Just xs) (Just ys) = Just (xs ++ ys)
both _ _ = Nothing

alls : List Deps -> Deps
alls = foldr both (Just [])

parameters {auto c : Ref Ctxt Defs} (cands : NameMap ())

  callee : Name -> Core (Maybe Callee)
  callee n
      = do defs <- get Ctxt
           Just gdef <- lookupCtxtExact n (gamma defs)
                | Nothing => pure Nothing
           let Just def = compexpr gdef
                | Nothing => pure Nothing
           fn <- toFullNames n
           pure $ Just $ MkCallee (arityOf def)
                    (map (const fn) (NameMap.lookup fn cands))

  -- `f args` (with `length args` arguments) as a value: cheap when it is
  -- a partial application, which it is if `f` takes more arguments, or if
  -- `f` takes as many and is given the world.
  partialApp : Name -> Nat -> Core Deps
  partialApp f k
      = do Just ce <- callee f
                | Nothing => pure Nothing
           pure $ if k < ce.arity
                     then Just []
                     else if k == ce.arity
                             then map (\n => [n]) ce.candidate
                             else Nothing

  mutual
    -- Whether evaluating the expression does a constant amount of work, with
    -- no effect (see the comment at the top).
    cheap : CExp vs -> Core Deps
    cheap (CLocal {}) = pure (Just [])
    cheap (CRef _ n) = partialApp n 0
    cheap (CLam {}) = pure (Just [])
    cheap (CLet _ _ _ val sc) = pure $ both !(cheap val) !(cheap sc)
    cheap tm@(CApp {})
        = case spine tm [] of
               (CRef _ f, args) =>
                   pure $ both !(partialApp f (length args)) !(cheaps args)
               _ => pure Nothing
    cheap (CCon _ _ _ _ args) = cheaps args
    cheap (COp _ op args) = if cheapOp op then cheaps (toList args) else pure Nothing
    cheap (CConCase _ sc alts def)
        = pure $ alls [ !(cheap sc)
                      , alls !(traverse (\(MkConAlt _ _ _ _ e) => cheap e) alts)
                      , !(maybe (pure (Just [])) cheap def) ]
    cheap (CConstCase _ sc alts def)
        = pure $ alls [ !(cheap sc)
                      , alls !(traverse (\(MkConstAlt _ e) => cheap e) alts)
                      , !(maybe (pure (Just [])) cheap def) ]
    cheap (CPrimVal {}) = pure (Just [])
    cheap (CErased {}) = pure (Just [])
    cheap (CCrash {}) = pure (Just [])
    -- (a thunk made at every run would compute its value at every run)
    cheap (CDelay {}) = pure Nothing
    cheap (CForce {}) = pure Nothing
    cheap (CExtPrim {}) = pure Nothing

    cheaps : List (CExp vs) -> Core Deps
    cheaps args = pure $ alls !(traverse cheap args)

  -- Whether the world can be pushed into the expression, whose value is an
  -- action, at a cost that is cheap.
  pushable : CExp vs -> Core Deps
  pushable (CLocal {}) = pure (Just [])
  pushable (CRef _ n) = partialApp n 0
  pushable (CLam {}) = pure (Just [])
  pushable (CLet _ _ _ val sc) = pure $ both !(cheap val) !(pushable sc)
  pushable tm@(CApp {})
      = case spine tm [] of
             (CRef _ f, args) =>
                 pure $ both !(partialApp f (length args)) !(cheaps args)
             _ => pure Nothing
  pushable (CConCase _ sc alts def)
      = pure $ alls [ !(cheap sc)
                    , alls !(traverse (\(MkConAlt _ _ _ _ e) => pushable e) alts)
                    , !(maybe (pure (Just [])) pushable def) ]
  pushable (CConstCase _ sc alts def)
      = pure $ alls [ !(cheap sc)
                    , alls !(traverse (\(MkConstAlt _ e) => pushable e) alts)
                    , !(maybe (pure (Just [])) pushable def) ]
  pushable (CCrash {}) = pure (Just [])
  pushable _ = pure Nothing

-- Apply the action that the expression gives to the world (a reference to
-- the name of the new parameter), inside it: into the alternatives of a case,
-- the scope of a let, the body of a lambda.
push : {vs : _} -> CExp [] -> CExp vs -> CExp vs
push w (CLam fc x sc) = substs (suc zero) [anyScope w] sc
  where
    anyScope : CExp [] -> CExp vs
    anyScope = believe_me -- a reference by name, the same in every scope
push w (CLet fc x inl val sc) = CLet fc x inl val (push w sc)
push w (CConCase fc sc alts def)
    = CConCase fc sc (map pushAlt alts) (map (push w) def)
  where
    pushAlt : CConAlt vs -> CConAlt vs
    pushAlt (MkConAlt n ci t args e) = MkConAlt n ci t args (push w e)
push w (CConstCase fc sc alts def)
    = CConstCase fc sc (map (\(MkConstAlt c e) => MkConstAlt c (push w e)) alts)
                 (map (push w) def)
push w tm@(CCrash {}) = tm
push w tm = case spine tm [] of
                 (f, args) => CApp (getFC tm) f (args ++ [believe_me w])

-- Whether the result of the function, after `k` of its arguments, is an
-- action of IO, or of PrimIO (a function of the world).  The arguments are
-- the binders of its type whose positions are not erased (`es`, see
-- `eraseArgs`): the compiled function does not take those.
returnsIO : {auto c : Ref Ctxt Defs} -> NatSet -> Nat -> ClosedTerm -> Core Bool
returnsIO es k ty
    = if !(surelyNot 0 k ty)
         then pure False
         else do defs <- get Ctxt
                 go defs 0 k !(nf defs Env.empty ty)
  where
    -- A look at the type as it is, before it is evaluated: the result is
    -- surely not an action when it is a type constructor other than IO, a
    -- primitive type or a universe.  (A name of a function, `PrimIO a` or an
    -- alias, is evaluated.)
    surelyNot : Nat -> Nat -> Term vs -> Core Bool
    surelyNot i k (Bind _ _ (Pi {}) sc)
        = if i `elem` es
             then surelyNot (S i) k sc
             else case k of
                    S k => surelyNot (S i) k sc
                    Z => pure False
    surelyNot i Z t
        = case getFn t of
               Ref _ (TyCon _) tn =>
                   do NS ns (UN (Basic "IO")) <- toFullNames tn
                           | _ => pure True
                      pure (ns /= primIONS)
               PrimVal {} => pure True
               TType {} => pure True
               _ => pure False
    surelyNot _ _ _ = pure False

    go : Defs -> Nat -> Nat -> ClosedNF -> Core Bool
    go defs i k t@(NBind fc _ (Pi _ _ _ argty) sc)
        = if i `elem` es
             then go defs (S i) k !(sc defs (toClosure defaultOpts Env.empty (Erased fc Placeholder)))
             else case k of
                    S k => go defs (S i) k
                             !(sc defs (toClosure defaultOpts Env.empty (Erased fc Placeholder)))
                    Z => do NPrimVal _ (PrT WorldType) <- evalClosure defs argty
                                 | _ => pure False
                            pure True
    go defs i Z (NTCon _ tn _ [_])
        = do NS ns (UN (Basic "IO")) <- toFullNames tn
                  | _ => pure False
             pure (ns == primIONS)
    go _ _ _ _ = pure False

-- A quick look, before the type is read: whether the function could be one
-- that this pass gives the world to.
mayPush : CExp vs -> Bool
mayPush (CLam {}) = False -- (the world is already a parameter, or is not
                          -- one only because the function is not inlined)
mayPush e = go e
  where
    go : CExp ws -> Bool
    go (CLocal {}) = True
    go (CRef {}) = True
    go (CLam {}) = True
    go (CLet _ _ _ _ sc) = go sc
    go (CApp {}) = True
    go (CConCase _ _ alts def)
        = all (\(MkConAlt _ _ _ _ e) => go e) alts && all go def
    go (CConstCase _ _ alts def)
        = all (\(MkConstAlt _ e) => go e) alts && all go def
    go (CCrash {}) = True
    go _ = False

-- A function of the module that could be given the world: its full name and
-- its resolved one.
candidate : {auto c : Ref Ctxt Defs} -> Name -> Core (Maybe (Name, Name))
candidate n
    = do defs <- get Ctxt
         Just gdef <- lookupCtxtExact n (gamma defs)
              | Nothing => pure Nothing
         let PMDef pi _ _ _ _ = definition gdef
              | _ => pure Nothing
         -- (as mergeLamDef: in incremental mode, keep the arity of a
         -- declaration that is defined in another module)
         let False = not (isNil (incrementalCGs !getSession)) && externalDecl pi
              | True => pure Nothing
         let Just (MkFun args body) = compexpr gdef
              | _ => pure Nothing
         let True = mayPush body
              | False => pure Nothing
         -- A function exported to the host language (`%export`) is called
         -- there by the arity of its type: one more parameter would break
         -- its callers.
         fn <- toFullNames n
         let Nothing = NameMap.lookup fn (foreignExports defs)
              | Just _ => pure Nothing
         True <- returnsIO (eraseArgs gdef) (length args) (type gdef)
              | False => pure Nothing
         pure (Just (fn, n))

-- Give the world to the function `n`, as a last parameter.
expand : {auto c : Ref Ctxt Defs} -> Name -> Core ()
expand n
    = do defs <- get Ctxt
         Just gdef <- lookupCtxtExact n (gamma defs)
              | Nothing => pure ()
         let Just (MkFun args body) = compexpr gdef
              | _ => pure ()
         let fc = getFC body
         -- (see `gotWorld`: the functions whose actions are all lambdas, after
         -- cases only, are those that `mergeLambdas` would give the world to
         -- if `caseLam` had moved the lambdas out of the cases.  A let before
         -- the lambdas is not moved, and the function took no world: an
         -- application that lacks only the world was a full one, whose
         -- arguments were computed once, and must still be.)
         let pn = if allLams body then MN "ext" 0 else ioetaWorld
         let body' = push (CRef fc ioetaWorld) body
         let body'' = mkLocals (mkSizeOf args) {vars = []} (Add pn ioetaWorld None)
                               (rewrite appendNilRightNeutral args in body')
         log "compiler.inline.ioeta" 5 $ "Giving the world to " ++ show !(toFullNames n)
         setCompiled n (MkFun (args ++ [pn]) body'')
  where
    -- Whether the actions of the expression are all lambdas (or crashes),
    -- with no let before them
    allLams : CExp vs -> Bool
    allLams (CLam {}) = True
    allLams (CCrash {}) = True
    allLams (CConCase _ _ alts def)
        = all (\(MkConAlt _ _ _ _ e) => allLams e) alts && all allLams def
    allLams (CConstCase _ _ alts def)
        = all (\(MkConstAlt _ e) => allLams e) alts && all allLams def
    allLams _ = False

||| Give the world as a parameter to the functions `ns` (of a module) whose
||| results are actions of IO and whose bodies give their actions after a
||| cheap computation (see the comment at the top of the module).
export
etaIO : {auto c : Ref Ctxt Defs} -> List Name -> Core ()
etaIO ns
    = do cs <- mapMaybeM candidate ns
         let cands = fromList (map (\(fn, _) => (fn, ())) cs)
         deps <- mapMaybeM (\(fn, n) =>
                    do defs <- get Ctxt
                       Just gdef <- lookupCtxtExact n (gamma defs)
                            | Nothing => pure Nothing
                       let Just (MkFun _ body) = compexpr gdef
                            | _ => pure Nothing
                       Just ds <- pushable cands body
                            | Nothing => pure Nothing
                       pure (Just (fn, n, ds))) cs
         let chosen = fixpoint deps
         traverse_ (\(_, n, _) => expand n) chosen
  where
    -- The largest set of the functions whose conditions are in the set
    fixpoint : List (Name, Name, List Name) -> List (Name, Name, List Name)
    fixpoint fs
        = let set = fromList (map (\(fn, _, _) => (fn, ())) fs)
              fs' = filter (\(_, _, ds) => all (\d => isJust (NameMap.lookup d set)) ds) fs in
              if length fs' == length fs then fs else fixpoint fs'

    mapMaybeM : (a -> Core (Maybe b)) -> List a -> Core (List b)
    mapMaybeM f [] = pure []
    mapMaybeM f (x :: xs)
        = do r <- f x
             rest <- mapMaybeM f xs
             pure (maybe rest (:: rest) r)
