||| Recursion on an explicit stack for the JavaScript backends.
|||
||| A function that calls itself where the call is not a tail call,
|||
||| ```idris
||| foldr c n (x :: xs) = c x (foldr c n xs)
||| span p (x :: xs) = if p x then let (ys, zs) = span p xs in (x :: ys, zs)
|||                           else ([], x :: xs)
||| ```
|||
||| needs a JavaScript frame per level of the recursion: a list of some 10^4
||| elements overflows the stack of the browser (and of the main thread of
||| Node).  Such a function `f` is compiled to a loop that keeps what is left
||| to do after the call (the continuation) in a frame on the heap instead:
||| `f` becomes
|||
||| ```javascript
||| function f(as) { return f$stk(0, as, Done, undefined) }
||| ```
|||
||| where `f$stk(mode, as, k, r)` is a loop with two modes.  In mode 0 it runs
||| the body of `f` on the arguments `as`.  A call `E[f(bs)]` of `f` in an
||| evaluation context `E` (an argument of an application or a constructor, the
||| scrutinee of a `case`, the value of a `let`, ...) becomes a jump back to
||| the start, `f$stk(0, bs, Frame_i(vs, k), _)`, where `Frame_i` holds the
||| variables `vs` that `E` uses.  What the body returns, `v`, is returned to
||| the frame on top of the stack: `f$stk(1, _, k, v)`.  In mode 1, `Done`
||| returns `r` and `Frame_i(vs, k')` goes on with `E[r]` on the stack `k'`
||| (which can make more calls: `fib (n - 1) + fib (n - 2)`).  All the calls of
||| `f$stk` are tail calls to itself, so it is a `while` loop (see
||| `Compiler.ES.TailRec`).
|||
||| The order of evaluation is the one of the code without the loop: the parts
||| of `E` that are evaluated before the call are bound by `let`s before the
||| jump (or saved as they are, if they only allocate), and the parts after it
||| are in the frame.  The code generator evaluates some parts of an expression
||| before the others (a `case` or a `let` in an argument is lifted out of it),
||| so a call is only made a jump when that cannot change the order: the parts
||| after the call do no such thing, and, unless the parts before it only
||| allocate, neither do the parts that come after them (the arguments of the
||| call, say).  The other calls stay as they are.
|||
||| A tail call of `f` to another function, `return g(x)`, can return a pending
||| call of the trampoline (see `Compiler.ES.TailRec`): with an empty stack,
||| `f$stk` still returns it as it is, and to a frame its value goes, as it did
||| to the caller that needed it without the loop.  A function in a group of
||| several that call each other by tail calls is not transformed: the loop
||| through them would need a frame per round.
module Compiler.ES.Stack

import Core.CompileExpr
import Core.Context

import Compiler.ES.TailRec

import Control.Monad.State
import Data.List
import Data.List1
import Data.SortedMap
import Data.SortedSet
import Data.Vect
import Libraries.Data.Graph

%default covering

--------------------------------------------------------------------------------
--          Expressions
--------------------------------------------------------------------------------

-- Computing it does nothing but allocate.
safe : NamedCExp -> Bool
safe (NmLocal _ _) = True
safe (NmPrimVal _ _) = True
safe (NmErased _) = True
safe (NmLam _ _ _) = True
safe (NmDelay _ _ _) = True
safe (NmCon _ _ _ _ as) = all safe as
safe _ = False

-- The code generator makes it a single expression, without statements before
-- it (`Compiler.ES.ToAst` lifts a `let`, a `case` and a crash out of the
-- expression it is in, and runs them first).
plain : NamedCExp -> Bool
plain (NmLocal _ _) = True
plain (NmRef _ _) = True
plain (NmLam _ _ _) = True
plain (NmDelay _ _ _) = True
plain (NmPrimVal _ _) = True
plain (NmErased _) = True
plain (NmApp _ f as) = plain f && all plain as
plain (NmCon _ _ _ _ as) = all plain as
plain (NmOp _ _ as) = all plain (toList as)
plain (NmExtPrim _ _ as) = all plain as
plain (NmForce _ _ e) = plain e
plain _ = False

