module Typos

import Data.List
import Data.Vect
import Data.String
import Data.SortedMap
import Control.Monad.State

record Point where
  constructor MkPoint
  xCoord : Nat
  yCoord : Nat

privateThing : Nat
privateThing = 3

myFunction : Nat -> Nat
myFunction = S

g01 : List Nat -> Nat
g01 xs = lenght xs
g02 : List Nat -> List Nat
g02 = mapp S
g03 : String -> List String
g03 = wrods
g04 : SortedMap String Nat -> List String
g04 m = keyss m
g05 : Nat -> State Nat ()
g05 n = modfy (+ n)
g06 : Nat
g06 = privateThin
g07 : Nat -> Nat
g07 = myFuncton
g08 : Point -> Nat
g08 p = p.xCord
g09 : Point -> Nat
g09 p = yCord p
g10 : List Nat -> List Nat
g10 xs = xs <+ xs
g11 : Maybe Nat -> (Nat -> Maybe Nat) -> Maybe Nat
g11 m f = m >>== f
g12 : Nat
g12 = foldl (+) 0 [1,2]
g13 : List Nat -> Nat
g13 = sum'
g14 : Vect 2 Nat
g14 = replicat 2 0
g15 : Nat -> Nat
g15 = id'
g16 : String -> Nat
g16 = lengt
g17 : Nat
g17 = fold (+) 0 [1]
g18 : List a -> List a
g18 = revers
g19 : Bool
g19 = Tru
g20 : List Nat
g20 = Nill
g22 : String -> String
g22 = trimm
g23 : Nat
g23 = λx
g24 : Nat -> Nat
g24 = pred'
g25 : Maybe Nat
g25 = Jus 1
g26 : List Nat -> Maybe Nat
g26 = hed'
g27 : List Nat -> List Nat
g27 = sortt
g28 : String -> List Char
g28 = unpak
g29 : Nat
g29 = x
g30 : Nat -> Nat -> Nat
g30 = plsu

myFuncton x = x
