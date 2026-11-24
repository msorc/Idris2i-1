||| A copy does not hide what its static arguments call from the totality
||| checker: the functions that are checked call the function that is copied,
||| and refer to the static arguments, not to the copy.
module Partial

import Loop

%default total

%spec f
apply : (f : Int -> Int) -> Int -> Int
apply f n = f n

loops : Int -> Int
loops n = apply loop n

misses : Int -> Int
misses n = apply half n

-- the copy of `apply` by `next` is used here
next : Int -> Int
next n = n + 1

fine : Int -> Int
fine n = apply next n
