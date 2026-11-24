||| Partial functions, which another module cannot reduce (a `%spec` copy by
||| a function that it can reduce reduces it without limit, at compile time).
module Loop

export partial
loop : Int -> Int
loop n = loop (n + 1)

export partial
half : Int -> Int
half 0 = 0
