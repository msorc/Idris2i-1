module Control.Monad.Reader.Reader

import Control.Monad.Identity
import Control.Monad.Trans

%default total

||| A monad transformer extending an inner monad with access to an environment.
|||
||| The environment is the same for all actions in a sequence, but may be
||| changed within scopes created by `Control.Monad.Reader.local`.
public export
record ReaderT (stateType : Type) (m : Type -> Type) (a : Type) where
  constructor MkReaderT
  1 runReaderT' : stateType -> m a

||| Transform the computation inside a @ReaderT@.
public export %inline
mapReaderT : (m a -> n b) -> ReaderT r m a -> ReaderT r n b
mapReaderT f m = MkReaderT $ \st => f (runReaderT' m st)

||| Unwrap and apply a ReaderT monad computation
public export
%inline
runReaderT : stateType -> ReaderT stateType m a -> m a
runReaderT s action = runReaderT' action s

--------------------------------------------------------------------------------
--          Reader
--------------------------------------------------------------------------------

||| A monad that can access an environment.
|||
||| This is `ReaderT` applied to `Identity`.
public export
Reader : (stateType : Type) -> (a : Type) -> Type
Reader s = ReaderT s Identity

||| Unwrap and apply a Reader monad computation
public export %inline
runReader : stateType -> Reader stateType a -> a
runReader s = runIdentity . runReaderT s

--------------------------------------------------------------------------------
--          Implementations
--------------------------------------------------------------------------------

public export
implementation Functor f => Functor (ReaderT stateType f) where
  map f (MkReaderT g) = MkReaderT $ \st => f <$> g st

public export
implementation Applicative f => Applicative (ReaderT stateType f) where
  pure x = MkReaderT $ \_ => pure x

  MkReaderT f <*> MkReaderT a =
    MkReaderT $ \st =>
      let f' = f st in
      let a' = a st in
      f' <*> a'

public export
implementation Monad m => Monad (ReaderT stateType m) where
  MkReaderT f >>= k =
    MkReaderT $ \st => f st >>= runReaderT st . k

public export
implementation MonadTrans (ReaderT stateType) where
  lift x = MkReaderT $ \_ => x

public export
implementation HasIO m => HasIO (ReaderT stateType m) where
  liftIO f = MkReaderT $ \_ => liftIO f

public export
implementation Alternative f => Alternative (ReaderT stateType f) where
  empty = MkReaderT $ const empty

  MkReaderT f <|> mg = MkReaderT $ \st => f st <|> runReaderT' mg st

-- In `ReaderT` over `IO` or `Identity`, `<*>` is `ap`, and `>>=` calls its
-- continuation as a tail call: `traverse` and friends on lists are transformed
-- to the loops with `>>=` of `Control.Monad.Trans`, which run in constant
-- stack on the JavaScript backends (see there).

%transform "readerTIOTraverseList" traverse {t = List} {f = ReaderT r IO} = bindTraverseList
%transform "readerTIOForList" for {t = List} {f = ReaderT r IO} xs f = bindTraverseList f xs
%transform "readerTIOSequenceList" sequence {t = List} {f = ReaderT r IO} {a} xs = bindTraverseList {a = ReaderT r IO a} {b = a} id xs
%transform "readerTIOTraverseList_" traverse_ {t = List} {f = ReaderT r IO} = bindTraverseList_
%transform "readerTIOForList_" for_ {t = List} {f = ReaderT r IO} xs f = bindTraverseList_ f xs
%transform "readerTIOSequenceList_" sequence_ {t = List} {f = ReaderT r IO} {a} xs = bindTraverseList_ {a = ReaderT r IO a} {b = a} id xs
%transform "readerTIOSeqRight" (*>) {f = ReaderT r IO} = bindSeqRight
%transform "readerTIOFoldlMList" foldlM {t = List} {m = ReaderT r IO} = bindFoldlMList

%transform "readerTraverseList" traverse {t = List} {f = ReaderT r Identity} = bindTraverseList
%transform "readerForList" for {t = List} {f = ReaderT r Identity} xs f = bindTraverseList f xs
%transform "readerSequenceList" sequence {t = List} {f = ReaderT r Identity} {a} xs = bindTraverseList {a = ReaderT r Identity a} {b = a} id xs
%transform "readerTraverseList_" traverse_ {t = List} {f = ReaderT r Identity} = bindTraverseList_
%transform "readerForList_" for_ {t = List} {f = ReaderT r Identity} xs f = bindTraverseList_ f xs
%transform "readerSequenceList_" sequence_ {t = List} {f = ReaderT r Identity} {a} xs = bindTraverseList_ {a = ReaderT r Identity a} {b = a} id xs
%transform "readerSeqRight" (*>) {f = ReaderT r Identity} = bindSeqRight
%transform "readerFoldlMList" foldlM {t = List} {m = ReaderT r Identity} = bindFoldlMList
