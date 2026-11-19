module Main

-- Chains of actions as long as a list (traverse and friends, foldr (*>),
-- foldlM) in the monad transformers of base over IO, Identity, Either and
-- Maybe, in EitherT and MaybeT over IO, on SnocList, List1 and Vect in IO, and
-- many of Data.String.Parser: the library runs them as loops (which the
-- browser backend needs, see tests/node/applchain_browser).  The results and
-- the order of the effects are those of the chains.

import Control.Monad.State
import Control.Monad.Reader
import Control.Monad.Writer
import Control.Monad.RWS
import Control.Monad.Either
import Control.Monad.Maybe
import Control.Monad.Identity
import Data.IORef
import Data.List
import Data.List1
import Data.SnocList
import Data.Vect
import Data.String.Parser

%default covering

record S where
  constructor MkS
  unS : Integer

Semigroup S where
  MkS a <+> MkS b = MkS (a + b)

Monoid S where
  neutral = MkS 0

n : Integer
n = 100000

xs : List Integer
xs = [1 .. n]

small : List Integer
small = [1, 2, 3]

-- What the actions in IO did, in order.
%noinline
logRef : IORef (List String)
logRef = unsafePerformIO (newIORef [])

say : HasIO io => String -> io ()
say s = liftIO (modifyIORef logRef (s ::))

said : IO String
said = do l <- readIORef logRef
          writeIORef logRef []
          pure (show (reverse l))

%noinline
count : IORef Integer
count = unsafePerformIO (newIORef 0)

bump : HasIO io => io ()
bump = liftIO (modifyIORef count (+ 1))

counted : IO Integer
counted = do c <- readIORef count; writeIORef count 0; pure c

line : String -> String -> IO ()
line s r = putStrLn (s ++ ": " ++ r)

stateTIO : IO ()
stateTIO = do
  let step : Integer -> StateT Integer IO Integer
      step x = do modify (+ x); bump; pure (x * 2)
  (s, ys) <- runStateT 0 (traverse step xs)
  line "StateT IO traverse" (show s ++ " " ++ show (sum ys) ++ " " ++ show !counted)
  (s, ys) <- runStateT 0 (for xs step)
  line "StateT IO for" (show s ++ " " ++ show (sum ys))
  (s, ys) <- runStateT 0 (sequence (map step xs))
  line "StateT IO sequence" (show s ++ " " ++ show (sum ys))
  (s, _) <- runStateT 0 (traverse_ step xs)
  line "StateT IO traverse_" (show s)
  (s, _) <- runStateT 0 (for_ xs step)
  line "StateT IO for_" (show s)
  (s, _) <- runStateT 0 (sequence_ (map step xs))
  line "StateT IO sequence_" (show s)
  (s, _) <- runStateT 0 (foldr (*>) (pure ()) (map (ignore . step) xs))
  line "StateT IO *>" (show s ++ " " ++ show !counted)
  (s, a) <- runStateT 0 (foldlM (\acc, x => map (+ acc) (step x)) 0 xs)
  line "StateT IO foldlM" (show s ++ " " ++ show a)
  -- the order of the effects, on the state and in IO
  let ostep : Integer -> StateT (List Integer) IO Integer
      ostep x = do say ("s" ++ show x); modify (x ::); gets (cast . length)
  (s, ys) <- runStateT [] (traverse ostep small)
  line "StateT IO order" (show s ++ " " ++ show ys ++ " " ++ !said)
  (s, ()) <- runStateT [] (traverse_ ostep small)
  line "StateT IO order_" (show s ++ " " ++ !said)
  (s, v) <- runStateT [] (ostep 1 *> ostep 2 *> pure 7)
  line "StateT IO order *>" (show s ++ " " ++ show v ++ " " ++ !said)
  (s, v) <- runStateT [] (foldlM (\acc, x => map (+ acc) (ostep x)) 0 small)
  line "StateT IO order foldlM" (show s ++ " " ++ show v ++ " " ++ !said)

