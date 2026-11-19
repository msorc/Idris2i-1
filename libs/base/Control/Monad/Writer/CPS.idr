||| Note: The difference to a 'strict' Writer implementation is
||| that accumulation of values does not happen in the
||| Applicative and Monad instances but when invoking `Writer`-specific
||| functions like `writer` or `listen`.
module Control.Monad.Writer.CPS

import Control.Monad.Identity
import Control.Monad.Trans

%default total

||| A writer monad parameterized by:
|||
|||   @w the output to accumulate.
|||
|||   @m The inner monad.
|||
||| The `pure` function produces the output `neutral`, while `>>=`
||| combines the outputs of the subcomputations using `<+>`.
public export
record WriterT (w : Type) (m : Type -> Type) (a : Type) where
  constructor MkWriterT
  unWriterT : w -> m (a, w)

||| Construct an writer computation from a (result,output) computation.
||| (The inverse of `runWriterT`.)
public export %inline
writerT : Semigroup w => Functor m => m (a, w) -> WriterT w m a
writerT f = MkWriterT $ \w => (\(a,w') => (a,w <+> w')) <$> f

||| Unwrap a writer computation.
||| (The inverse of 'writerT'.)
public export %inline
runWriterT : Monoid w => WriterT w m a -> m (a,w)
runWriterT m = unWriterT m neutral

||| Extract the output from a writer computation.
public export %inline
execWriterT : Monoid w => Functor m => WriterT w m a -> m w
execWriterT = map snd . runWriterT

||| Map both the return value and output of a computation using
||| the given function.
public export %inline
mapWriterT :  (Functor n, Monoid w, Semigroup w')
           => (m (a, w) -> n (b, w')) -> WriterT w m a -> WriterT w' n b
mapWriterT f m = MkWriterT $ \w =>
                  (\(a,w') => (a,w <+> w')) <$> f (runWriterT m)

--------------------------------------------------------------------------------
--          Writer Functions
--------------------------------------------------------------------------------

||| The `return` function produces the output `neutral`, while `>>=`
||| combines the outputs of the subcomputations using `<+>`.
public export
Writer : Type -> Type -> Type
Writer w = WriterT w Identity

||| Unwrap a writer computation as a (result, output) pair.
public export %inline
runWriter : Monoid w => Writer w a -> (a, w)
runWriter = runIdentity . runWriterT

||| Extract the output from a writer computation.
public export %inline
execWriter : Monoid w => Writer w a -> w
execWriter = runIdentity . execWriterT

||| Map both the return value and output of a computation using
||| the given function.
public export %inline
mapWriter :  (Monoid w, Semigroup w')
          => ((a, w) -> (b, w')) -> Writer w a -> Writer w' b
mapWriter f = mapWriterT $ \(Id p) => Id (f p)

--------------------------------------------------------------------------------
--          Implementations
--------------------------------------------------------------------------------

public export %inline
Functor m => Functor (WriterT w m) where
  map f m = MkWriterT $ \w => (\(a,w') => (f a,w')) <$> unWriterT m w

public export %inline
Monad m => Applicative (WriterT w m) where
  pure a = MkWriterT $ \w => pure (a,w)
  MkWriterT mf <*> MkWriterT mx =
    MkWriterT $ \w => do (f,w1) <- mf w
                         (a,w2) <- mx w1
                         pure (f a,w2)

public export %inline
(Monad m, Alternative m) => Alternative (WriterT w m) where
  empty = MkWriterT $ \_ => empty
  MkWriterT m <|> mn = MkWriterT $ \w => m w <|> unWriterT mn w

public export %inline
Monad m => Monad (WriterT w m) where
  m >>= k = MkWriterT $ \w => do (a,w1) <- unWriterT m w
                                 unWriterT (k a) w1

public export %inline
MonadTrans (WriterT w) where
  lift m = MkWriterT $ \w => map (\a => (a,w)) m

public export %inline
HasIO m => HasIO (WriterT w m) where
  liftIO = lift . liftIO

-- In `WriterT` over `IO` or `Identity`, `<*>` is `ap`, and `>>=` calls its
-- continuation as a tail call: `traverse` and friends on lists are transformed
-- to the loops with `>>=` of `Control.Monad.Trans`, which run in constant
-- stack on the JavaScript backends (see there).

%transform "writerTIOTraverseList" traverse {t = List} {f = WriterT w IO} = bindTraverseList
%transform "writerTIOForList" for {t = List} {f = WriterT w IO} xs f = bindTraverseList f xs
%transform "writerTIOSequenceList" sequence {t = List} {f = WriterT w IO} {a} xs = bindTraverseList {a = WriterT w IO a} {b = a} id xs
%transform "writerTIOTraverseList_" traverse_ {t = List} {f = WriterT w IO} = bindTraverseList_
%transform "writerTIOForList_" for_ {t = List} {f = WriterT w IO} xs f = bindTraverseList_ f xs
%transform "writerTIOSequenceList_" sequence_ {t = List} {f = WriterT w IO} {a} xs = bindTraverseList_ {a = WriterT w IO a} {b = a} id xs
%transform "writerTIOSeqRight" (*>) {f = WriterT w IO} = bindSeqRight
%transform "writerTIOFoldlMList" foldlM {t = List} {m = WriterT w IO} = bindFoldlMList

%transform "writerTraverseList" traverse {t = List} {f = WriterT w Identity} = bindTraverseList
%transform "writerForList" for {t = List} {f = WriterT w Identity} xs f = bindTraverseList f xs
%transform "writerSequenceList" sequence {t = List} {f = WriterT w Identity} {a} xs = bindTraverseList {a = WriterT w Identity a} {b = a} id xs
%transform "writerTraverseList_" traverse_ {t = List} {f = WriterT w Identity} = bindTraverseList_
%transform "writerForList_" for_ {t = List} {f = WriterT w Identity} xs f = bindTraverseList_ f xs
%transform "writerSequenceList_" sequence_ {t = List} {f = WriterT w Identity} {a} xs = bindTraverseList_ {a = WriterT w Identity a} {b = a} id xs
%transform "writerSeqRight" (*>) {f = WriterT w Identity} = bindSeqRight
%transform "writerFoldlMList" foldlM {t = List} {m = WriterT w Identity} = bindFoldlMList
