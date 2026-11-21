module Main

import Language.Reflection

%language ElabReflection

-- A literal -0.0 (the elaborator makes one) is not the constant 0.0.

negZero : Double
negZero = %runElab check (IPrimVal EmptyFC (Db (negate 0.0)))

posZero : Double
posZero = 0.0

main : IO ()
main = do
  printLn (1.0 / posZero)
  printLn (1.0 / negZero)
  printLn (1.0 / negZero)
  printLn (1.0 / posZero)
