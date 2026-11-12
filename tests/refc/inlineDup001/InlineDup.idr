module InlineDup

import System

-- `div` and `mod` on `Int` are small enough to be inlined, and their body
-- uses the divisor twice (to check for 0, then to divide).  The divisor is
-- computed once all the same, as when they are called.

%noinline
noisy : String -> Int -> Int
noisy s x = unsafePerformIO $ do putStrLn s; pure x

-- (`n` is only known at run time, so that nothing is computed at compile
-- time or shared as a constant)
%noinline
test : Int -> IO ()
test n = do
  printLn (100 `div` noisy "div" (n + 6))
  printLn (100 `mod` noisy "mod" (n + 6))
  printLn (1000 `div` (100 `div` noisy "nested" (n + 6)))

main : IO ()
main = test (cast (length !getArgs))
