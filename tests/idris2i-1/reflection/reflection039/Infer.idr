import Language.Reflection
import Data.Maybe

%language ElabReflection
%default total

run : Elab a -> Elab ()
run = ignore

logInfer : TTImp -> Elab ()
logInfer t = do
  (tm, ty) <- infer t
  logTerm "" 0 "term" tm
  logTerm "" 0 "type" ty

-- a term with no expected type
inferred : Elab ()
inferred = do
  logInfer `(plus 1 2)
  logInfer `(the (List Nat) [1, 2])
  -- defaults are resolved: an integer literal is an Integer
  logInfer `(3)
  logInfer `(\x : Nat => x + 1)
  logInfer `(Nat -> Type)
  -- implicit arguments solved from the explicit ones
  logInfer `(Just 'c')

%runElab inferred

-- local variables are in scope
localVar : Nat -> List Nat
localVar n = %runElab (do logInfer `(n * 2)
                          logInfer `([n, S n])
                          check `([n]))

-- the result can be used: check the inferred type, then the term at it
roundTrip : Elab ()
roundTrip = do
  (tm, ty) <- infer `(the (List Nat) [length "four"])
  tyv <- check {expected = Type} ty
  v <- check {expected = tyv} tm
  logTerm "" 0 "round trip" !(quote v)

%runElab roundTrip

-- an unsolved metavariable is an error
failing "Can't infer the term of Prelude.Nil completely"
  %runElab run (infer `(Prelude.Nil))

failing "it contains the unsolved"
  %runElab run (infer `(\x => x))

-- elaboration errors are reported as such
failing "Undefined name undefinedName"
  %runElab run (infer `(undefinedName 1))

-- a failed search is an error too, not a delayed constraint
failing "Can't find an implementation for FromString Nat"
  %runElab run (infer `(the Nat "s"))

-- inside `try`, a failure leaves no trace
tryInfer : Elab ()
tryInfer = do
  r <- catch (infer `(Prelude.Nil))
  logMsg "" 0 "caught: \{show (isJust r)}"

%runElab tryInfer
