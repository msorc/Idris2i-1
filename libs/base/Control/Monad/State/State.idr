module Control.Monad.State.State

import Control.Monad.Identity
import Control.Monad.Trans

%default total

||| A monad transformer extending an inner monad `m` with state `stateType`.
|||
||| Updates to the state are applied in the order as the sequence of actions.
public export
record StateT (stateType : Type) (m : Type -> Type) (a : Type) where
  constructor ST
  runStateT' : stateType -> m (stateType, a)

||| Unwrap and apply a StateT monad computation.
public export
%inline
runStateT : stateType -> StateT stateType m a -> m (stateType, a)
runStateT s act = runStateT' act s

||| Unwrap and apply a StateT monad computation, but discard the final state.
public export %inline
evalStateT : Functor m => stateType -> StateT stateType m a -> m a
evalStateT s = map snd . runStateT s

||| Unwrap and apply a StateT monad computation, but discard the resulting value.
public export %inline
execStateT : Functor m => stateType -> StateT stateType m a -> m stateType
execStateT s = map fst . runStateT s

||| Map both the return value and final state of a computation using
||| the given function.
public export %inline
mapStateT : (m (s, a) -> n (s, b)) -> StateT s m a -> StateT s n b
mapStateT f m = ST $ f . runStateT' m

--------------------------------------------------------------------------------
--          State
--------------------------------------------------------------------------------

||| The State monad. See the MonadState interface
public export
State : (stateType : Type) -> (ty : Type) -> Type
State = \s, a => StateT s Identity a

||| Unwrap and apply a State monad computation.
public export %inline
runState : stateType -> State stateType a -> (stateType, a)
runState s act = runIdentity (runStateT s act)

||| Unwrap and apply a State monad computation, but discard the final state.
public export %inline
evalState : stateType -> State stateType a -> a
evalState s = snd . runState s

||| Unwrap and apply a State monad computation, but discard the resulting value.
public export %inline
execState : stateType -> State stateType a -> stateType
execState s = fst . runState s

||| Map both the return value and final state of a computation using
||| the given function.
public export %inline
mapState : ((s, a) -> (s, b)) -> State s a -> State s b
mapState f = mapStateT $ \(Id p) => Id (f p)

--------------------------------------------------------------------------------
--          Implementations
--------------------------------------------------------------------------------

public export
implementation Functor f => Functor (StateT stateType f) where
    map f (ST g) = ST $ \st => map f <$> g st

public export
implementation Monad f => Applicative (StateT stateType f) where
    pure x = ST $ \st => pure (st, x)

    ST f <*> ST a
        = ST $ \st =>
               do (r, g) <- f st
                  (t, b) <- a r
                  pure (t, g b)

public export
implementation Monad m => Monad (StateT stateType m) where
    ST f >>= k
        = ST $ \st =>
               do (st', v) <- f st
                  runStateT st' $ k v

--------------------------------------------------------------------------------
--          Loops over lists in State
--------------------------------------------------------------------------------

-- `traverse` on a list builds a chain of `<*>` as long as the list, and the
-- state function of `<*>` calls the one of the rest of the chain before it
-- returns: running it needs a stack as deep as the list, which overflows on
-- the JavaScript backends.  So do a chain of `*>`.  In `State` (whose monad,
-- `Identity`, needs nothing after its continuation), the functions below are
-- loops that pass the state on from one element to the next instead, and the
-- uses of `traverse`, `for`, `sequence`, `traverse_`, `for_`, `sequence_` on
-- lists, and of `*>`, in `State` are transformed to them.

||| `traverse` on a list in `State`, as a loop.
public export
stateTraverseList : (a -> StateT s Identity b) -> List a -> StateT s Identity (List b)
stateTraverseList f xs = ST $ \st => Id (go st [<] xs)
  where
    go : s -> SnocList b -> List a -> (s, List b)
    go st acc [] = (st, acc <>> [])
    go st acc (x :: xs) = case runIdentity (runStateT' (f x) st) of
                               (st', y) => go st' (acc :< y) xs

||| `traverse_` on a list in `State`, as a loop.
public export
stateTraverseList_ : (a -> StateT s Identity b) -> List a -> StateT s Identity ()
stateTraverseList_ f xs = ST $ \st => Id (go st xs)
  where
    go : s -> List a -> (s, ())
    go st [] = (st, ())
    go st (x :: xs) = case runIdentity (runStateT' (f x) st) of
                           (st', _) => go st' xs

||| `*>` in `State`, where the second action is a tail call.
public export
stateSeqRight : StateT s Identity a -> StateT s Identity b -> StateT s Identity b
stateSeqRight a b = ST $ \st => case runIdentity (runStateT' a st) of
                                     (st', _) => runStateT' b st'

%transform "stateTraverseList" traverse {t = List} {f = StateT s Identity} = stateTraverseList
%transform "stateForList" for {t = List} {f = StateT s Identity} xs f = stateTraverseList f xs
%transform "stateSequenceList" sequence {t = List} {f = StateT s Identity} {a} xs = stateTraverseList {a = StateT s Identity a} {b = a} id xs
%transform "stateTraverseList_" traverse_ {t = List} {f = StateT s Identity} = stateTraverseList_
%transform "stateForList_" for_ {t = List} {f = StateT s Identity} xs f = stateTraverseList_ f xs
%transform "stateSequenceList_" sequence_ {t = List} {f = StateT s Identity} {a} xs = stateTraverseList_ {a = StateT s Identity a} {b = a} id xs
%transform "stateSeqRight" (*>) {f = StateT s Identity} = stateSeqRight

public export
implementation MonadTrans (StateT stateType) where
    lift x = ST $ \st => (st,) <$> x

public export
implementation (Monad f, Alternative f) => Alternative (StateT st f) where
    empty = lift empty
    ST f <|> mg = ST $ \st => f st <|> runStateT' mg st

public export
implementation HasIO m => HasIO (StateT stateType m) where
  liftIO io = ST $ \s => liftIO $ io_bind io $ \a => pure (s, a)
