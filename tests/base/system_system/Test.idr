import System
import System.File
import System.Info

-- `system` returns the exit status of the command as a shell reports it.
expect : String -> Int -> String -> IO ()
expect what code cmd = do
  r <- system cmd
  if r == code
     then do putStrLn "\{what}: \{show r}"
             -- before the output of the next command
             ignore $ fflush stdout
     else do putStrLn "\{what}: expecting \{show code}, got \{show r}"
             exitFailure

main : IO ()
main = do
  expect "zero" 0 "bash zero.sh"
  expect "seventeen" 17 "bash seventeen.sh"
  expect "exit 3" 3 "exit 3"
  if not isWindows
     then do -- not found by the shell
             expect "not found" 127 "./no-such-command 2>/dev/null"
             -- killed by a signal: 128 + the number of the signal
             expect "SIGTERM" 143 "kill -TERM $$"
             expect "SIGKILL" 137 "kill -KILL $$"
     else do putStrLn "not found: 127"
             putStrLn "SIGTERM: 143" -- no signals on Windows
             putStrLn "SIGKILL: 137"
             ignore $ fflush stdout

  let nastyStr = "Hello \"world\" $PATH %PATH% \\\" `echo 'Uh, oh'`"
  ignore $ system $ "echo " ++ escapeArg nastyStr
  ignore $ system ["echo", nastyStr]

  if not isWindows
     then do ignore $ system $ "echo " ++ escapeArg "Hello\nworld"
             ignore $ system ["echo", "Hello\nworld"]
     else do putStrLn "Hello\nworld\nHello\nworld" -- Windows has no way of escaping '\n', so skip test
