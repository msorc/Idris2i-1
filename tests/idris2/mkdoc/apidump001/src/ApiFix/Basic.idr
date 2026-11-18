||| Functions, quantities, totality and fixities
module ApiFix.Basic

import Data.Nat

%default total

export infixl 6 <+>
public export infixr 5 :::
private infixl 9 ^^
export typebind infixr 0 =@

||| An exported function: its type is API, its body is not
export
(<+>) : List a -> List a -> List a
(<+>) xs ys = xs ++ ys

||| Public export: the definition is part of the API too
public export
twice : {0 a : Type} -> (a -> a) -> a -> a
twice f x = f (f x)

||| A linear argument, an erased one and an auto implicit
export
consume : (1 x : a) -> {0 n : Nat} -> {auto prf : NonZero n} -> a
consume x = x

export covering
loopy : Nat -> Nat
loopy n = loopy n

export partial
headOf : List a -> a
headOf (x :: _) = x

%deprecate
export
oldName : Nat
oldName = 0

||| Uses a where block and a case block, neither of which is API
public export
helper : Nat -> Nat
helper n = case n of
             Z => go 1
             S k => go k
  where
    go : Nat -> Nat
    go m = m + 1

private
hidden : Nat
hidden = 3

(^^) : Nat -> Nat -> Nat
(^^) = (+)

export
0 Erased : Type
Erased = Nat

(=@) : (a : Type) -> (a -> Type) -> Type
(=@) a f = (x : a) -> f x

namespace Inner
  export
  inner : Nat
  inner = 1
