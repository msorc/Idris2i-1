||| `total2` is copied by --spec-interfaces at `Sz (List Int)`, whose
||| implementation is copied too, in the modules A and B, which do not import
||| each other.  Their copies are in the namespaces of their modules, so the
||| copy of `total2` that each makes is by a different copy of the
||| implementation.  Main, which imports both, reuses one of them: the copies
||| of the implementation are the same.
module Base

public export
interface Sz a where
  sz : a -> Int

public export
Sz Int where
  sz x = x

public export
Sz a => Sz (List a) where
  sz [] = 0
  sz (x :: xs) = sz x + sz xs

public export
total2 : Sz a => List a -> Int
total2 [] = 1
total2 (x :: xs) = sz x * 2 + total2 xs
