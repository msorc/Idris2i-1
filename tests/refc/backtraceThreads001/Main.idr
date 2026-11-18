module Main

import System

-- A recursion without end, which overflows the stack, and a crash, on the
-- main thread and on a forked one.

%noinline
depth : Int -> Int
depth n = 1 + depth (n + 1)

%noinline partial
checked : Int -> Int
checked n = if n > 100 then idris_crash "too big" else n

%noinline partial
work : String -> Int
work "overflow" = 1 + depth 0
work "crash" = 1 + checked 1000
work _ = 0

partial
main : IO ()
main = do
  [_, what, wher] <- getArgs
    | _ => putStrLn "what and where?"
  case wher of
    "thread" => do t <- fork (do pure (); printLn (work what))
                   threadWait t
    _ => printLn (work what)
