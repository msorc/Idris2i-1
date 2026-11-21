-- The memory statistics at exit while other threads still allocate and
-- free values: they stop first, so that the report does not look at pages
-- that change under it.
import System
import System.Concurrency

allocate : Nat -> IO ()
allocate k = do
    let xs : List Int = map (+ cast k) [1 .. 2000]
    if sum xs == 0 then putStrLn "zero" else pure ()
    allocate (S k)

main : IO ()
main = do
    for_ [1 .. 7] $ \_ => fork (allocate 0)
    usleep 50000
    putStrLn "main ends"
