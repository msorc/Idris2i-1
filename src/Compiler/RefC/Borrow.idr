||| Which parameters of the functions the RefC backend passes without
||| ownership ("borrowed").
|||
||| A parameter that a function only looks at (a list it walks, a key it
||| compares) need not be owned by it: when the caller passes it borrowed, it
||| keeps its reference, and neither the caller takes a reference for the call
||| nor the function releases it.  This saves two reference count operations
||| per argument and call, and many more in a function that walks a structure
||| (see the second point below).
|||
||| As in Lean (Ullrich and de Moura, "Counting Immutable Beans"), every
||| parameter starts borrowed, and a whole program fixpoint makes owned the
||| parameters that the function consumes, anywhere in its body:
|||
||| * stored in a constructor, captured by a closure (`AUnderApp`), applied as
|||   a closure or passed to one (`AApp`);
||| * returned;
||| * passed to an owned parameter of another function (or to a function
|||   called with more than `maxArgs` arguments, which goes through a closure);
||| * given to `believe_me`;
||| * the scrutinee of a `case` with a branch that builds a constructor with as
|||   many fields as the branch's own, which could reuse its cell in place
|||   (a borrowed value is never reused);
||| * passed in a call in tail position to a borrowed parameter while the
|||   caller owns it: the caller would have to release it after the call,
|||   which would then not be a tail call any more (`preserveTailCall` in
|||   Lean).  This makes the parameter of the *callee* owned.
|||
||| These parameters are never borrowed: those of a function that is used as a
||| closure (the runtime calls closures with owned arguments: a wrapper that
||| releases them after the call would break the tail calls through closures,
||| which monadic code makes all the time), of a function with more than
||| `maxArgs` parameters (called with an array, through a closure), and the
||| parameters that are C integers (see Compiler.RefC.Unbox: the value is
||| released once it is unboxed).
|||
||| The variables bound by a `case` on a borrowed variable are borrowed too:
||| the scrutinee, which the caller keeps alive during the whole call, keeps
||| them alive.  So a function that walks a list it borrows takes no reference
||| at all.  When one of them is used in one of the ways above (or copied by a
||| `let`), the scrutinee is made owned instead, as in Lean: a reference to a
||| field costs as much as owning the value, which gives its fields away for
||| free when nobody else holds it.  So only the parameters that a function
||| merely looks at (down to the fields it passes on to borrowed parameters)
||| are borrowed.  The code generator follows the same rules (see `AConCase` in
||| Compiler.RefC.RefC): what the analysis takes as borrowed is never owned
||| there.
module Compiler.RefC.Borrow

import Compiler.ANF

import Core.TT

import Data.List
import Data.SortedMap
import Data.SortedSet
import Data.Vect

%default covering

||| For each function (by C name) that has borrowed parameters, which of its
||| parameters are borrowed (True), in order.  The other functions own all
||| their parameters.
public export
Signatures : Type
Signatures = SortedMap String (List Bool)

||| The signature of a function called with `n` arguments: Nothing when it
||| owns all of them.
export
signatureOf : Signatures -> String -> Nat -> Maybe (List Bool)
signatureOf sigs f n
    = case lookup f sigs of
           Just s => if length s == n then Just s else Nothing
           Nothing => Nothing

isBelieveMe : PrimFn arity -> Bool
isBelieveMe BelieveMe = True
isBelieveMe _ = False

||| The numbers of fields of the constructors that an expression builds
||| (those that are allocated: nullary ones are not).
conSizes : ANF -> SortedSet Nat -> SortedSet Nat
conSizes (ACon _ _ _ _ args) s
    = case args of
           [] => s
           _ => insert (length args) s
conSizes (ALet _ _ val body) s = conSizes body (conSizes val s)
conSizes (AConCase _ _ alts def) s
    = let s = foldl (\s', (MkAConAlt _ _ _ _ b) => conSizes b s') s alts in
          maybe s (\d => conSizes d s) def
