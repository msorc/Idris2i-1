||| A function specialised by its first argument, in the modules A and B,
||| which do not import each other, and in Main, which imports both.
module Base

public export
data T = P | Q | R

-- (not inlined, nor are its copies, so that they are called)
%spec x
%noinline
public export
pick : (x : T) -> Int -> Int
pick P n = n + 1
pick Q n = n + 2
pick R n = n + 3
