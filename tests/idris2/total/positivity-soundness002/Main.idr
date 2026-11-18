module Main
import Lib
%default total
data Bad : Type where
  MkBad : NegT Bad -> Bad
data Bad2 : Type where
  MkBad2 : Hidden Bad2 -> Bad2
notBad2 : Bad2 -> Void
notBad2 (MkBad2 h) = useHidden h (MkBad2 h)
void : Void
void = notBad2 (MkBad2 (mkHidden notBad2))
