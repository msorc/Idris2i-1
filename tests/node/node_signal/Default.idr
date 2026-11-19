module Default

import System
import System.Signal

-- After defaultSignal, a raised signal has its default effect.
main : IO ()
main = do
  Right () <- ignoreSignal SigABRT
    | Left (Error code) => putStrLn $ "error " ++ show code
  Right () <- defaultSignal SigABRT
    | Left (Error code) => putStrLn $ "error " ++ show code
  putStrLn "raising"
  Right () <- raiseSignal SigABRT
    | Left (Error code) => putStrLn $ "error " ++ show code
  sleep 1
  putStrLn "(should not get here)"
