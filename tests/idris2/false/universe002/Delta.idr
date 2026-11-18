||| Coquand's Delta (upstream #3907): the field quantifies over all types,
||| including Delta itself
module Delta

%default total
data Delta = MkDelta ((a : _) -> a -> a)
absurd : Delta -> Void
absurd (MkDelta f) = absurd $ f _ (MkDelta f)
oops : Void
oops = absurd $ MkDelta (\_, x => x)