conSizes (AConstCase _ _ alts def) s
    = let s = foldl (\s', (MkAConstAlt _ b) => conSizes b s') s alts in
          maybe s (\d => conSizes d s) def
conSizes _ s = s

-- ---------------------------------------------------------------------------
-- Tail recursion modulo cons (see trmcFunction in Compiler.RefC.RefC): the
-- shape of the code, which the borrowing must know too (the call of the
-- function to itself there is a tail call).
-- ---------------------------------------------------------------------------

||| May the value be computed before a call that does not need it (`r` is
||| the variable of the call)?  Only values that do nothing but allocate.
safeBefore : Int -> ANF -> Bool
safeBefore r (AV _ v) = v /= ALocal r
safeBefore _ (APrimVal _ _) = True
safeBefore _ (AErased _) = True
safeBefore r (ACon _ _ _ _ as) = not (ALocal r `elem` as)
safeBefore r (AUnderApp _ _ _ as) = not (ALocal r `elem` as)
safeBefore _ _ = False

isCall : ANF -> Bool
isCall (AAppName _ Nothing _ _) = True
isCall _ = False

||| A chain of `let`s, with the `let`s in the values of `let`s first (`let v =
||| (let w = e in b) in body` is `let w = e in let v = b in body`: variables
||| are bound once, so `w` is not in `body`), and the `let`s of values that
||| only allocate (see `safeBefore`) right after a call moved before it, so
||| that a call made into a cell (`Node (f l) x Leaf`) comes right before the
||| constructor.
export
trmcNormalise : ANF -> ANF
trmcNormalise (ALet fc v (ALet fc' w e b) body)
    = trmcNormalise (ALet fc' w e (ALet fc v b body))
trmcNormalise (ALet fc v val body)
    = let body' = trmcNormalise body in
          if isCall val then sink (ALet fc v val body') else ALet fc v val body'
  where
    sink : ANF -> ANF
    sink (ALet fc r call (ALet fc' w e rest))
        = if safeBefore r e then ALet fc' w e (sink (ALet fc r call rest))
             else ALet fc r call (ALet fc' w e rest)
    sink a = a
trmcNormalise anf = anf

positionsOf : Eq a => a -> List a -> List Nat
positionsOf x = go 0
  where
    go : Nat -> List a -> List Nat
    go _ [] = []
    go k (y :: ys) = if x == y then k :: go (S k) ys else go (S k) ys

||| `let r = self as in Con .. r ..`, a cell made of a call of the function to
||| itself (C name `self`, `nargs` parameters), where `r` is one field and
||| nothing else: the field.
export
trmcDirect : (key : Name -> String) -> (self : String) -> (nargs : Nat) ->
             ANF -> Maybe Nat
trmcDirect key self nargs (ALet _ r (AAppName _ Nothing f as) (ACon _ _ _ _ cargs))
    = if key f == self && length as == nargs
         then case positionsOf (ALocal r) cargs of
                   [k] => Just k
                   _ => Nothing
         else Nothing
trmcDirect _ _ _ _ = Nothing

||| Does a normalised chain of `let`s (see `trmcNormalise`) end with such a
||| cell?
export
trmcChain : (key : Name -> String) -> (self : String) -> (nargs : Nat) ->
            ANF -> Bool
trmcChain key self nargs a@(ALet _ _ _ body)
    = isJust (trmcDirect key self nargs a) || trmcChain key self nargs body
trmcChain _ _ _ _ = False

||| The end of a chain of `let`s.
export
chainEnd : ANF -> ANF
chainEnd (ALet _ _ _ body) = chainEnd body
chainEnd anf = anf

public export
data TrmcPlan = TrmcSite Nat | TrmcReorder ANF | TrmcNone

||| What the code generator does with a `let` in tail position, in a
||| function with tail recursion modulo cons: the cell (`TrmcSite`), the
||| chain normalised first when that gives a cell at its end and changes its
||| first `let` (`TrmcReorder`), or nothing special.
export
trmcPlan : (key : Name -> String) -> (self : String) -> (nargs : Nat) ->
           ANF -> TrmcPlan
trmcPlan key self nargs anf@(ALet _ v val _)
    = case trmcDirect key self nargs anf of
           Just k => TrmcSite k
           Nothing =>
             let n = trmcNormalise anf in
                 if trmcChain key self nargs n && changed n
                    then TrmcReorder n else TrmcNone
  where
    changed : ANF -> Bool
    changed (ALet _ v' _ _) = v' /= v || isLet val
      where
        isLet : ANF -> Bool
        isLet (ALet _ _ _ _) = True
        isLet _ = False
    changed _ = True
trmcPlan _ _ _ _ = TrmcNone

||| What the analysis of a function found.
record Found where
  constructor MkFound
  ||| its borrowed parameters that must be owned
  owned : SortedSet Int
  ||| the parameters of other functions (or of itself) that must be owned,
  ||| by C name and position
  marks : List (String, Nat)

||| The context of the analysis of a function.
record Ctx where
  constructor MkCtx
  sigs : Signatures
  ||| the C name of a function, from its name in the code
  key : Name -> String
  ||| the C names of the foreign functions (they borrow their arguments)
  foreign : String -> Nat -> Bool
  ||| above this many arguments, a call goes through a closure
  maxArgs : Nat
  ||| the borrowed parameters of the function
  params : SortedSet Int
  ||| the C name and the number of parameters of the function, when it has
  ||| tail recursion modulo cons
  trmc : Maybe (String, Nat)

||| A use of `v` that needs it owned.  When `v` is a borrowed parameter, it
||| must be owned.  When it is a field of a borrowed value (see `par`), that
||| value must be owned instead (as in Lean): taking a reference to a field
||| costs as much as owning the value, which then gives its fields away for
||| free when it is not shared.
markParam : Ctx -> (par : SortedMap Int Int) -> AVar -> Found -> Found
markParam c par (ALocal v) f
    = if contains v c.params then { owned $= insert v } f
      else case lookup v par of
                Just sc => markParam c par (ALocal sc) f
                Nothing => f
markParam _ _ ANull f = f

markParams : Ctx -> SortedMap Int Int -> List AVar -> Found -> Found
markParams c par vs f = foldl (flip (markParam c par)) f vs

||| Is the variable owned by the function (where the code generator holds a
||| reference to it)?  The borrowed ones are `bor`; the others are the owned
||| parameters, the `let`s and the fields of owned values.
isOwned : SortedSet Int -> AVar -> Bool
isOwned bor (ALocal v) = not (contains v bor)
isOwned _ ANull = False

||| The analysis of an expression, in tail position or not, with the borrowed
||| variables `bor`, of which the fields of borrowed values are in `par` (with
||| the value that they come from).
analyse : Ctx -> (tail : Bool) -> (bor : SortedSet Int) ->
          (par : SortedMap Int Int) -> ANF -> Found -> Found
-- (a copy of a variable is owned: `let x = v` takes a reference to `v`)
analyse c t bor par (AV _ v) f = markParam c par v f
analyse c t bor par (AAppName _ _ n args) f
    = let g = c.key n
          nargs = length args in
          if c.foreign g nargs then f
          else if nargs > c.maxArgs then markParams c par args f
          else case signatureOf c.sigs g nargs of
                    Nothing => markParams c par args f
                    Just s =>
                      let pairs = zip args s
                          f = markParams c par (map fst (filter (not . snd) pairs)) f in
                          if t
                             then foldl (\f', (k, (a, b)) =>
                                           if b && isOwned bor a
                                              then { marks $= ((g, k) ::) } f'
                                              else f')
                                        f (zip [0 .. length pairs] pairs)
                             else f
analyse c t bor par (AUnderApp _ _ _ args) f = markParams c par args f
analyse c t bor par (AApp _ _ cl a) f = markParam c par cl (markParam c par a f)
analyse c t bor par anf@(ALet _ _ val body) f
    = case (t, c.trmc) of
           -- (the call made into a cell is a tail call)
           (True, Just (self, nargs)) => chain self nargs (trmcNormalise anf) f
           _ => analyse c t bor par body (analyse c False bor par val f)
  where
    chain : String -> Nat -> ANF -> Found -> Found
    chain self nargs a@(ALet _ _ v b) f'
        = if isJust (trmcDirect c.key self nargs a)
             then analyse c True bor par b (analyse c True bor par v f')
             else chain self nargs b (analyse c False bor par v f')
    chain _ _ a f' = analyse c True bor par a f'
analyse c t bor par (ACon _ _ _ _ args) f = markParams c par args f
analyse c t bor par (AOp _ _ op args) f
    = if isBelieveMe op then markParams c par (toList args) f else f
analyse c t bor par (AExtPrim _ _ _ _) f = f
analyse c t bor par (AConCase _ sc alts def) f
    = let reuse = any (\(MkAConAlt _ _ _ fields body) =>
                         not (null fields) &&
                         contains (length fields) (conSizes body empty)) alts
          f1 = if reuse then markParam c par sc f else f
          f2 = foldl (\f', alt => analyseAlt sc alt f') f1 alts in
          maybe f2 (\d => analyse c t bor par d f2) def
  where
    -- (the fields of a borrowed value are borrowed)
    analyseAlt : AVar -> AConAlt -> Found -> Found
    analyseAlt (ALocal v) (MkAConAlt _ _ _ fields body) f'
        = if contains v bor
             then analyse c t (foldl (flip insert) bor fields)
                          (foldl (\m, x => insert x v m) par fields) body f'
             else analyse c t bor par body f'
    analyseAlt ANull (MkAConAlt _ _ _ _ body) f' = analyse c t bor par body f'
analyse c t bor par (AConstCase _ _ alts def) f
    = let f = foldl (\f', (MkAConstAlt _ b) => analyse c t bor par b f') f alts in
          maybe f (\d => analyse c t bor par d f) def
analyse _ _ _ _ _ f = f

||| A function that may borrow parameters.
record Fun where
  constructor MkFun
  params : List Int
  body : ANF

||| The fixpoint of the analysis, over the functions `funs` (by C name),
||| starting from the signatures `sigs`.
fixpoint : (key : Name -> String) -> (foreign : String -> Nat -> Bool) ->
           (maxArgs : Nat) -> (trmc : String -> Bool) ->
           SortedMap String Fun -> (callers : SortedMap String (List String)) ->
           Signatures -> List String -> Signatures
fixpoint key foreign maxArgs trmc funs callers sigs [] = sigs
fixpoint key foreign maxArgs trmc funs callers sigs (g :: todo)
    -- (every function is analysed, also those that own all their
    -- parameters: their calls in tail position may make other functions
    -- own theirs)
    = case lookup g funs of
           Just fn =>
             let s = fromMaybe (map (const False) fn.params) (lookup g sigs)
                 bps = fromList (map fst (filter snd (zip fn.params s)))
                 c = MkCtx sigs key foreign maxArgs bps
                       (if trmc g then Just (g, length fn.params) else Nothing)
                 found = analyse c True bps empty fn.body (MkFound empty [])
                 -- this function
                 s' = zipWith (\p, b => b && not (contains p found.owned)) fn.params s
                 (sigs, changed) = if s' == s
                                      then (sigs, the (List String) [])
                                      else (setSig g s' sigs, [g])
                 -- the functions that it calls in tail position
                 (sigs, changed) = foldl (\(sigs', ch), (h, k) =>
                                            case lookup h sigs' of
                                                 Just hs =>
                                                   if index' k hs
                                                      then (setSig h (clear k hs) sigs', h :: ch)
                                                      else (sigs', ch)
                                                 Nothing => (sigs', ch))
                                         (sigs, changed) found.marks
                 -- a function whose signature changed is analysed again,
                 -- with its callers
                 again = concatMap (\h => h :: fromMaybe [] (lookup h callers)) changed in
                 fixpoint key foreign maxArgs trmc funs callers sigs (again ++ todo)
           Nothing => fixpoint key foreign maxArgs trmc funs callers sigs todo
  where
    index' : Nat -> List Bool -> Bool
    index' _ [] = False
    index' Z (b :: _) = b
    index' (S k) (_ :: bs) = index' k bs

    clear : Nat -> List Bool -> List Bool
    clear _ [] = []
    clear Z (_ :: bs) = False :: bs
    clear (S k) (b :: bs) = b :: clear k bs

    -- (a function left with no borrowed parameter is dropped from the map)
    setSig : String -> List Bool -> Signatures -> Signatures
    setSig h hs sigs' = if any id hs then insert h hs sigs' else delete h sigs'

||| The borrowed parameters of the functions `defs` (by C name).
|||
||| `key` gives the C name of a function from its name in the code (as the
||| code generator calls it), `foreign` tells the foreign functions (by C name
||| and number of arguments), `unboxed` the variables that are C integers.
||| `trmc` the functions with tail recursion modulo cons, whose calls to
||| themselves made into cells are tail calls (see `trmcPlan`).
export
inferBorrowing : (key : Name -> String) ->
                 (foreign : String -> Nat -> Bool) ->
                 (unboxed : String -> SortedSet Int) ->
                 (maxArgs : Nat) ->
                 (trmc : String -> Bool) ->
                 List (String, ANFDef) -> Signatures
inferBorrowing key foreign unboxed maxArgs trmc defs
    = let funs = mapMaybe (\case
                             (n, MkAFun args body) => Just (n, MkFun args body)
                             _ => Nothing) defs
          arities = fromList (map (\(n, fn) => (n, length fn.params)) funs)
          -- (and those called with another number of arguments, which
          -- should not happen)
          closures = foldl (\s, (_, fn) => underApps arities fn.body s) (the (SortedSet String) empty) funs
          start = fromList $ mapMaybe (\(n, fn) =>
                     let nargs = length fn.params
                         u = unboxed n in
                         if nargs == 0 || nargs > maxArgs || contains n closures
                            then Nothing
                            else let s = map (\p => not (contains p u)) fn.params in
                                     if any id s then Just (n, s) else Nothing) funs
          callers = foldl (\m, (n, fn) =>
                             foldl (\m', g => insert g (n :: fromMaybe [] (lookup g m')) m')
                                   m (Prelude.toList (calleesOf fn.body)))
                          empty funs in
          fixpoint key foreign maxArgs trmc (fromList funs) callers start (map fst funs)
  where
    calleesOf : ANF -> SortedSet String
    calleesOf body = fromList (map key (namesIn body []))
      where
        namesIn : ANF -> List Name -> List Name
        namesIn (AAppName _ _ n _) ns = n :: ns
        namesIn (ALet _ _ val b) ns = namesIn b (namesIn val ns)
        namesIn (AConCase _ _ alts def) ns
            = let ns = foldl (\ns', (MkAConAlt _ _ _ _ b) => namesIn b ns') ns alts in
                  maybe ns (\d => namesIn d ns) def
        namesIn (AConstCase _ _ alts def) ns
            = let ns = foldl (\ns', (MkAConstAlt _ b) => namesIn b ns') ns alts in
                  maybe ns (\d => namesIn d ns) def
        namesIn _ ns = ns

    underApps : SortedMap String Nat -> ANF -> SortedSet String -> SortedSet String
    underApps ar (AUnderApp _ n _ _) s = insert (key n) s
    underApps ar (AAppName _ _ n args) s
        = let g = key n in
              case lookup g ar of
                   Just k => if k == length args then s else insert g s
                   Nothing => s
    underApps ar (ALet _ _ val b) s = underApps ar b (underApps ar val s)
    underApps ar (AConCase _ _ alts def) s
        = let s = foldl (\s', (MkAConAlt _ _ _ _ b) => underApps ar b s') s alts in
              maybe s (\d => underApps ar d s) def
    underApps ar (AConstCase _ _ alts def) s
        = let s = foldl (\s', (MkAConstAlt _ b) => underApps ar b s') s alts in
              maybe s (\d => underApps ar d s) def
    underApps _ _ s = s
