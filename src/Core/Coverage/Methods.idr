||| Which methods of an implementation a function uses, for the totality of
||| interface methods.
|||
||| An implementation of an interface whose methods (or parent
||| implementations) are not all covering carries the `PartialMethods` flag.
||| A function that refers to such an implementation is not covering, as far
||| as the method totality check goes, only if it may use one of those
||| methods.  To see which fields of a dictionary a function may use, we look
||| at what the function does with it:
|||
||| * a `case` on it binds its fields, so the uses of the variables bound
|||   are uses of the fields (this is what the projections of the methods and
|||   of the parent implementations do);
||| * giving it to a function, at a position where the function's definition
|||   is known, uses what that function uses of that argument (worked out in
|||   the same way, given what is used of the function's result);
||| * a constructor applied to it puts it in a field, so the uses of that
|||   field of the result are uses of it (this is how a constraint tuple, or
|||   an implementation built from other implementations, is seen through);
||| * anything else (applying it, storing it under a binder, giving it to a
|||   function whose definition is unknown or which is not applied to all its
|||   arguments, a recursion too deep to follow) uses all of it.
|||
||| Evaluation is strict, so what is evaluated is checked whether or not its
||| value is used: the arguments of a constructor, and the fields of an
||| implementation (a method that is not a function is evaluated with its
||| implementation); only the bodies of lambdas and delayed terms whose values
||| are not used are skipped.
|||
||| A function that is not covering for this reason gets the flag too, so the
||| check crosses modules through the flags in TTC files; what a function uses
||| of its arguments is worked out from its definition, wherever it is, when
||| it is needed.  Everything that is not analysed counts as a use of every
||| field, so the answer is never more permissive than the check per
||| implementation was.
module Core.Coverage.Methods

import Core.Case.CaseTree
import Core.Context
import Core.Context.Log
import Core.Coverage
import Core.TT

import Data.List

import Libraries.Data.NameMap

%default covering

||| What may be used of a value: everything, or some of its fields, by the
||| position of the argument of its constructor, each with what may be used
||| of it.  `Fields []` is nothing.  The fields are in increasing order.
data Demand = All | Fields (List (Nat, Demand))

eqDemand : Demand -> Demand -> Bool
eqDemand All All = True
eqDemand (Fields xs) (Fields ys) = eqFields xs ys
  where
    eqFields : List (Nat, Demand) -> List (Nat, Demand) -> Bool
    eqFields [] [] = True
    eqFields ((i, d) :: xs) ((j, e) :: ys)
        = i == j && eqDemand d e && eqFields xs ys
    eqFields _ _ = False
eqDemand _ _ = False

none : Demand
none = Fields []

showDemand : Demand -> String
showDemand All = "all"
showDemand (Fields fs)
    = "{" ++ concat (intersperse ", " (map (\ (k, d) => show k ++ ": " ++ showDemand d) fs)) ++ "}"

joinD : Demand -> Demand -> Demand
joinD All _ = All
joinD _ All = All
joinD (Fields xs) (Fields ys) = Fields (merge xs ys)
  where
    merge : List (Nat, Demand) -> List (Nat, Demand) -> List (Nat, Demand)
    merge [] ys = ys
    merge xs [] = xs
    merge ((i, d) :: xs) ((j, e) :: ys)
        = if i < j then (i, d) :: merge xs ((j, e) :: ys)
          else if j < i then (j, e) :: merge ((i, d) :: xs) ys
          else (i, joinD d e) :: merge xs ys

joinAll : List Demand -> Demand
joinAll = foldl joinD none

-- How deep in the fields of an argument we look
maxPath : Nat
maxPath = 8

-- The demand `d` at the given path in the fields of a value
atPath : List Nat -> Demand -> Demand
atPath p d = if length p > maxPath then go (take maxPath p) All else go p d
  where
    go : List Nat -> Demand -> Demand
    go [] d = d
    go (k :: ks) d = Fields [(k, go ks d)]

leadingLams : Term vars -> Nat
leadingLams (Bind _ _ (Lam {}) sc) = S (leadingLams sc)
leadingLams _ = Z

isNone : Demand -> Bool
isNone (Fields []) = True
isNone _ = False

fieldDemand : Nat -> Demand -> Maybe Demand
fieldDemand _ All = Just All
fieldDemand k (Fields fs) = lookup k fs

-- Bounds: the number of summaries computed for one check, the iterations
-- for one recursive summary, and the depth of implementations whose fields
-- are looked at (a parent implementation is one level down)
maxSummaries : Nat
maxSummaries = 2000

maxIterations : Nat
maxIterations = 8

maxDictDepth : Nat
maxDictDepth = 16

data Status = Fine | NotCovering | Flagged

-- A summary under computation
record Entry where
  constructor MkEntry
  key : (Name, Nat, Demand)
  depth : Nat
  approx : Demand
  read : Bool

Cache : Type
Cache = NameMap (List ((Nat, Demand), Demand))

addCache : Name -> Nat -> Demand -> Demand -> Cache -> Cache
addCache n j rd r c = insert n (((j, rd), r) :: fromMaybe [] (lookup n c)) c

record MState where
  constructor MkMState
  -- what a function uses of an argument, given what is used of its result
  cache : Cache
  stack : List Entry -- innermost first
  -- the least depth of an entry of the stack that the summary being
  -- computed has read (so it depends on its approximation)
  low : Nat
  budget : Nat
  statuses : NameMap Status
  -- in a check: the names found not covering
  bad : List Name
  atotal : Name

data MTot : Type where

infinity : Nat
infinity = 1000000

sameKey : (Name, Nat, Demand) -> (Name, Nat, Demand) -> Bool
sameKey (n, j, d) (n', j', d') = n == n' && j == j' && eqDemand d d'

-- The variables in scope of a term: which of them is (a field of) the
-- tracked argument, and at which path
Tracked : Type
Tracked = List (Maybe (List Nat))

data Mode = Summary | Check Nat


parameters {auto c : Ref Ctxt Defs} {auto m : Ref MTot MState}

  resolvedName : Name -> Core Name
  resolvedName n
      = do defs <- get Ctxt
           Just (i, _) <- lookupCtxtExactI n (gamma defs)
                | Nothing => pure n
           pure (Resolved i)

  status : Name -> Core Status
  status n
      = do st <- get MTot
           case lookup n (statuses st) of
                Just s => pure s
                Nothing =>
                  do defs <- get Ctxt
                     s <- case !(lookupCtxtExact n (gamma defs)) of
                               Nothing => pure Fine
                               Just def =>
                                 case isCovering (totality def) of
                                      IsCovering =>
                                        pure $ if isJust (partialMethods (flags def))
                                                  then Flagged else Fine
                                      _ => pure NotCovering
                     update MTot { statuses $= insert n s }
                     pure s

  -- The arguments of a function defined by a case tree, with those of the
  -- lambdas its definition starts with when it is not a match (as for a
  -- solved metavariable)
  pmArity : Name -> Core (Maybe Nat)
  pmArity n
      = do defs <- get Ctxt
           Just def <- lookupCtxtExact n (gamma defs)
                | Nothing => pure Nothing
           case definition def of
                PMDef _ args (STerm _ tm) _ _ => pure (Just (length args + leadingLams tm))
                PMDef _ args _ _ _ => pure (Just (length args))
                _ => pure Nothing

  addBad : Name -> Core ()
  addBad n = update MTot { bad $= (++ [n]) }

  -- Does the term mention a tracked variable?
  mentionsTracked : Tracked -> Term vars -> Bool
  mentionsTracked env (Local _ _ idx _)
      = case getAt idx env of
             Just (Just _) => True
             _ => False
  mentionsTracked env (Ref {}) = False
  mentionsTracked env (Meta _ _ _ args) = any (mentionsTracked env) args
  mentionsTracked env (Bind _ _ b sc)
      = mentionsTracked env (binderType b)
        || (case b of
                 Let _ _ v _ => mentionsTracked env v
                 _ => False)
        || mentionsTracked (Nothing :: env) sc
  mentionsTracked env (App _ f a) = mentionsTracked env f || mentionsTracked env a
  mentionsTracked env (As _ _ a p) = mentionsTracked env a || mentionsTracked env p
  mentionsTracked env (TDelayed _ _ t) = mentionsTracked env t
  mentionsTracked env (TDelay _ _ ty t) = mentionsTracked env ty || mentionsTracked env t
  mentionsTracked env (TForce _ _ t) = mentionsTracked env t
  mentionsTracked env (PrimVal {}) = False
  mentionsTracked env (Erased _ (Dotted t)) = mentionsTracked env t
  mentionsTracked env (Erased {}) = False
  mentionsTracked env (TType {}) = False

  -- Does the term mention a name that is not covering, or flagged?
  mentionsBad : Term vars -> Core Bool
  mentionsBad (Local {}) = pure False
  mentionsBad (Ref _ _ n)
      = case !(status n) of
             Fine => pure False
             _ => pure True
  mentionsBad (Meta _ n _ args)
      = case !(status n) of
             Fine => anyM mentionsBad args
             _ => pure True
  mentionsBad (Bind _ _ b sc)
      = pure $ !(mentionsBad (binderType b))
               || !(case b of
                         Let _ _ v _ => mentionsBad v
                         _ => pure False)
               || !(mentionsBad sc)
  mentionsBad (App _ f a) = pure $ !(mentionsBad f) || !(mentionsBad a)
  mentionsBad (As _ _ a p) = pure $ !(mentionsBad a) || !(mentionsBad p)
  mentionsBad (TDelayed _ _ t) = mentionsBad t
  mentionsBad (TDelay _ _ ty t) = pure $ !(mentionsBad ty) || !(mentionsBad t)
  mentionsBad (TForce _ _ t) = mentionsBad t
  mentionsBad (PrimVal {}) = pure False
  mentionsBad (Erased _ (Dotted t)) = mentionsBad t
  mentionsBad (Erased {}) = pure False
  mentionsBad (TType {}) = pure False

  interesting : Mode -> Tracked -> Term vars -> Core Bool
  interesting Summary env tm = pure (mentionsTracked env tm)
  interesting (Check _) env tm = mentionsBad tm

  record' : Tracked -> Nat -> Demand -> Demand
  record' env idx d
      = case getAt idx env of
             Just (Just p) => atPath p d
             _ => none

  mutual
    -- What the term uses of the tracked argument, when `d` is used of its
    -- value (Summary); or the names it uses that are not covering, which
    -- go to `bad` (Check)
    walk : Mode -> Tracked -> Demand -> Term vars -> Core Demand
    walk mode env d tm@(App {}) = walkApp mode env d (getFnArgs tm)
    walk mode env d tm@(Local {}) = walkApp mode env d (tm, [])
    walk mode env d tm@(Ref {}) = walkApp mode env d (tm, [])
    walk mode env d tm@(Meta {}) = walkApp mode env d (tm, [])
    walk mode env d (Bind _ _ (Let _ _ v ty) sc)
        = do rv <- walk mode env All v
             rt <- walk mode env All ty
             rs <- walk mode (Nothing :: env) d sc
             pure (joinAll [rv, rt, rs])
    -- A function: its body is evaluated only if it is applied
    walk mode env d (Bind _ _ (Lam {}) sc)
        = if isNone d then pure none else walk mode (Nothing :: env) All sc
    walk mode env d (Bind _ _ b sc)
        = do rt <- walk mode env All (binderType b)
             rs <- walk mode (Nothing :: env) All sc
             pure (joinD rt rs)
    walk mode env d (As _ _ a p)
        = pure $ joinD !(walk mode env All a) !(walk mode env All p)
    walk mode env d (TDelayed _ _ t) = walk mode env All t
    walk mode env d (TDelay _ _ ty t)
        = if isNone d then pure none
             else pure $ joinD !(walk mode env All ty) !(walk mode env All t)
    walk mode env d (TForce _ _ t) = walk mode env All t
    walk mode env d (PrimVal {}) = pure none
    walk mode env d (Erased _ (Dotted t)) = walk mode env All t
    walk mode env d (Erased {}) = pure none
    walk mode env d (TType {}) = pure none

    walkAll : Mode -> Tracked -> Demand -> List (Term vars) -> Core Demand
    walkAll mode env d args = joinAll <$> traverse (walk mode env d) args

    walkApp : Mode -> Tracked -> Demand -> (Term vars, List (Term vars)) ->
              Core Demand
    walkApp mode env d (Local _ _ idx _, args)
        = do let r = record' env idx (if null args then d else All)
             pure (joinD r !(walkAll mode env All args))
    -- The arguments of a constructor are evaluated, whether or not they
    -- are used
    walkApp mode env d (Ref _ (DataCon {}) _, args)
        = do rs <- traverse (\ (k, a) => walk mode env (fromMaybe none (fieldDemand k d)) a)
                            (zip [0 .. length args] args)
             pure (joinAll rs)
    walkApp mode env d (Ref _ (TyCon {}) _, args) = walkAll mode env All args
    walkApp mode env d (Ref _ _ n, args)
        = do at <- atotal <$> get MTot
             if n == at
                then walkAssert args
                else do Just a <- pmArity n
                             | Nothing => do check (length args) All
                                             walkAll mode env All args
                        if length args < a
                           then -- a closure: called later, if it is used
                                if isNone d
                                   then walkAll mode env none args
                                   else call a All
                           else call a (if length args == a then d else All)
      where
        check : Nat -> Demand -> Core ()
        check nargs rd
            = case mode of
                   Check dep => checkRef dep n nargs rd
                   Summary => pure ()

        walkArg : Demand -> Nat -> (Nat, Term vars) -> Core Demand
        walkArg rd a (j, arg)
            = if j >= a
                 then walk mode env All arg
                 else if !(interesting mode env arg)
                         then do dj <- summary n j rd
                                 walk mode env dj arg
                         else pure none

        call : Nat -> Demand -> Core Demand
        call a rd
            = do check (length args) rd
                 rs <- traverse (walkArg rd a) (zip [0 .. length args] args)
                 pure (joinAll rs)

        -- `assert_total`: what it asserts is not checked here, as with
        -- the references under it; a tracked argument is still followed
        walkAssert : List (Term vars) -> Core Demand
        walkAssert [ty, x]
            = case mode of
                   Summary => pure $ joinD !(walk mode env All ty) !(walk mode env d x)
                   Check _ => walk mode env All ty
        walkAssert (ty :: x :: rest)
            = case mode of
                   Summary => walkAll mode env All (ty :: x :: rest)
                   Check _ => walkAll mode env All (ty :: rest)
        walkAssert args = walkAll mode env All args
    -- A solved metavariable is a function of the variables it is applied to
    -- (as the type given to `assert_total` often is)
    walkApp mode env d (Meta fc n _ margs, args)
        = walkApp mode env d (Ref fc (Func []) n, margs ++ args)
    walkApp mode env d (f, args)
        = pure $ joinD !(walk mode env All f) !(walkAll mode env All args)

    walkTree : Mode -> Tracked -> Demand -> CaseTree vars -> Core Demand
    walkTree mode env d (Case idx _ _ alts)
        = joinAll <$> traverse (walkAlt (scrutinee (getAt idx env))) alts
      where
        scrutinee : Maybe (Maybe (List Nat)) -> Maybe (List Nat)
        scrutinee (Just p) = p
        scrutinee Nothing = Nothing

        walkAlt : Maybe (List Nat) -> CaseAlt vars -> Core Demand
        walkAlt scr (ConCase _ _ cargs sc)
            = let fenv = map (\ k => map (++ [k]) scr)
                             (take (length cargs) [0 .. length cargs]) in
                  walkTree mode (fenv ++ env) d sc
        walkAlt (Just p) (DelayCase _ _ sc)
            = pure $ joinD (atPath p All)
                           !(walkTree mode (Nothing :: Nothing :: env) d sc)
        walkAlt Nothing (DelayCase _ _ sc)
            = walkTree mode (Nothing :: Nothing :: env) d sc
        walkAlt scr (ConstCase _ sc) = walkTree mode env d sc
        walkAlt scr (DefaultCase sc) = walkTree mode env d sc
    walkTree mode env d (STerm _ tm) = walk mode env d tm
    walkTree mode env d (Unmatched _) = pure none
    walkTree mode env d Impossible = pure none

    -- In a check: is the use `d` of the name `n`, applied to `nargs`
    -- arguments, covering?
    checkRef : Nat -> Name -> Nat -> Demand -> Core ()
    checkRef dep n nargs d
        = case !(status n) of
                  Fine => pure ()
                  NotCovering => addBad n
                  Flagged => unless !(fieldsCovering dep n nargs d) $ addBad n

    -- Is evaluating the implementation `n`, applied to `nargs` arguments,
    -- covering, with `d` used of it?  Its fields are evaluated (a method is
    -- usually a function, which is then not called) and those `d` uses are
    -- used.  Only for the definition of an implementation (a constructor
    -- applied to its fields).
    fieldsCovering : Nat -> Name -> Nat -> Demand -> Core Bool
    fieldsCovering dep n nargs All = pure False
    fieldsCovering dep n nargs d
        = if dep >= maxDictDepth then pure False else
            do defs <- get Ctxt
               Just def <- lookupCtxtExact n (gamma defs)
                    | Nothing => pure False
               let PMDef _ dargs (STerm _ body) _ _ = definition def
                    | _ => pure False
               let (Ref _ (DataCon {}) _, fields) = getFnArgs body
                    | _ => pure False
               if nargs /= length dargs
                  then pure False
                  else allM (fieldCovering (map (const Nothing) dargs))
                            (zip [0 .. length fields] fields)
      where
        fieldCovering : Tracked -> (Nat, Term vs) -> Core Bool
        fieldCovering env (k, f)
            = do let dk = fromMaybe none (fieldDemand k d)
                 st <- get MTot
                 put MTot ({ bad := [] } st)
                 ignore $ walk (Check (S dep)) env dk f
                 st' <- get MTot
                 put MTot ({ bad := bad st } st')
                 pure (null (bad st'))

    -- What the function `n` uses of its argument `j`, when `rd` is used of
    -- its result
    summary : Name -> Nat -> Demand -> Core Demand
    summary n_in j rd
        = do n <- resolvedName n_in
             st <- get MTot
             let key = (n, j, rd)
             case lookup n (cache st) >>= find (\ ((j', rd'), _) => j == j' && eqDemand rd rd') of
               Just (_, r) => pure r
               Nothing =>
                 case find (\ e => sameKey key (Entry.key e)) (stack st) of
                   Just e =>
                     do put MTot ({ stack $= map (\ e' => if depth e' == depth e
                                                              then { read := True } e'
                                                              else e'),
                                    low $= min (depth e) } st)
                        pure (approx e)
                   Nothing =>
                     if budget st == 0 then pure All else
                       do let dep = length (stack st)
                          put MTot ({ stack $= (MkEntry key dep none False ::),
                                      low := infinity } st)
                          r <- iterate key dep Z
                          logC "totality.methods" 10 $
                            do n' <- toFullNames n
                               pure "\{show n'} uses of argument \{show j}, when \{showDemand rd} of its result is used: \{showDemand r}"
                          st' <- get MTot
                          let l = low st'
                          let ok = l >= dep
                          let cache' : Cache = if ok then addCache n j rd r (cache st') else cache st'
                          put MTot ({ stack $= drop 1,
                                      low := min (low st) (if ok then infinity else l),
                                      cache := cache' } st')
                          pure r
      where
        analyse : Name -> Core Demand
        analyse n
            = do defs <- get Ctxt
                 Just def <- lookupCtxtExact n (gamma defs)
                      | Nothing => pure All
                 let PMDef _ dargs tree _ _ = definition def
                      | _ => pure All
                 let env = map (\ i => if i == j then Just [] else Nothing)
                               (take (length dargs) [0 .. length dargs])
                 case tree of
                      -- the arguments after those of the case tree are
                      -- those of the leading lambdas
                      STerm _ tm =>
                        walkLams env (leadingLams tm)
                                 (if j >= length dargs then Just (j `minus` length dargs)
                                                       else Nothing) tm
                      _ => if j >= length dargs
                              then pure All
                              else walkTree Summary env rd tree
          where
            walkLams : Tracked -> Nat -> Maybe Nat -> Term vs -> Core Demand
            walkLams env Z Nothing tm = walk Summary env rd tm
            walkLams env Z (Just _) tm = pure All
            walkLams env (S k) tgt (Bind _ _ (Lam {}) sc)
                = let (here, tgt') = the (Maybe (List Nat), Maybe Nat) $ case tgt of
                                          Just Z => (Just [], Nothing)
                                          Just (S i) => (Nothing, Just i)
                                          Nothing => (Nothing, Nothing) in
                      walkLams (here :: env) k tgt' sc
            walkLams env _ _ tm = pure All

        iterate : (Name, Nat, Demand) -> Nat -> Nat -> Core Demand
        iterate key@(n, _, _) dep i
            = do update MTot { budget $= (`minus` 1),
                               stack $= map (\ e => if depth e == dep
                                                       then { read := False } e
                                                       else e) }
                 r <- analyse n
                 st <- get MTot
                 let Just e = find (\ e => depth e == dep) (stack st)
                      | Nothing => pure All
                 if read e && not (eqDemand r (approx e))
                    then if i >= maxIterations
                            then pure All
                            else do put MTot ({ stack $= map (\ e => if depth e == dep
                                                                        then { approx := r } e
                                                                        else e) } st)
                                    iterate key dep (S i)
                    else pure r

initState : Name -> MState
initState at = MkMState empty [] infinity maxSummaries empty [] at

-- The case blocks of a definition, and theirs, recursively
caseBlocks : {auto c : Ref Ctxt Defs} -> Name -> Core (List Name)
caseBlocks n
    = do defs <- get Ctxt
         Just d <- lookupCtxtExact n (gamma defs)
              | Nothing => pure []
         cs <- filter isCase <$> traverse toFullNames (keys (refersTo d))
         pure (cs ++ concat !(traverse caseBlocks cs))
  where
    isCase : Name -> Bool
    isCase (NS _ n) = isCase n
    isCase (CaseBlock {}) = True
    isCase _ = False

||| The names that make the given function not covering once the methods of
||| the implementations it uses are counted: those not covering, and the
||| implementations (and other functions) flagged with `PartialMethods` of
||| which it may use what is not covering.  The function itself must be
||| covering when they are not counted; the result is in full names.
export
methodNonCoveringRefs : {auto c : Ref Ctxt Defs} ->
                        FC -> Name -> Core (List Name)
methodNonCoveringRefs fc n
    = do candidates <- getNonCoveringRefs fc True n
         if null candidates then pure [] else do
           at <- toResolvedNames (NS builtinNS (UN $ Basic "assert_total"))
           m <- newRef MTot (initState at)
           cs <- caseBlocks n
           ok <- allM checkDef (n :: cs)
           st <- get MTot
           let bad = if ok then bad st else candidates
           bad <- nub <$> traverse toFullNames bad
           logC "totality.methods" 5 $
             do n' <- toFullNames n
                cs <- traverse toFullNames candidates
                pure "\{show n'}: uses implementations with methods that are not covering: \{show cs}; of which it may use those of \{show bad}"
           pure bad
  where
    checkDef : {auto m : Ref MTot MState} -> Name -> Core Bool
    checkDef fn
        = do defs <- get Ctxt
             Just def <- lookupCtxtExact fn (gamma defs)
                  | Nothing => pure False
             let PMDef _ dargs tree _ _ = definition def
                  | _ => pure False
             ignore $ walkTree (Check Z) (map (const Nothing) dargs) All tree
             pure True

||| For the definition of an implementation (a constructor applied to its
||| fields): the names that make the fields not covering, in full names, or
||| `Nothing` if the definition is not of this form.
export
implNonCoveringRefs : {auto c : Ref Ctxt Defs} ->
                      Name -> Core (Maybe (List Name))
implNonCoveringRefs n
    = do defs <- get Ctxt
         Just def <- lookupCtxtExact n (gamma defs)
              | Nothing => pure Nothing
         let PMDef _ dargs (STerm _ body) _ _ = definition def
              | _ => pure Nothing
         let (Ref _ (DataCon {}) _, fields) = getFnArgs body
              | _ => pure Nothing
         at <- toResolvedNames (NS builtinNS (UN $ Basic "assert_total"))
         m <- newRef MTot (initState at)
         traverse_ (walk (Check Z) (map (const Nothing) dargs) All) fields
         st <- get MTot
         Just . nub <$> traverse toFullNames (bad st)
