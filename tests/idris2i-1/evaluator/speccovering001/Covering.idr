||| A specialised copy runs the code of the implementations it is given, and
||| so calls what they call: here `prim__mod_Int`, which is not covering, from
||| `mod` of `Integral Int`, where `bucket` only calls the method `hash`.  The
||| copies must not be checked against the default totality of this module.
||| (It is `covering`: a total function could not use `mod` of `Integral Int`
||| through `Hash Few`.)
module Covering

%default covering

interface Hash a where
  hash : a -> Int

record Few where
  constructor MkFew
  n : Int

Hash Few where
  hash x = x.n `mod` 7

Hash Int where
  hash x = x

-- explicitly specialised
%spec h
bucket : {auto h : Hash a} -> a -> List a -> Int
bucket x [] = hash x
bucket x (y :: ys) = hash x + bucket y ys

-- specialised by --spec-interfaces
twice : Hash a => a -> Int
twice x = hash x + hash x

fewBucket : List Few -> Int
fewBucket [] = 0
fewBucket (x :: xs) = bucket x xs

fewTwice : Few -> Int
fewTwice x = twice x

main : IO ()
main = do
  printLn (fewBucket [MkFew 10, MkFew 20, MkFew 30])
  printLn (fewTwice (MkFew 40))
  printLn (bucket (the Int 1) [2, 3])
