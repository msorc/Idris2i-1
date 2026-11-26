module A

-- The same functions as in B, in other units of a split program

-- Only made into closures, without and with arguments
export
wrapA : Int -> Either String Int
wrapA x = if x > 100 then Left "big" else Right (x * 3 + 1)

export
stepA : Nat -> Int -> Int
stepA Z x = x
stepA (S k) x = stepA k (x * 2 + 1)

-- Called by name, and made into a closure: it stays in its unit
export
bothA : Nat -> Int -> Int
bothA Z x = x
bothA (S k) x = bothA k (x + 7)

export
wrapsA : List (Int -> Either String Int)
wrapsA = [wrapA]

export
stepsA : List (Int -> Int)
stepsA = [stepA 3, bothA 1]

export
runA : Int -> Int
runA x = bothA 2 x
