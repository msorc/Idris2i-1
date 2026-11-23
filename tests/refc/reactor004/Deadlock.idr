-- Every thread is blocked forever: the program reports a deadlock, as
-- nothing waits for a file descriptor.
import System.Concurrency

main : IO ()
main = do
  c <- makeChannel {a = Int}
  t <- fork $ do
    putStrLn "the thread waits for a value that never comes"
    ignore $ channelGet c
  threadWait t
