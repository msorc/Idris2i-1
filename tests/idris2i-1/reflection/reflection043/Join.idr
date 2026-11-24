import Language.Reflection

%language ElabReflection
%default total

-- a script computing the script to run
choose : Bool -> Elab (Elab Nat)
choose b = pure (if b then pure 1 else map S (pure 41))

runChosen : Elab ()
runChosen = do
  n <- join (choose True)
  m <- join (choose False)
  logMsg "" 0 "join: \{show n} \{show m}"
  -- the inner script may be a top-level definition, and may fail
  r <- catch (join (pure (the (Elab Nat) (fail "inner"))))
  logMsg "" 0 "caught: \{show r}"

%runElab runChosen

-- the inner script sees the goal of the outer one
goalInside : Nat
goalInside = %runElab join (pure (do Just g <- goal | Nothing => fail "no goal"
                                     logTerm "" 0 "goal" g
                                     check `(7)))