mutual
  freeVars : NamedCExp -> SortedSet Name
  freeVars (NmLocal _ n) = singleton n
  freeVars (NmRef _ _) = empty
  freeVars (NmLam _ x b) = delete x (freeVars b)
  freeVars (NmLet _ x v b) = freeVars v `union` delete x (freeVars b)
  freeVars (NmApp _ f as) = freeVars f `union` freeVarsList as
  freeVars (NmCon _ _ _ _ as) = freeVarsList as
  freeVars (NmOp _ _ as) = freeVarsList (toList as)
  freeVars (NmExtPrim _ _ as) = freeVarsList as
  freeVars (NmForce _ _ e) = freeVars e
  freeVars (NmDelay _ _ e) = freeVars e
  freeVars (NmConCase _ sc alts def)
      = foldr (\(MkNConAlt _ _ _ xs b), acc =>
                 (freeVars b `difference` fromList xs) `union` acc)
              (freeVars sc `union` maybe empty freeVars def) alts
  freeVars (NmConstCase _ sc alts def)
      = foldr (\(MkNConstAlt _ b), acc => freeVars b `union` acc)
              (freeVars sc `union` maybe empty freeVars def) alts
  freeVars (NmPrimVal _ _) = empty
  freeVars (NmErased _) = empty
  freeVars (NmCrash _ _) = empty

  freeVarsList : List NamedCExp -> SortedSet Name
  freeVarsList = foldr (\e, acc => freeVars e `union` acc) empty

-- Puts the elements of the list in the places of the vector.
refill : Vect n a -> List a -> Vect n a
refill [] _ = []
refill (x :: xs) [] = x :: xs
refill (_ :: xs) (y :: ys) = y :: refill xs ys

--------------------------------------------------------------------------------
--          Calls in an evaluation context
--------------------------------------------------------------------------------

-- A call of the function in an evaluation context.
record Site where
  constructor MkSite
  ||| what is evaluated before the call, bound to fresh variables
  binds : List (Name, NamedCExp)
  ||| what is evaluated before the call, in order (for the check of the order)
  before : List NamedCExp
  ||| the arguments of the call
  args : List NamedCExp
  ||| the context, given the result of the call
  context : NamedCExp -> NamedCExp
  ||| what is evaluated after the call (for the check of the order)
  after : List NamedCExp

-- The order of evaluation stays the same (see the top of the module).
inOrder : Site -> Bool
inOrder s = all plain s.after && go (s.before ++ s.args)
  where
    go : List NamedCExp -> Bool
    go [] = True
    go (e :: es) = (safe e || all plain es) && go es

tmpName : Int -> Name
tmpName = MN "$stkTmp"

parameters (self : Name) (arity : Nat)

  selfCall : NamedCExp -> Maybe (List NamedCExp)
  selfCall (NmApp _ (NmRef _ g) as)
      = if g == self && length as == arity then Just as else Nothing
  selfCall _ = Nothing

  mutual
    -- The first call of the function that is evaluated in `e`, if it is in
    -- an evaluation context.  (`i` numbers the fresh variables.)
    site : NamedCExp -> State Int (Maybe Site)
    site (NmApp fc f@(NmRef _ g) as)
        = do Nothing <- siblings as
               | Just (s, rebuild) => pure $ Just $ { context $= \c => NmApp fc f . rebuild . c } s
             pure $ if g == self && length as == arity
                       then Just (MkSite [] [] as id [])
                       else Nothing
    site (NmApp fc f as)
        = do Just (s, rebuild) <- siblings (f :: as)
               | Nothing => pure Nothing
             pure $ Just $ { context $= \c => app . rebuild . c } s
      where
        app : List NamedCExp -> NamedCExp
        app (f' :: as') = NmApp fc f' as'
        app [] = NmApp fc f as
    site (NmCon fc n ci t as)
        = do Just (s, rebuild) <- siblings as
               | Nothing => pure Nothing
             pure $ Just $ { context $= \c => NmCon fc n ci t . rebuild . c } s
    site (NmOp fc op as)
        = do Just (s, rebuild) <- siblings (toList as)
               | Nothing => pure Nothing
             pure $ Just $ { context $= \c => NmOp fc op . refill as . rebuild . c } s
    site (NmExtPrim fc p as)
        = do Just (s, rebuild) <- siblings as
               | Nothing => pure Nothing
             pure $ Just $ { context $= \c => NmExtPrim fc p . rebuild . c } s
    site (NmForce fc r e)
        = do Just s <- site e
               | Nothing => pure Nothing
             pure $ Just $ { context $= \c => NmForce fc r . c } s
    site _ = pure Nothing

    -- The first of the expressions with a call in an evaluation context: the
    -- call, and how to put the expressions back together with the context
    -- in its place.
    siblings : List NamedCExp ->
               State Int (Maybe (Site, NamedCExp -> List NamedCExp))
    siblings = go []
      where
        -- `ls` are the expressions to the left, last first
        go : List NamedCExp -> List NamedCExp ->
             State Int (Maybe (Site, NamedCExp -> List NamedCExp))
        go ls [] = pure Nothing
        go ls (e :: rs)
            = do Just s <- site e
                   | Nothing => go (e :: ls) rs
                 bound <- traverse bind (reverse ls)
                 let lefts = reverse ls
                 pure $ Just
                   ( { binds $= (concatMap snd bound ++)
                     , before $= (lefts ++)
                     , after $= (++ rs) } s
                   , \h => map fst bound ++ [h] ++ rs )
          where
            -- an expression to the left of the call: bound to a variable
            -- unless it only allocates
            bind : NamedCExp -> State Int (NamedCExp, List (Name, NamedCExp))
            bind l = if safe l
                        then pure (l, [])
                        else do i <- get
                                put (i + 1)
                                pure (NmLocal EmptyFC (tmpName i), [(tmpName i, l)])

