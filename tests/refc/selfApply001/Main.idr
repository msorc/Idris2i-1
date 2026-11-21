module Main
import System

-- A closure applied to itself (`Rec` is erased, so `f (MkRec f)` is `f f`)
-- consumes two references to it, also when the application is made with
-- another argument at once or in tail position.

data Rec = MkRec (Rec -> Nat)
data Rec2 = MkRec2 (Rec2 -> Nat -> Nat)

%noinline
mk : Nat -> Rec -> Nat
mk k (MkRec h) = k + 1

%noinline
mk2 : Nat -> Rec2 -> Nat -> Nat
mk2 k (MkRec2 h) n = k + n

%noinline
selfAppT : (Rec -> Nat) -> Nat
selfAppT f = f (MkRec f)

%noinline
selfAppN : (Rec -> Nat) -> Nat
selfAppN f = S (f (MkRec f))

%noinline
selfApp2 : (Rec2 -> Nat -> Nat) -> Nat -> Nat
selfApp2 f n = S (f (MkRec2 f) n)

main : IO ()
main = do
  args <- getArgs
  let k = length args
  printLn (selfAppT (mk (k + 10)))
  printLn (selfAppN (mk (k + 20)))
  printLn (selfApp2 (mk2 (k + 30)) 5)