readerTIO : IO ()
readerTIO = do
  let step : Integer -> ReaderT Integer IO Integer
      step x = do r <- ask; bump; pure (x * 2 + r)
  ys <- runReaderT 1 (traverse step xs)
  line "ReaderT IO traverse" (show (sum ys) ++ " " ++ show !counted)
  ys <- runReaderT 1 (sequence (map step xs))
  line "ReaderT IO sequence" (show (sum ys))
  runReaderT 1 (for_ xs step)
  line "ReaderT IO for_" (show !counted)
  runReaderT 1 (foldr (*>) (pure ()) (map (ignore . step) xs))
  line "ReaderT IO *>" (show !counted)
  a <- runReaderT 1 (foldlM (\acc, x => map (+ acc) (step x)) 0 xs)
  line "ReaderT IO foldlM" (show a)
  let rstep : Integer -> ReaderT Integer IO Integer
      rstep x = do r <- ask; say ("r" ++ show x); pure (x + r)
  ys <- runReaderT 10 (for small rstep)
  line "ReaderT IO order" (show ys ++ " " ++ !said)

writerTIO : IO ()
writerTIO = do
  let step : Integer -> WriterT S IO Integer
      step x = do tell (MkS x); bump; pure (x * 2)
  (ys, MkS w) <- runWriterT (traverse step xs)
  line "WriterT IO traverse" (show w ++ " " ++ show (sum ys) ++ " " ++ show !counted)
  (_, MkS w) <- runWriterT (traverse_ step xs)
  line "WriterT IO traverse_" (show w)
  (_, MkS w) <- runWriterT (foldr (*>) (pure ()) (map (ignore . step) xs))
  line "WriterT IO *>" (show w)
  (a, MkS w) <- runWriterT (foldlM (\acc, x => map (+ acc) (step x)) 0 xs)
  line "WriterT IO foldlM" (show w ++ " " ++ show a)
  let ostep : Integer -> WriterT (List String) IO Integer
      ostep x = do say ("w" ++ show x); tell ["t" ++ show x]; pure x
  (ys, w) <- runWriterT (traverse ostep small)
  line "WriterT IO order" (show ys ++ " " ++ show w ++ " " ++ !said)

identities : IO ()
identities = do
  -- Writer
  let wstep : Integer -> Writer S Integer
      wstep x = do tell (MkS x); pure (x * 2)
  let (ys, MkS w) = runWriter (traverse wstep xs)
  line "Writer traverse" (show w ++ " " ++ show (sum ys))
  let (_, MkS w) = runWriter (sequence_ (map wstep xs))
  line "Writer sequence_" (show w)
  let (_, MkS w) = runWriter (foldr (*>) (pure ()) (map (ignore . wstep) xs))
  line "Writer *>" (show w)
  let (a, MkS w) = runWriter (foldlM (\acc, x => map (+ acc) (wstep x)) 0 xs)
  line "Writer foldlM" (show w ++ " " ++ show a)
  let ows : Integer -> Writer (List Integer) Integer
      ows x = do tell [x]; pure (x * 10)
  let (ys, w) = runWriter (for small ows)
  line "Writer order" (show ys ++ " " ++ show w)
  -- Reader
  let rstep : Integer -> Reader Integer Integer
      rstep x = do r <- ask; pure (x * 2 + r)
  line "Reader traverse" (show (sum (runReader 1 (traverse rstep xs))))
  line "Reader for" (show (sum (runReader 1 (for xs rstep))))
  line "Reader traverse_" (show (runReader 1 (traverse_ rstep xs)))
  line "Reader foldlM" (show (runReader 1 (foldlM (\acc, x => map (+ acc) (rstep x)) 0 xs)))
  -- RWS
  let step : Integer -> RWS Integer S Integer Integer
      step x = do r <- ask; tell (MkS x); modify (+ 1); pure (x * 2 + r)
  let (ys, s, MkS w) = runRWS 1 0 (traverse step xs)
  line "RWS traverse" (show s ++ " " ++ show w ++ " " ++ show (sum ys))
  let (_, s, MkS w) = runRWS 1 0 (for_ xs step)
  line "RWS for_" (show s ++ " " ++ show w)
  let (_, s, MkS w) = runRWS 1 0 (foldr (*>) (pure ()) (map (ignore . step) xs))
  line "RWS *>" (show s ++ " " ++ show w)
  let (a, s, MkS w) = runRWS 1 0 (foldlM (\acc, x => map (+ acc) (step x)) 0 xs)
  line "RWS foldlM" (show s ++ " " ++ show w ++ " " ++ show a)
  let orws : Integer -> RWS Integer (List Integer) (List Integer) Integer
      orws x = do r <- ask; tell [x]; modify (x ::); pure (x + r)
  let (ys, s, w) = runRWS 100 [] (traverse orws small)
  line "RWS order" (show ys ++ " " ++ show s ++ " " ++ show w)
  -- State, foldlM
  let (s, a) = runState 0 (foldlM (\acc, x => do modify (+ 1); pure (acc + x)) 0 xs)
  line "State foldlM" (show s ++ " " ++ show a)

