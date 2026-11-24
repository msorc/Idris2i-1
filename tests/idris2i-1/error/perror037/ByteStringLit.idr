import Data.ByteString

f : ByteString -> IO ()
f "abc" = putStrLn "abc"
f _ = putStrLn "other"
