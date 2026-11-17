module Deep

-- After inlining, `deep` is a chain of 512 binds, each in the continuation of
-- the one before.  The inliner closed every binder it made over its scope
-- with a pass over the scope, and evaluates the code of a continuation again
-- where `io_bind` applies it: 512 binds took a minute, 1,024 seven minutes.

step : Int -> Int -> IO Int
step x y = pure (x * 3 + y)

%inline
f0 : Int -> (Int -> IO Int) -> IO Int
f0 x k = do x <- step x x
            if x == 0 then pure 0 else k x

%inline
f1 : Int -> (Int -> IO Int) -> IO Int
f1 x k = f0 x (\x => f0 x k)

%inline
f2 : Int -> (Int -> IO Int) -> IO Int
f2 x k = f1 x (\x => f1 x k)

%inline
f3 : Int -> (Int -> IO Int) -> IO Int
f3 x k = f2 x (\x => f2 x k)

%inline
f4 : Int -> (Int -> IO Int) -> IO Int
f4 x k = f3 x (\x => f3 x k)

%inline
f5 : Int -> (Int -> IO Int) -> IO Int
f5 x k = f4 x (\x => f4 x k)

%inline
f6 : Int -> (Int -> IO Int) -> IO Int
f6 x k = f5 x (\x => f5 x k)

%inline
f7 : Int -> (Int -> IO Int) -> IO Int
f7 x k = f6 x (\x => f6 x k)

%inline
f8 : Int -> (Int -> IO Int) -> IO Int
f8 x k = f7 x (\x => f7 x k)

%inline
f9 : Int -> (Int -> IO Int) -> IO Int
f9 x k = f8 x (\x => f8 x k)

deep : Int -> IO Int
deep x = f9 x pure

main : IO ()
main = deep 1 >>= printLn
