-- Elaborator scripts in a compiled program. Only the elaborator runs a
-- script and nothing can run one at run time, so no back end implements
-- the primitives of `Elab`: a script built at run time is an erased value.
-- A program which builds scripts (a top-level one, one in a lazy field and
-- forced, functions returning one, the dictionaries of `Monad Elab` and
-- `Elaboration Elab`) compiles and runs as before.
module Main

import Language.Reflection

%language ElabReflection

script : Elab ()
script = logMsg "test" 0 "never"

record Tactic where
  constructor MkTactic
  name : String
  run : Lazy (Elab ())

tactics : List Tactic
tactics = [MkTactic "log" script, MkTactic "warn" (warn "never")]

named : String -> Elab ()
named = logMsg "test" 0

-- polymorphic in the monad, used at Elab
twice : Monad m => m () -> m ()
twice x = x >> x

-- polymorphic in the elaboration monad, used at Elab
%noinline
logIt : Elaboration m => String -> m ()
logIt = logMsg "test" 0

-- `%runElab` runs at compile time
two : Nat
two = %runElab pure 2

%noinline
built : Elab a -> String
built _ = "built"

main : IO ()
main = do
  printLn two
  traverse_ (putStrLn . name) tactics
  let fs = [named, \s => twice (named s), logIt]
  printLn (length fs)
  printLn (length [the (Elab ()) empty, goal >>= \_ => pure ()])
  putStrLn (built (force (run (MkTactic "x" script))))
  putStrLn (built (twice script))
  putStrLn (built (traverse_ (\f => f "x") fs))
