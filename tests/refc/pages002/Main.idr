-- Like pages001, but in two threads that run on different workers: the
-- empty pages of one go to the pool of the workers, where the other takes
-- them.
import Data.IORef
import System
import System.Concurrency

data Small = SEnd | SLink Int Small

-- 7 fields: 64 bytes, where SLink takes 24
data Big = BEnd | BLink Int Int Int Int Int Int Big

mkSmall : Small -> Int -> Small
mkSmall acc 0 = acc
mkSmall acc n = mkSmall (SLink n acc) (n - 1)

sumSmall : Int -> Small -> Int
sumSmall acc SEnd = acc
sumSmall acc (SLink x r) = sumSmall (acc + x) r

mkBig : Big -> Int -> Big
mkBig acc 0 = acc
mkBig acc n = mkBig (BLink n n n n n n acc) (n - 1)

sumBig : Int -> Big -> Int
sumBig acc BEnd = acc
sumBig acc (BLink x _ _ _ _ _ r) = sumBig (acc + x) r

waitFor : IORef Bool -> IO ()
waitFor flag = do
  b <- readIORef flag
  if b then pure () else do usleep 10000; waitFor flag

main : IO ()
main = do
  ready <- newIORef False
  done <- newIORef False
  -- The second thread starts at once, and sleeps until the first one is
  -- done: the timers wake it up on whichever worker looks.
  t2 <- fork $ do
    waitFor ready
    printLn (sumBig 0 (mkBig BEnd 750000))
    writeIORef done True
  t1 <- fork $ do
    pure ()
    printLn (sumSmall 0 (mkSmall SEnd 2000000))
    writeIORef ready True
    -- (and this worker goes idle)
    waitFor done
  threadWait t1
  threadWait t2
