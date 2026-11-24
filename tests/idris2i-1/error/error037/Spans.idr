-- Errors whose location spans several lines: the excerpt marks where the
-- span starts and ends, and leaves out the middle of a long one

short : Nat ->
        Bool
short Z = True

long : Nat ->
       Nat ->
       Nat ->
       Nat ->
       Nat ->
       Nat ->
       Nat ->
       Bool
long Z Z Z Z Z Z Z = True

wrong : Nat -> String
wrong n = the Nat (case n of
                        Z => 0
                        S k => 1) ++ "x"
