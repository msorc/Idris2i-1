-- Crash boundaries (System.Crash) on the Scheme and JavaScript backends: a
-- crash call, a missing case and an error that the runtime raises are
-- caught, boundaries nest, a crash in a function given to a library
-- function is caught, and the program goes on.  With an argument: `exit`
-- inside a boundary exits, and a crash without a boundary exits as before.
module Main

import Data.IORef
import Data.List
import System
import System.Crash

%default partial

f : Int -> Int
f 0 = 1

report : String -> Either CrashInfo String -> IO ()
report what (Right x) = putStrLn (what ++ ": returned " ++ x)
report what (Left c) = putStrLn (what ++ ": " ++ show c.kind ++ ": " ++ c.message)

-- (the message of an error of the runtime depends on the backend)
kindOnly : String -> Either CrashInfo String -> IO ()
kindOnly what (Right x) = putStrLn (what ++ ": returned " ++ x)
kindOnly what (Left c) = putStrLn (what ++ ": " ++ show c.kind)

main : IO ()
main = do
  args <- getArgs
  let n = cast (length args) - 1
  case drop 1 args of
    [] => do
      report "pure" !(catchCrash (pure "fine"))
      report "idris_crash" !(catchCrash (pure (assert_total (idris_crash "boom"))))
      report "missing case" !(catchCrash (pure (show (f (n + 1)))))
      kindOnly "Integer division" !(catchCrash (pure (show (prim__div_Integer 7 (cast n)))))
      r <- catchCrash $ do
        inner <- catchCrash (pure (show (f (n + 2))))
        report "inner" inner
        pure (assert_total (idris_crash "outer"))
      report "outer" r
      report "sortBy" !(catchCrash (pure (show (sortBy (\x, y => compare (f x) (f y)) [n, n + 3]))))
      ref <- newIORef (the Int 0)
      report "traverse_" !(catchCrash (do traverse_ (\x => modifyIORef ref (+ f x)) [n, n, n + 7]
                                          pure "done"))
      putStrLn ("ref: " ++ show !(readIORef ref))
      putStrLn ("crashes caught: " ++ show !crashesCaught)
      putStrLn ("boundaries: " ++ show crashBoundaries)
    ["exit"] => do
      _ <- catchCrash {a = ()} (do putStrLn "exiting"; exitWith (ExitFailure 3))
      putStrLn "not reached"
    ["none"] => do
      _ <- catchCrash (pure "fine")
      putStrLn (show (f (n + 1)))
    _ => putStrLn "?"
