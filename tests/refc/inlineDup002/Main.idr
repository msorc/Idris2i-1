-- An action given to the inlined bind of a monad over IO (like the Core of
-- the compiler) is used once, under the let of io_bind: it must not be
-- let-bound (a closure made and applied) when the bind is inlined.
module Main

import Data.IORef

record Core t where
  constructor MkCore
  runCore : IO (Either String t)

%inline
coreLift : IO a -> Core a
coreLift op = MkCore (do op' <- op
                         pure (Right op'))

%inline
(>>=) : Core a -> (a -> Core b) -> Core b
(>>=) (MkCore act) f
    = MkCore (act >>=
                   \case
                     Left err => pure $ Left err
                     Right val => runCore $ f val)

%inline
(>>) : Core () -> Core a -> Core a
ma >> mb = ma >>= const mb

%inline
pure : a -> Core a
pure x = MkCore (pure (pure x))

data Ref : (l : label) -> Type -> Type where
     [search l]
     MkRef : IORef a -> Ref x a

%inline
get : (0 x : label) -> {auto ref : Ref x a} -> Core a
get x {ref = MkRef io} = coreLift (readIORef io)

%inline
put : (0 x : label) -> {auto ref : Ref x a} -> a -> Core ()
put x {ref = MkRef io} val = coreLift (writeIORef io val)

data Bin : Type where

record Chunk where
  constructor MkChunk
  loc : Int
  size : Int

getTag : {auto b : Ref Bin Chunk} -> Core Int
getTag {b}
    = do chunk <- get Bin
         if loc chunk < size chunk
            then do put Bin ({ loc $= (+1) } chunk)
                    pure (loc chunk)
            else MkCore (pure (Left "end"))

main : IO ()
main = do
  r <- newIORef (MkChunk 0 3)
  Right v <- runCore (getTag {b = MkRef r}) | Left e => putStrLn e
  printLn v
