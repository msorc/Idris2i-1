module B

-- The same functions as in A, in other units of a split program

-- Only made into closures, without and with arguments
export
wrapB : Int -> Either String Int
wrapB x = if x > 100 then Left "big" else Right (x * 3 + 1)

export
stepB : Nat -> Int -> Int
stepB Z x = x
stepB (S k) x = stepB k (x * 2 + 1)

-- Called by name, and made into a closure: it stays in its unit
export
bothB : Nat -> Int -> Int
bothB Z x = x
bothB (S k) x = bothB k (x + 7)

export
wrapsB : List (Int -> Either String Int)
wrapsB = [wrapB]

export
stepsB : List (Int -> Int)
stepsB = [stepB 3, bothB 1]

export
runB : Int -> Int
runB x = bothB 2 x
