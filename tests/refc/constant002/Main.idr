-- A constant that needs itself while it is evaluated (here once, thanks to a
-- counter): the inner evaluation gives an ordinary value, which is freed
-- once used, rather than an immortal copy.
import Data.IORef

counter : IORef Int
counter = unsafePerformIO (newIORef 0)

weird : List Int
weird = unsafePerformIO $ do
  n <- readIORef counter
  writeIORef counter (n + 1)
  pure (if n == 0 then [cast (length weird)] else [1, 2, 3])

main : IO ()
main = do
  printLn weird
  printLn weird
