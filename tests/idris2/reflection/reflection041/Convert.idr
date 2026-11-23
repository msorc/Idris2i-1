import Language.Reflection

%language ElabReflection
%default total

run : Elab a -> Elab ()
run = ignore

logConv : TTImp -> TTImp -> Elab ()
logConv x y = do
  b <- convertible x y
  logTerm "" 0 "first" x
  logTerm "" 0 "second" y
  logMsg "" 0 "  convertible: \{show b}"

tests : Elab ()
tests = do
  logConv `(plus 1 1) `(2)
  logConv `(\x => plus 0 x) `(\y => y)
  -- stuck on a variable: not convertible, though provably equal
  logConv `(\x => plus x 0) `(\y => y)
  logConv `(List Nat) `(List (Nat))
  logConv `(Nat) `(Bool)
  -- the second term is checked at the type of the first
  logConv `(the Integer 2) `(1 + 1)

%runElab tests

-- a term which does not elaborate at the type of the first one is an error
failing "Mismatch between"
  %runElab run (convertible `(plus 1 1) `(True))

tryConv : Elab ()
tryConv = do
  r <- catch (convertible `(plus 1 1) `(True))
  logMsg "" 0 "caught: \{show r}"

%runElab tryConv

-- nothing the elaboration did survives: no hole is left behind
noTrace : Elab ()
noTrace = do
  b <- convertible `(?h) `(the Nat 1)
  logMsg "" 0 "hole ~ 1: \{show b}"

%runElab noTrace
