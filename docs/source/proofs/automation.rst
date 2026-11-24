.. _proofs-automation:

****************
Proof Automation
****************

Idris2i-1 has no tactic language, but elaborator reflection (the ``Elab`` monad
of ``Language.Reflection``, run with ``%runElab`` or in a ``%macro``) lets a
library inspect the goal and build the proof term. This section describes the
primitives that a tactic or a solver needs, the derivers built on them, and a
solver for equalities of natural numbers.

Reflection primitives
=====================

Besides ``check``, ``quote`` and ``goal``, the ``Elaboration`` interface has:

``infer : TTImp -> m (TTImp, TTImp)``
  Elaborate a term without an expected type, and return the elaborated term
  and its type. Defaults are resolved (``3`` is an ``Integer``). If the term
  or its type still contains an unsolved metavariable, ``infer`` fails: give
  a type annotation with ``the``.

``quoteNF : (unfoldAll : Bool) -> (0 _ : val) -> m TTImp``
  Quote a value after normalising it. ``quote`` only reduces the head of a
  value. Without ``unfoldAll``, only the definitions visible from the current
  module are unfolded, as during type checking; with it, all of them are.
  ``normaliseTerm unfoldAll t`` does the same to the syntax ``t``, which is
  what a tactic usually holds.

``convertible : TTImp -> TTImp -> m Bool``
  Test whether two terms are equal up to evaluation. The second is
  elaborated at the type of the first. Whatever the elaboration solved or
  defined is undone: only the answer is kept. This is a test, not
  unification; to unify, use ``check`` inside ``try``.

``getClauses : Name -> m (List Clause)``
  The clauses of a function defined by pattern matching, as ``:printdef``
  shows them. The clauses of a ``private`` or ``export`` definition can only
  be read in the module that defines it. Constructors, primitives and other
  names that are not defined by pattern matching make it fail.

``Elab`` also has a primitive ``join``, which runs a script that returns a
script.

.. code-block:: idris

    import Language.Reflection
    %language ElabReflection

    double : Nat -> Nat
    double n = n + n

    showNF : Elab ()
    showNF = do
      t <- normaliseTerm False `(\x => double (S x))
      logTerm "" 0 "normal form" t     -- \x => S (plus x (S x))

    %runElab showNF

A script runs in the module that uses it, so it can only compute with the
functions of the modules loaded there: the modules which that module imports,
and those they import publicly. A library of scripts should not depend on
functions that it imports privately.

Deriving ``Eq``, ``Ord`` and ``DecEq``
======================================

``Deriving.Eq``, ``Deriving.Ord`` and ``Deriving.DecEq`` derive these
interfaces as ``Deriving.Show`` derives ``Show``:

.. code-block:: idris

    import Deriving.Eq
    import Deriving.Ord
    import Deriving.DecEq
    %language ElabReflection

    data Tree a = Leaf a | Node (Tree a) a (Tree a)

    %hint treeEq : Eq a => Eq (Tree a)
    treeEq = %runElab derive

    %hint treeOrd : Ord a => Ord (Tree a)
    treeOrd = %runElab derive

    %hint treeDecEq : DecEq a => DecEq (Tree a)
    treeDecEq = %runElab derive

Two values are compared constructor first (in the order of declaration, for
``Ord``), then field by field from left to right. Erased fields are not
compared by ``Eq`` and ``Ord``; ``DecEq`` fails on them, since their values
cannot be inspected. A field of the type itself is compared with a direct
recursive call, so the derived function is total; a field which mentions the
type inside another type constructor (``List (Tree a)``) is compared through
the implementation being defined, which must then be a ``%hint``. The
``DecEq`` deriver uses ``getDecEqConPairs`` to write the refutations of the
pairs of constructors that can build values of one type, and no clause for
the others.

An indexed family is supported when the indices in the types of its
constructors are made of constructors and variables (``Vect (S n) a``), and
the implicit arguments its fields depend on occur in them. Otherwise two
values of one type need not have fields of the same types, and the derivation
fails with a message saying which constructor is the problem.

Solving equalities of natural numbers
=====================================

``Data.Nat.Solver`` (in ``contrib``) proves equalities that hold in every
commutative semiring, between expressions built from variables, literals,
``S``, ``+`` and ``*``:

.. code-block:: idris

    import Data.Nat.Solver

    example : (x, y, z : Nat) -> (x + y) * (z + 1) = x * z + y + z * y + x
    example x y z = solveNat

The macro normalises the goal, reifies both sides as expressions over their
atoms (a term which is not a literal, ``S``, ``+`` or ``*``, such as a
variable or ``minus x y``), and checks that they have the same polynomial
normal form. The proof is ``prove env lhs rhs Refl``, where ``prove`` rests
on a soundness theorem proved once. When the normal forms differ, the error
shows both of them. Atoms are compared syntactically, so ``f (x + y)`` and
``f (y + x)`` are different atoms. Coefficients are unary, so the cost of
checking a proof grows with the coefficients of the polynomials; a goal with
20 monomials on each side and coefficients up to 6 costs about 1.6e9
instructions to check, well under a second.
