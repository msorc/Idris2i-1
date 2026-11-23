-- Crash boundaries (System.Crash): each kind of crash that may be caught is
-- caught, with its kind and message; boundaries nest; a crash in a function
-- given to a library function is caught too; the program goes on after
-- them.  Then, with an argument, what stays fatal inside a boundary, and a
-- crash without a boundary, which exits as it always did.
module Main

import Data.Buffer
import Data.IOArray.Prims
import Data.IORef
import Data.List
import Data.Maybe
import System
import System.Crash

%default partial

-- (a missing case: `f` covers 0 only)
f : Int -> Int
f 0 = 1

report : String -> Either CrashInfo String -> IO ()
report what (Right x) = putStrLn (what ++ ": returned " ++ x)
report what (Left c) = putStrLn (what ++ ": " ++ show c.kind ++ ": " ++ c.message
                                 ++ (if isJust c.backtrace then " (with a backtrace)" else ""))

-- The divisors and indices are made at run time (from the number of
-- arguments), so that the compiler does not fold them.
kinds : Int -> IO ()
kinds n = do
  report "pure" !(catchCrash (pure "fine"))
  report "idris_crash" !(catchCrash (pure (assert_total (idris_crash "boom"))))
  report "missing case" !(catchCrash (pure (show (f (n + 1)))))
  Just buf <- newBuffer 8
    | Nothing => putStrLn "no buffer"
  report "buffer read" !(catchCrash (show <$> getBits32 buf (n + 6)))
  report "buffer write" !(catchCrash (do setBits16 buf (n - 1) 7; pure "written"))
  report "buffer string" !(catchCrash (getString buf 4 (n + 20)))
  report "buffer copy" !(catchCrash (do copyData buf 2 (n + 9) buf 0; pure "copied"))
  report "Integer division" !(catchCrash (pure (show (the Integer 7 `div` cast n))))
  report "Int division" !(catchCrash (pure (show (prim__div_Int 7 n))))
  report "Bits8 modulo" !(catchCrash (pure (show (prim__mod_Bits8 7 (cast n)))))
  report "array length" !(catchCrash (do _ <- primIO (prim__newArray {a = Int} (n - 1) 0)
                                         pure "made"))
  -- the buffer is still there, and works
  setBits32 buf 0 42
  putStrLn ("buffer: " ++ show !(getBits32 buf 0))

nested : Int -> IO ()
nested n = do
  r <- catchCrash $ do
    inner <- catchCrash (pure (show (f (n + 1))))
    report "inner" inner
    putStrLn "between"
    pure (assert_total (idris_crash "outer"))
  report "outer" r
  -- a crash after an inner boundary returned is the outer one's
  r <- catchCrash $ do
    _ <- catchCrash (pure "nothing")
    pure (show (f (n + 2)))
  report "after inner" r

callbacks : Int -> IO ()
callbacks n = do
  report "sortBy" !(catchCrash (pure (show (sortBy (\x, y => compare (f x) (f y)) [n, n + 3, n + 1]))))
  report "foldl" !(catchCrash (pure (show (foldl (\acc, x => acc + f x) 0 [n, n, n + 5]))))
  ref <- newIORef (the Int 0)
  report "traverse_" !(catchCrash (do traverse_ (\x => modifyIORef ref (+ f x)) [n, n, n + 7, n]
                                      pure "done"))
  -- (what was written before the crash stays written)
  putStrLn ("ref: " ++ show !(readIORef ref))
  report "map" !(catchCrash (pure (show (map f [n, n + 1]))))

main : IO ()
main = do
  args <- getArgs
  case drop 1 args of
    [] => do
      -- (0, which the compiler does not know)
      let n = cast (length args) - 1
      kinds n
      nested n
      callbacks n
      putStrLn ("crashes caught: " ++ show !crashesCaught)
      putStrLn ("boundaries: " ++ show crashBoundaries)
    ["exit"] => do
      _ <- catchCrash {a = ()} (do putStrLn "exiting"; exitWith (ExitFailure 3))
      putStrLn "not reached"
    ["none"] => do
      _ <- catchCrash (pure "fine")
      putStrLn (show (f (cast (length args))))
    ["none buffer"] => do
      Just buf <- newBuffer 4
        | Nothing => putStrLn "no buffer"
      putStrLn (show !(getBits32 buf (cast (length args))))
    _ => putStrLn "?"
