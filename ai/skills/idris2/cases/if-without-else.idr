-- expect: E1101
f : Bool -> IO ()
f b = if b then putStrLn "yes"
