module Control.Monad.RWS.Interface

import Control.Monad.RWS.CPS
import Control.Monad.Reader.Interface
import Control.Monad.State.Interface
import Control.Monad.Writer.Interface

%default total

public export
interface (MonadReader r m, MonadWriter w m, MonadState s m) =>
  MonadRWS (0 r : Type) (0 w : Type) (0 s : Type) (0 m : Type -> Type) | m where

public export
(Monoid w, Monad m) => MonadRWS r w s (RWST r w s m) where
