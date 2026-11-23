||| The syntax of a small typed language, and values that the checker compares.
module Syntax

import Data.Fin
import Data.Nat
import Decidable.Equality

%default total

||| Types of the object language.
public export
data Ty = TInt | TBool | TFun Ty Ty | TList Ty | TPair Ty Ty

||| Binary operators.
public export
data Op = Add | Sub | Mul | Lt | Same | And | Or

||| Well-scoped terms: `Term n` has at most `n` free variables.
public export
data Term : Nat -> Type where
  Var   : Fin n -> Term n
  Num   : Integer -> Term n
  Truth : Bool -> Term n
  Lam   : Ty -> Term (S n) -> Term n
  App   : Term n -> Term n -> Term n
  Bin   : Op -> Term n -> Term n -> Term n
  If    : Term n -> Term n -> Term n -> Term n
  Let   : Term n -> Term (S n) -> Term n
  Empty : Ty -> Term n
  Cons  : Term n -> Term n -> Term n

||| A module tree: an operator-labelled node with any number of children.
public export
data Rose = MkRose Op (List Rose)

||| A positive number; the proof is erased at run time.
public export
data Pos : Type where
  MkPos : (n : Nat) -> (0 ok : IsSucc n) -> Pos

-- TODO: DecEq Ty, DecEq Op, DecEq (Term n), DecEq Rose, DecEq Pos
