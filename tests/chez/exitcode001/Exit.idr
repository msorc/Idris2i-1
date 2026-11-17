module Exit

import System

ok : IO ()
ok = putStrLn "ok"

three : IO ()
three = do putStrLn "exiting with 3"
           exitWith (ExitFailure 3)

failure : IO ()
failure = exitFailure

partial
crash : IO ()
crash = idris_crash "crashing"

-- The shell that `system` starts sends SIGTERM (15) to the program, its
-- parent
terminated : IO ()
terminated = do ignore $ system "kill -TERM $PPID"
                putStrLn "still running"
