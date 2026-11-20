||| `believe_me` and raw fields: a record coerced to a type that stands for
||| any value and back is fine; matched as a constructor of another type with
||| another layout, it is undefined behaviour, which
||| `--directive refc-check-layout` catches.
module Main

record P where
  constructor MkP
  x : Double
  y : Double

data B = MkB String String

-- a record kept as AnyPtr (as in a foreign library's callback data) and
-- taken back
roundTrip : P -> P
roundTrip p = believe_me (the AnyPtr (believe_me p))

wrong : P -> String
wrong p = case the B (believe_me p) of
               MkB s _ => s

main : IO ()
main = do
  let p = roundTrip (MkP 1.5 2.5)
  printLn (p.x + p.y)
  putStrLn (wrong (MkP 1.5 2.5))
