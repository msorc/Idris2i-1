-- After inlining, `deep` is 128 binds nested in each other, each in a
-- branch of an `if`: 128 `let`s of the same name, nested 128 blocks deep
-- in C.  (Forgetting the names of such code took time cubic in the depth,
-- and the C of it had lines indented by 4 spaces per level.)
module Main

step : Int -> IO Int
step x = pure (x * 3 + 1)

%inline
f0 : Int -> (Int -> IO Int) -> IO Int
f0 x k = do x <- step x
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

deep : Int -> IO Int
deep x = f7 x pure

main : IO ()
main = deep 1 >>= printLn
