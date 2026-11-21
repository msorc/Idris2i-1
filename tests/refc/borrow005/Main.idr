module Main

-- The raw fields of a borrowed value (an Int, a Double) are read into C
-- numbers, which the function owns: passing one back in a call to itself
-- in tail position makes the parameter owned, so the call stays a tail
-- call (and a worker that gives a C number gets one).

data P = MkP Int P | End

goI : Int -> P -> Int
goI k End = 0
goI k (MkP x rest) = if x > 100 then 1 else goI x rest

goD : Double -> P -> Double
goD k End = 0.5
goD k (MkP x rest) = if x > 100 then 1.5 else goD (cast x) rest

record R where
  constructor MkR
  d : Double
  n : Int

loop : Double -> R -> Int -> String
loop acc r 0 = "done"
loop acc r k = case r of MkR d _ => loop d r (k - 1)

loopI : Double -> R -> Int -> Int
loopI acc r 0 = 7
loopI acc r k = case r of MkR d _ => loopI d r (k - 1)

main : IO ()
main = do
  printLn (goI 0 (MkP 1 (MkP 2 (MkP 3 End))))
  printLn (goI 0 (MkP 1 (MkP 200 End)))
  printLn (goD 0 (MkP 1 (MkP 2 End)))
  printLn (goD 0 (MkP 1 (MkP 200 End)))
  printLn (loop 0 (MkR 1.5 2) 1000000)
  printLn (loopI 0 (MkR 1.5 2) 1000000)
