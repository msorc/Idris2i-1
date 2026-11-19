module Stream

-- Foreign code that reads `process.stdin` as a stream gets the input when
-- `main` runs in its worker thread, as on the main thread.

%foreign "node:lambda:(cb, w) => { let s = ''; process.stdin.setEncoding('utf8'); process.stdin.on('data', d => { s += d }); process.stdin.on('end', () => cb(s)(w)) }"
prim__readStdin : (String -> PrimIO ()) -> PrimIO ()

main : IO ()
main = do
  putStrLn "start"
  primIO $ prim__readStdin (\s => toPrim (putStr ("read: " ++ s)))
  putStrLn "main returned"
