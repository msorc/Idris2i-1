-- 10,000 crashes caught in a loop: the memory that the crashed code held is
-- leaked (see System.Crash), and nothing else.  The action of the loop
-- holds a string of 1,000 bytes while it calls a function that crashes: a
-- crash leaks the string, and the closure of the action, about 1.1 kB in
-- all, so the resident memory grows by about 11 MB for
-- 10,000 crashes, and not at all when the action does not crash.
module Main

import Data.List
import Data.Maybe
import Data.String
import System
import System.Crash
import System.File

%default partial

-- The resident memory, in kB (0 where /proc is not there).
rss : IO Integer
rss = do
  Right s <- readFile "/proc/self/status"
    | Left _ => pure 0
  case filter (isPrefixOf "VmRSS:") (lines s) of
    (l :: _) => pure (cast (fromMaybe "0" (head' (drop 1 (words l)))))
    [] => pure 0

%noinline
check : Bool -> Int -> Int
check crash i = if crash then assert_total (idris_crash ("request " ++ show i)) else i

-- An action that holds a string while it calls a function that crashes (or
-- not).
act : Bool -> Int -> IO Int
act crash i = do
  let s = pack (replicate 1000 (chr (65 + i `mod` 26)))
  let r = check crash i
  pure (r + cast (length s))

loop : Bool -> Int -> Int -> IO Int
loop crash n caught =
  if n == 0 then pure caught else do
    r <- catchCrash (act crash n)
    loop crash (n - 1) (either (const (caught + 1)) (const caught) r)

main : IO ()
main = do
  -- (the loops are not tail calls in C: the first ones make the stack as
  -- deep as the others will, and the allocator take the pages it needs)
  for_ [1 .. 3] $ \_ => loop False 10000 0
  _ <- loop True 1000 0
  _ <- loop False 10000 0
  -- (reading the memory takes some the first time)
  _ <- rss
  r0 <- rss
  c <- loop False 10000 0
  r1 <- rss
  putStrLn ("without crashes: " ++ show c ++ " caught, growth under 512 kB: " ++ show (r1 - r0 < 512))
  c <- loop True 10000 0
  r2 <- rss
  putStrLn ("with crashes: " ++ show c ++ " caught, growth between 8 and 16 MB: "
            ++ show (r2 - r1 > 8192 && r2 - r1 < 16384))
  args <- getArgs
  when (drop 1 args == ["-v"]) $
    putStrLn ("growth: " ++ show (r1 - r0) ++ " kB without crashes, "
              ++ show (((r2 - r1) * 1024) `div` 10000) ++ " bytes per crash")
  putStrLn ("crashes caught: " ++ show !crashesCaught)