--------------------------------------------------------------------------------
--          The loop
--------------------------------------------------------------------------------

modeName : Name
modeName = MN "$stkMode" 0

stackName : Name
stackName = MN "$stkK" 0

resultName : Name
resultName = MN "$stkR" 0

holeName : Int -> Name
holeName = MN "$stkHole"

nextName : Int -> Name
nextName = MN "$stkNext"

frameCon : Int -> Name
frameCon = MN "$stkFrame"

doneCon : Name
doneCon = MN "$stkDone" 0

done : NamedCExp
done = NmCon EmptyFC doneCon DATACON (Just 0) []

-- What is left to do after a call: the variables in the frame (they are
-- bound to the same names in the branch of the frame), and the
-- continuation, whose stack is `nextName i`.
record Frame where
  constructor MkFrame
  index : Int
  vars : List Name
  body : NamedCExp

-- The state of the transformation: the fresh variables, and the frames.
record St where
  constructor MkSt
  next : Int
  frames : List Frame

parameters (self : Name) (loop : Name) (args : List Name)

  -- A call of the loop.
  jump : Int -> List NamedCExp -> NamedCExp -> NamedCExp -> NamedCExp
  jump mode as k r
      = NmApp EmptyFC (NmRef EmptyFC loop) (NmPrimVal EmptyFC (I mode) :: as ++ [k, r])

  -- Returns `v` to the frame on top of the stack `k`.  A tail call that can
  -- return a pending call of the trampoline stays a tail call when the stack
  -- is empty.
  ret : NamedCExp -> NamedCExp -> NamedCExp
  ret k v
      = let ret = jump 1 (map (NmLocal EmptyFC) args) k v in
            if mayBounce v
               then NmConCase EmptyFC k [MkNConAlt doneCon DATACON (Just 0) [] v] (Just ret)
               else ret
    where
      mayBounce : NamedCExp -> Bool
      mayBounce (NmApp _ _ _) = True
      mayBounce (NmForce _ _ _) = True
      mayBounce _ = False

  mutual
    -- The site as a jump that pushes a frame; `outer` is what the code
    -- around the context does with its value (a `let` or a `case`).
    push : NamedCExp -> Site -> (NamedCExp -> NamedCExp) -> State St NamedCExp
    push k s outer
        = do i <- next <$> get
             modify { next := i + 1 }
             let hole = holeName i
                 cont = outer (s.context (NmLocal EmptyFC hole))
                 vars = Prelude.toList (delete hole (freeVars cont))
             body <- toStack (NmLocal EmptyFC (nextName i)) cont
             modify { frames $= (MkFrame i vars (NmLet EmptyFC hole (NmLocal EmptyFC resultName) body) ::) }
             let frame = NmCon EmptyFC (frameCon i) DATACON (Just i)
                           (map (NmLocal EmptyFC) vars ++ [k])
             pure $ foldr (\(x, v), b => NmLet EmptyFC x v b)
                          (jump 0 s.args frame (NmLocal EmptyFC resultName)) s.binds

    -- The first site in `e`, if the order of evaluation stays the same with
    -- the jump.
    findSite : NamedCExp -> State St (Maybe Site)
    findSite e
        = do st <- get
             let (i', s) = runState st.next (site self (length args) e)
             put ({ next := i' } st)
             pure $ case s of
                         Just s' => if inOrder s' then Just s' else Nothing
                         Nothing => Nothing

    -- An expression in tail position, whose value goes to the frame on top
    -- of the stack `k`.
    toStack : NamedCExp -> NamedCExp -> State St NamedCExp
    toStack k (NmLet fc x v b)
        = do Nothing <- findSite v
               | Just s => push k s (\h => NmLet fc x h b)
             NmLet fc x v <$> toStack k b
    toStack k (NmConCase fc sc alts def)
        = do Nothing <- findSite sc
               | Just s => push k s (\h => NmConCase fc h alts def)
             alts' <- traverse (\(MkNConAlt n ci t xs b) => MkNConAlt n ci t xs <$> toStack k b) alts
             def' <- traverse (toStack k) def
             pure $ NmConCase fc sc alts' def'
    toStack k (NmConstCase fc sc alts def)
        = do Nothing <- findSite sc
               | Just s => push k s (\h => NmConstCase fc h alts def)
             alts' <- traverse (\(MkNConstAlt c b) => MkNConstAlt c <$> toStack k b) alts
             def' <- traverse (toStack k) def
             pure $ NmConstCase fc sc alts' def'
    toStack k e@(NmCrash _ _) = pure e
    toStack k e
        = case selfCall self (length args) e of
               -- a tail call of the function itself keeps the stack
               Just as => if any (isJust . evalState 0 . site self (length args)) as
                             then call
                             else pure (jump 0 as k (NmLocal EmptyFC resultName))
               Nothing => call
      where
        call : State St NamedCExp
        call = do Just s <- findSite e
                    | Nothing => pure (ret k e)
                  push k s id

-- The function `f` as a loop (named `loop`), if it has a call to transform.
transform : (f : Name) -> (loop : Name) -> FC -> List Name -> NamedCExp ->
            Maybe (List (Name, FC, NamedDef))
transform f loop fc args body
    = let (st, body0) = runState (MkSt 1 []) (toStack f loop args (NmLocal fc stackName) body) in
          case st.frames of
               [] => Nothing
               frames =>
                 let alts = MkNConAlt doneCon DATACON (Just 0) [] (NmLocal fc resultName)
                            :: map frameAlt (sortBy (comparing index) frames)
                     body1 = NmConCase fc (NmLocal fc stackName) alts Nothing
                     loopBody = NmConstCase fc (NmLocal fc modeName)
                                  [MkNConstAlt (I 0) body0] (Just body1)
                     wrapper = NmApp fc (NmRef fc loop)
                                 (NmPrimVal fc (I 0) :: map (NmLocal fc) args
                                    ++ [done, NmErased fc])
                  in Just [ (f, fc, MkNmFun args wrapper)
                          , (loop, fc, MkNmFun (modeName :: args ++ [stackName, resultName]) loopBody) ]
  where
    frameAlt : Frame -> NamedConAlt
    frameAlt fr = MkNConAlt (frameCon fr.index) DATACON (Just fr.index)
                    (fr.vars ++ [nextName fr.index]) fr.body

||| Compiles the functions that call themselves where the calls are not tail
||| calls to loops on an explicit stack (see the top of this module); the
||| other definitions stay as they are.
export
stackDefs : List (Name, FC, NamedDef) -> List (Name, FC, NamedDef)
stackDefs defs =
  let funs = mapMaybe fun defs
      graph : SortedMap Name (SortedSet Name)
      graph = fromList $ map (\(n, _, _, b) => (n, fromList (catMaybes (tailCallees b)))) funs
      -- the functions that are in a group of several that call each other
      -- by tail calls
      grouped = SortedSet.fromList $ concatMap forget $ filter (\g => length g > 1) $ tarjan graph
   in go grouped 0 defs
  where
    fun : (Name, FC, NamedDef) -> Maybe (Name, FC, List Name, NamedCExp)
    fun (n, fc, MkNmFun as b) = Just (n, fc, as, b)
    fun _ = Nothing

    go : SortedSet Name -> Int -> List (Name, FC, NamedDef) -> List (Name, FC, NamedDef)
    go grouped i [] = []
    go grouped i (d@(n, fc, MkNmFun as@(_ :: _) b) :: rest)
        = if contains n grouped
             then d :: go grouped i rest
             else case transform n (MN "$stk" i) fc as b of
                       Just ds => ds ++ go grouped (i + 1) rest
                       Nothing => d :: go grouped i rest
    go grouped i (d :: rest) = d :: go grouped i rest
