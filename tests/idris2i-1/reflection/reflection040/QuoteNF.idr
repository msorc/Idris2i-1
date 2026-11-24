import Language.Reflection
import Lib

%language ElabReflection
%default total

double : Nat -> Nat
double Z = Z
double (S k) = S (S (double k))

-- `quote` only reduces the head of a value, `quoteNF` normalises it
heads : Elab ()
heads = do
  logTerm "" 0 "quote (double 2)" !(quote (double 2))
  logTerm "" 0 "quoteNF (double 2)" !(quoteNF False (double 2))

%runElab heads

-- open terms: what is stuck stays stuck
openTerm : Nat -> Elab ()
openTerm n = do
  logTerm "" 0 "quoteNF (\\x => double (S x) + n)" !(quoteNF False (\x => double (S x) + n))

%runElab openTerm 3

-- the definitions which are not visible here stay folded, unless all of
-- them are unfolded
visibility : Elab ()
visibility = do
  logTerm "" 0 "public export" !(quoteNF False (pub 2))
  logTerm "" 0 "export" !(quoteNF False (abstr 2))
  logTerm "" 0 "export, unfoldAll" !(quoteNF True (abstr 2))
  logTerm "" 0 "export using private" !(quoteNF False (usesPriv 2))
  logTerm "" 0 "export using private, unfoldAll" !(quoteNF True (usesPriv 2))

%runElab visibility

-- normaliseTerm: from syntax to syntax
fromSyntax : Elab ()
fromSyntax = do
  logTerm "" 0 "normaliseTerm" !(normaliseTerm False `(\x : Nat => double 1 + pub x))
  -- interface methods are reduced to the implementation
  logTerm "" 0 "normaliseTerm (+)" !(normaliseTerm False `(\x, y : Nat => x + y * 2))

%runElab fromSyntax