-- A Left (Nothing) in EitherT (MaybeT): traverse and *> run the IO actions
-- after it (<*> runs both), foldlM and >>= do not.
eitherT : IO ()
eitherT = do
  let step : Integer -> EitherT String IO Integer
      step x = do bump; pure (x * 2)
  r <- runEitherT (traverse step xs)
  line "EitherT IO traverse" (show (map sum r) ++ " " ++ show !counted)
  r <- runEitherT (for_ xs step)
  line "EitherT IO for_" (show r ++ " " ++ show !counted)
  r <- runEitherT (sequence (map step xs))
  line "EitherT IO sequence" (show (map sum r))
  r <- runEitherT (foldr (*>) (pure ()) (map (ignore . step) xs))
  line "EitherT IO *>" (show r ++ " " ++ show !counted)
  r <- runEitherT (foldlM (\acc, x => map (+ acc) (step x)) 0 xs)
  line "EitherT IO foldlM" (show r)
  let ostep : Integer -> EitherT String IO Integer
      ostep x = do say ("e" ++ show x); if x == 2 || x == 3 then left ("bad" ++ show x) else pure x
  r <- runEitherT (traverse ostep small)
  line "EitherT IO order" (show r ++ " " ++ !said)
  r <- runEitherT (traverse_ ostep small)
  line "EitherT IO order_" (show r ++ " " ++ !said)
  r <- runEitherT (ostep 1 *> ostep 2 *> ostep 3 *> ostep 4)
  line "EitherT IO order *>" (show r ++ " " ++ !said)
  r <- runEitherT (foldlM (\acc, x => map (+ acc) (ostep x)) 0 small)
  line "EitherT IO order foldlM" (show r ++ " " ++ !said)

maybeT : IO ()
maybeT = do
  let step : Integer -> MaybeT IO Integer
      step x = do bump; pure (x * 2)
  r <- runMaybeT (traverse step xs)
  line "MaybeT IO traverse" (show (map sum r) ++ " " ++ show !counted)
  r <- runMaybeT (traverse_ step xs)
  line "MaybeT IO traverse_" (show r ++ " " ++ show !counted)
  r <- runMaybeT (foldr (*>) (pure ()) (map (ignore . step) xs))
  line "MaybeT IO *>" (show r ++ " " ++ show !counted)
  r <- runMaybeT (foldlM (\acc, x => map (+ acc) (step x)) 0 xs)
  line "MaybeT IO foldlM" (show r)
  let ostep : Integer -> MaybeT IO Integer
      ostep x = do say ("m" ++ show x); if x == 2 then nothing else pure x
  r <- runMaybeT (for small ostep)
  line "MaybeT IO order" (show r ++ " " ++ !said)
  r <- runMaybeT (sequence_ (map ostep small))
  line "MaybeT IO order_" (show r ++ " " ++ !said)
  r <- runMaybeT (ostep 2 *> ostep 3)
  line "MaybeT IO order *>" (show r ++ " " ++ !said)

