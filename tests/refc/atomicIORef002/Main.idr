module Main

import Data.IORef
import Data.String
import System
import System.Concurrency

-- Atomic updates of IORefs that hold allocated values (lists of strings,
-- records), from threads on two workers, under Valgrind: the values that are
-- replaced, and the ones that a failed swap built, must be freed once, and
-- the tickets must keep the values that they stand for alive.
record Stats where
  constructor MkStats
  count : Integer
  names : List String

worker : IORef Stats -> IORef (List String) -> Int -> Int -> IO ()
worker stats log i m = go m
  where
    go : Int -> IO ()
    go 0 = pure ()
    go k = do
        let name = "t\{show i}-\{show k}"
        t <- readForCAS stats
        atomicModifyIORef_ stats
          (\s => MkStats (s.count + 1) (take 3 (name :: s.names)))
        atomicModifyIORef_ log (name ::)
        -- a swap that fails: the ticket is stale, as the update above wrote
        -- a new record
        ignore $ casIORef stats t (MkStats 0 ("never" :: (peekTicket t).names))
        go (k - 1)

main : IO ()
main = do
    let n = 4
    let m = 300
    stats <- newIORef (MkStats 0 [])
    log <- newIORef []
    tids <- for [0 .. n - 1] $ \i => fork (worker stats log i m)
    for_ tids (\t => threadWait t)
    s <- readIORef stats
    xs <- readIORef log
    printLn s.count
    printLn (length s.names)
    printLn (length xs)
    printLn (length (filter (== "never") s.names))
