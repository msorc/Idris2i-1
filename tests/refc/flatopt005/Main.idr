||| An element of a flat array read by its fields (Compiler.RefC.FlatOpt) is
||| read once, so that its fields are those of one write when another thread
||| writes it: where it is read in a branch of a value that is split in turn
||| (`pick`, and `two` with two elements), and where it is used as a value
||| too (`both`).
module Main

import Data.IOArray

record P where
  constructor MkP
  x : Double
  y : Double

-- (the record read in a branch, split into its fields)
%noinline
pick : Bool -> IOArray P -> Int -> IO Double
pick b a i = do
  q <- if b then do m <- readFlatArray a i
                    case m of
                      Just p => pure p
                      Nothing => pure (MkP 0 0)
            else pure (MkP 5 6)
  pure (q.x + q.y)

-- (two elements read in a branch, each once)
%noinline
two : Bool -> IOArray P -> Int -> Int -> IO Double
two b a i j = do
  q <- if b then do Just p <- readFlatArray a i | Nothing => pure (MkP 0 0)
                    Just r <- readFlatArray a j | Nothing => pure p
                    pure (MkP (p.x + r.x) (p.y * r.y))
            else pure (MkP 7 8)
  pure (q.x * 10 + q.y)

-- (read by its fields and used as a value)
%noinline
both : IOArray P -> Int -> IO (Double, Maybe P)
both a i = do
  m <- readFlatArray a i
  case m of
    Just p => pure (p.x, m)
    Nothing => pure (0, m)

showP : Maybe P -> String
showP Nothing = "-"
showP (Just p) = "P \{show p.x} \{show p.y}"

main : IO ()
main = do
  ps <- newFlatArray {elem = P} 3
  ignore (writeFlatArray ps 1 (MkP 1.0 2.0))
  ignore (writeFlatArray ps 2 (MkP 3.0 4.0))
  printLn [!(pick True ps 1), !(pick False ps 1), !(pick True ps 0), !(pick True ps 5)]
  printLn [!(two True ps 1 2), !(two True ps 1 0), !(two True ps 0 2), !(two False ps 1 2)]
  for_ [0, 1, 5] $ \i => do
    (d, m) <- both ps i
    putStrLn "\{show d} \{showP m}"
