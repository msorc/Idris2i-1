import Data.Buffer

-- A String or Buffer argument of a C function must stay where it is while
-- the function calls back into Idris, even if the collector runs then.

%foreign "C:checkString,libpin"
prim__checkString : String -> PrimIO () -> PrimIO Int

%foreign "C:checkBuffer,libpin"
prim__checkBuffer : Buffer -> Int -> PrimIO () -> PrimIO Int

%foreign "scheme:(lambda () (collect (collect-maximum-generation)))"
prim__collect : PrimIO ()

-- Allocate, then collect everything
churn : IO ()
churn = do
  let s = fastConcat (map show [1 .. the Integer 20000])
  primIO prim__collect
  when (length s == 0) $ putStrLn "empty"

main : IO ()
main = do
  for_ [16, 1024, 65536] $ \n => do
    let s = pack (map (\i => chr (97 + i `mod` 26)) [1 .. n])
    r <- primIO $ prim__checkString s (toPrim churn)
    putStrLn "String of \{show n} bytes: \{if r == 1 then "intact" else "moved"}"
  for_ [16, 1024, 65536] $ \n => do
    Just b <- newBuffer n
      | Nothing => putStrLn "no buffer"
    for_ [0 .. n - 1] $ \i => setBits8 b i (cast (i `mod` 251))
    r <- primIO $ prim__checkBuffer b n (toPrim churn)
    putStrLn "Buffer of \{show n} bytes: \{if r == 1 then "intact" else "moved"}"
