-- Two case blocks of a %spec function, nested in the same block, with the
-- same static arguments: their copies must not be taken for each other
%spec f
g : (f : Int -> Int) -> Int -> Int -> Int
g f x y = if x > 0
             then case y of
                       0 => f 1
                       _ => f 2
             else case y of
                       0 => f 3
                       _ => f 4

main : IO ()
main = printLn [g (+ 10) 1 0, g (+ 10) 1 5, g (+ 10) 0 0, g (+ 10) 0 5]
