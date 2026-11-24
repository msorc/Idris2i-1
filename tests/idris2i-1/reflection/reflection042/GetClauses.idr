import Language.Reflection
import Lib

%language ElabReflection
%default total

local : List a -> Nat
local [] = 0
local (_ :: xs) = S (local xs)

private
hidden : Bool -> Bool
hidden True = False
hidden False = True

void' : Void -> a
void' x impossible

run : Elab a -> Elab ()
run = ignore

logClauses : Name -> Elab ()
logClauses n = do
  cs <- getClauses n
  logMsg "" 0 "\{show n}: \{show (length cs)} clause(s)"
  traverse_ (\c => logMsg "" 0 $ "  " ++ showClause InDecl c) cs

tests : Elab ()
tests = do
  logClauses `{local}
  logClauses `{hidden}
  logClauses `{plus}
  logClauses `{Lib.pub}
  logClauses `{void'}

%runElab tests

-- export and private definitions of other modules: their bodies are hidden
failing "The clauses of Lib.abstr are not visible here: it is export"
  %runElab run (getClauses `{Lib.abstr})

failing "The clauses of Lib.priv are not visible here: it is private"
  %runElab run (getClauses `{Lib.priv})

-- names which are not functions defined by pattern matching
failing "Prelude.Types.S is not a function defined by pattern matching"
  %runElab run (getClauses `{S})

failing "Prelude.Types.Nat is not a function defined by pattern matching"
  %runElab run (getClauses `{Nat})

failing "prim__add_Int is not a function defined by pattern matching"
  %runElab run (getClauses `{prim__add_Int})

failing "nothingHere is not defined"
  %runElab run (getClauses `{nothingHere})
