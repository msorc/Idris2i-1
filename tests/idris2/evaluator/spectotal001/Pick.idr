||| `pick` is `export`, not `public export`: it cannot be reduced in another
||| module.
module Pick

%default total

public export
data T = P | Q | R

%spec x
export
pick : (x : T) -> Int -> Int
pick P n = n + 1
pick Q n = n + 2
pick R n = n + 3

%spec f
export
twice : (f : Int -> Int) -> Int -> Int
twice f n = f (f n)
