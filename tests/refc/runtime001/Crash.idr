module Crash

-- The message goes to stdout, and the exit code is 1 (blodwen-error-quit)
partial
main : IO ()
main = idris_crash "the message"
