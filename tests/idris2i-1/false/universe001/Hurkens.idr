||| Hurkens' paradox: with Type : Type there is a closed term of type Void.
module Hurkens

%default total

Bot : Type
Bot = (a : Type) -> a

NotT : Type -> Type
NotT a = a -> Bot

P : Type -> Type
P a = a -> Type

U : Type
U = (x : Type) -> (P (P x) -> x) -> P (P x)

tau : P (P U) -> U
tau t = \x, f, p => t (\s => p (f (s x f)))

sigma : U -> P (P U)
sigma s = s U (\t => tau t)

Delta : P U
Delta y = NotT ((p : P U) -> sigma y p -> p (tau (sigma y)))

Omega : U
Omega = tau (\p => (x : U) -> sigma x p -> p x)

D : Type
D = (p : P U) -> sigma Omega p -> p (tau (sigma Omega))

lem1 : (p : P U) -> ((x : U) -> sigma x p -> p x) -> p Omega
lem1 p h1 = h1 Omega (\x => h1 (tau (sigma x)))

lem2 : NotT D
lem2 = lem1 Delta step
  where
    step : (x : U) -> sigma x Delta -> Delta x
    step x h2 h3 = h3 Delta h2 (\p => h3 (\y => p (tau (sigma y))))

lem3 : D
lem3 p = lem1 (\y => p (tau (sigma y)))

export
false : Void
false = lem2 lem3 Void
