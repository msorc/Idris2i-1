||| Specialising by static arguments that the partial evaluator cannot
||| reduce to a normal form in a bounded number of steps: a call of a function
||| that does not terminate, a copy whose body does not terminate (at compile
||| time: the program never runs that path), a recursive call that makes a
||| copy by a bigger argument each time, an infinite structure, and a term
||| that is total but huge.  They overflowed the stack of the compiler, or took very long; now
||| the function is called instead, and the arguments that do reduce still
||| make copies.
module Main

import Data.IORef
import Data.List
import Data.Stream

loop : Nat -> Nat
loop n = loop (n + 1)

loopF : Nat -> Nat
loopF n = loopF (S n)

-- A call of a function that does not terminate, as a static argument.
%spec x
lazyArg : (x : Lazy Nat) -> Nat -> Nat
lazyArg x y = if y == 0 then 0 else x + y

-- A function that does not terminate on any argument, as a static argument:
-- the body of the copy does not terminate.
%spec g
applyTo : (g : Nat -> Nat) -> Nat -> Nat
applyTo g y = if y == 0 then 0 else g y

-- A function that does not terminate on its static argument (unless the
-- dynamic one is 0).
%spec x
count : (x : Nat) -> Nat -> Nat
count x y = if y == 0 then x else count (S x) y

-- A function that is total, but makes a copy by a different argument where
-- it calls itself (a variable is matched), and so on.
%spec x
acc : (x : Nat) -> Nat -> Nat
acc x Z = x
acc x (S y) = acc (S x) y

-- Total, but too big to normalise at compile time.
%spec x
plusLen : (x : Nat) -> Nat -> Nat
plusLen x y = x + y

-- An infinite structure, which the copy is reduced under the delays of, and
-- whose elements are ever bigger normal forms.
%spec f
nth : (f : Nat -> Nat) -> Nat -> Nat
nth f n = Stream.index n (iterate f 0)

-- Arguments that do reduce: copies are made.
%spec x
twice : (x : Nat) -> Nat -> Nat
twice x y = x + x + y

main : IO ()
main = do
  r <- newIORef 0
  n <- readIORef r
  printLn (lazyArg (loop 0) n)
  printLn (applyTo loopF n)
  printLn (count 3 n)
  printLn (acc 3 (n + 5))
  printLn (plusLen (length (replicate 300000 ())) n)
  printLn (nth S (n + 5))
  printLn (twice 4 n)
  printLn (applyTo S (S n))