stateTOther : IO ()
stateTOther = do
  let estep : Integer -> StateT Integer (Either String) Integer
      estep x = do modify (+ x); when (x < 0) (lift (Left "neg")); pure (x * 2)
  line "StateT Either traverse" (show (map (\p => (fst p, sum (snd p))) (runStateT 0 (traverse estep xs))))
  line "StateT Either traverse_" (show (map fst (runStateT 0 (traverse_ estep xs))))
  line "StateT Either *>" (show (map fst (runStateT 0 (foldr (*>) (pure ()) (map (ignore . estep) xs)))))
  line "StateT Either foldlM" (show (runStateT 0 (foldlM (\acc, x => map (+ acc) (estep x)) 0 xs)))
  let oes : Integer -> StateT (List Integer) (Either String) ()
      oes x = do modify (x ::); when (x == 2) (lift (Left ("stop" ++ show x)))
  line "StateT Either order" (show (runStateT [] (traverse oes small)))
  line "StateT Either order_" (show (runStateT [] (traverse_ oes (the (List Integer) [1, 3]))))
  let mstep : Integer -> StateT Integer Maybe Integer
      mstep x = do modify (+ x); pure (x * 2)
  line "StateT Maybe traverse" (show (map (\p => (fst p, sum (snd p))) (runStateT 0 (traverse mstep xs))))
  line "StateT Maybe for_" (show (map fst (runStateT 0 (for_ xs mstep))))

containers : IO ()
containers = do
  let sx : SnocList Integer
      sx = [<] <>< xs
  ys <- traverse (\x => do bump; pure (x * 2)) sx
  line "SnocList IO traverse" (show (sum ys) ++ " " ++ show !counted)
  traverse_ (\x => bump) sx
  line "SnocList IO traverse_" (show !counted)
  ys <- traverse (\x => do say (show x); pure x) ([<] <>< small)
  line "SnocList IO order" (show ys ++ " " ++ !said)
  let l1 : List1 Integer
      l1 = 0 ::: xs
  ys <- traverse (\x => do bump; pure (x * 2)) l1
  line "List1 IO traverse" (show (sum ys) ++ " " ++ show !counted)
  for_ l1 (\x => bump)
  line "List1 IO for_" (show !counted)
  ys <- traverse (\x => do say (show x); pure x) (0 ::: small)
  line "List1 IO order" (show ys ++ " " ++ !said)
  case toVect 100000 xs of
    Nothing => putStrLn "no Vect"
    Just v => do traverse_ (\x => bump) v
                 line "Vect IO traverse_" (show !counted)
  sequence_ (map (\x => say (show x)) (Vect.fromList small))
  line "Vect IO order_" !said

parser : IO ()
parser = do
  let s = pack (replicate 100000 'a' ++ ['b'])
  line "Parser many" (show (map (\p => (length (fst p), snd p)) (parse (many (char 'a')) s)))
  line "Parser takeWhile" (show (map (\p => (length (fst p), snd p)) (parse (takeWhile (== 'a')) s)))
  line "Parser some" (show (map (\p => (length (fst p), snd p)) (parse (some (char 'a') <* char 'b') s)))
  line "Parser some fails" (show (parse (some (char 'b')) "abc"))
  line "Parser many order" (show (parse [| MkPair (many (char 'a')) (many (char 'b')) |] "aabbbc"))

main : IO ()
main = do
  stateTIO
  readerTIO
  writerTIO
  identities
  eitherT
  maybeT
  stateTOther
  containers
  parser
