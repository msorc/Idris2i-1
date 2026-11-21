module Main

-- An exported function is called from JavaScript by the arity of its type:
-- `loop` takes two arguments and gives an action (a function of the world),
-- as it did before the functions in IO were given the world as a parameter
-- (see Compiler.Opts.EtaIO), which it is not.  `loop2`, which is not
-- exported, is.

%export "javascript:loop"
loop : Int -> Int -> IO Int
loop acc n = if n == 0 then pure acc else loop (acc + n) (n - 1)

loop2 : Int -> Int -> IO Int
loop2 acc n = if n == 0 then pure acc else loop2 (acc + n) (n - 1)

main : IO ()
main = printLn !(loop 0 10) >> printLn !(loop2 0 10)
