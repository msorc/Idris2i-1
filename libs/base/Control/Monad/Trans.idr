module Control.Monad.Trans

%default total

||| A monad transformer is a type that can wrap an inner monad, extending it
||| with additional abilities.
public export
interface MonadTrans (0 t : (Type -> Type) -> Type -> Type) where
    ||| Lift a computation from the inner monad to the transformed monad.
    lift : Monad m => m a -> t m a

--------------------------------------------------------------------------------
--          Loops over lists in a monad
--------------------------------------------------------------------------------

-- `traverse` on a list builds a chain of `<*>` as long as the list, and
-- `traverse_` and `foldr (*>)` a chain of `*>`; in a monad transformer such as
-- `StateT s IO`, each action of the chain runs the rest of the chain before it
-- returns, so running it needs a stack as deep as the list, which overflows on
-- the JavaScript backends.  `foldlM` nests its `>>=` to the left, with the same
-- effect.  The functions below do the same with `>>=` alone, where the rest of
-- the list is the continuation: in a monad whose `>>=` calls its continuation
-- as a tail call (`IO`, `Identity`, and the transformers of this library over
-- them), they run in constant stack.  In a monad where `<*>` is `ap` (it runs
-- the first action, then the second, then applies the function), they have the
-- effects of the original in the same order; the transformers transform uses
-- of `traverse` and friends on lists to them where that is so.

||| `traverse` on a list, with `>>=`: the results are collected in a
||| `SnocList`, and the rest of the list is the continuation of each action.
public export
bindTraverseList : Monad m => (a -> m b) -> List a -> m (List b)
bindTraverseList f xs = go [<] xs
  where
    go : SnocList b -> List a -> m (List b)
    go acc [] = pure (acc <>> [])
    go acc (x :: xs) = f x >>= \y => go (acc :< y) xs

||| `traverse_` on a list, with `>>=` (see `bindTraverseList`).
public export
bindTraverseList_ : Monad m => (a -> m b) -> List a -> m ()
bindTraverseList_ f [] = pure ()
bindTraverseList_ f (x :: xs) = f x >>= \_ => bindTraverseList_ f xs

||| `foldlM` on a list, with `>>=` (see `bindTraverseList`).
public export
bindFoldlMList : Monad m => (acc -> a -> m acc) -> acc -> List a -> m acc
bindFoldlMList f a [] = pure a
bindFoldlMList f a (x :: xs) = f a x >>= \a' => bindFoldlMList f a' xs

||| `*>` with `>>=`, where the second action is the continuation.
public export
bindSeqRight : Monad m => m a -> m b -> m b
bindSeqRight a b = a >>= \_ => b
