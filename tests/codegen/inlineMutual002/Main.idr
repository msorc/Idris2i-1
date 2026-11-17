module Main

-- A recursive function specialised by `%spec` (like `nextDirEntry` of
-- System.Directory): the copies of its case blocks, which are inlinable,
-- call each other, as the copy of the second one has the call of
-- `countDown` reduced to the first one.  Each was inlined into its own body
-- through the other, in every round of transformations, and the copies of
-- the whole function got the recursion unrolled 133 times.

%spec hio
countDown : {auto hio : HasIO io} -> Int -> io Int
countDown n = do x <- pure n
                 if x <= 0 then pure 0
                    else if x == 5 then pure 5 else countDown (x - 1)

main : IO ()
main = countDown 10 >>= printLn
