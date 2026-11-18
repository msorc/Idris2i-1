-- With the C__scoped_callbacks convention, the code made for a callback is
-- only kept during the call: calling a function that takes a callback many
-- times does not keep memory, as it does with the C convention.

%foreign "C__scoped_callbacks:sumWith,libscoped"
         "C:sumWith,libscoped"
prim__sumScoped : (Int -> Int) -> Int -> PrimIO Int

%foreign "C:sumWith,libscoped"
prim__sumKept : (Int -> Int) -> Int -> PrimIO Int

%foreign "scheme:(lambda () (begin (collect (collect-maximum-generation)) (bytes-allocated)))"
prim__usedAfterCollect : PrimIO Int

%foreign "scheme:(lambda (x) (begin (collect (collect-maximum-generation)) x))"
prim__collectThen : Int -> PrimIO Int

-- A full collection in the callback: its code must still be there when C
-- calls it again
collecting : Int -> Int
collecting x = unsafePerformIO $ primIO (prim__collectThen (x * 2))

loop : ((Int -> Int) -> Int -> PrimIO Int) -> Int -> Int -> IO Int
loop f 0 acc = pure acc
loop f n acc = do r <- primIO (f (\x => x + n) 3); loop f (n - 1) (acc + r)

kept : ((Int -> Int) -> Int -> PrimIO Int) -> IO Int
kept f = do
  before <- primIO prim__usedAfterCollect
  _ <- loop f 20000 0
  after <- primIO prim__usedAfterCollect
  pure (after - before)

main : IO ()
main = do
  r <- primIO (prim__sumScoped collecting 5)
  putStrLn "sum with collections in the callback: \{show r}"
  s <- loop prim__sumScoped 10 0
  putStrLn "sum of 10 calls: \{show s}"
  scoped <- kept prim__sumScoped
  putStrLn "scoped callbacks keep less than 100KB: \{show (scoped < 100000)}"
  plain <- kept prim__sumKept
  putStrLn "C callbacks keep more than 1MB: \{show (plain > 1000000)}"
