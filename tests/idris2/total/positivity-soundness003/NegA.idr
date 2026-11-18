module NegA

public export
data NegT a = MkNegT (a -> Void)
