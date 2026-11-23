*******************
Universe checking
*******************

.. warning::
   Universe checking is experimental and **off by default**. Without it,
   Idris has ``Type : Type``, which makes the logic inconsistent: Girard's
   paradox (for example in Hurkens' form) gives a closed term of type
   ``Void`` which the totality checker accepts. Read the section on what is
   not covered before relying on it.

Every ``Type`` which the elaborator builds carries a name standing for its
universe level. The option ``--check-universes`` checks that these levels can
be given natural numbers such that the rules of a predicative, cumulative
hierarchy hold:

* ``Type u : Type v`` needs ``u < v``;
* a function type ``(x : A) -> B`` with ``A : Type a`` and ``B : Type b`` is
  in a universe ``w`` with ``a <= w`` and ``b <= w``;
* a term whose type is ``Type u`` can be used where ``Type v`` is expected
  when ``u <= v`` (cumulativity, also in the codomain of a function type);
  elsewhere, when two types are compared, the universes in them have to be
  equal, and they also have to be equal on the left hand side of a clause;
* each field of a constructor of a data type in ``Type u`` must be in a
  universe no bigger than ``u`` (parameters are not fields). The indices of
  a data type are not fields either: the index in the return type of a
  constructor can be in a smaller universe than the argument of the data
  type, so that ``Elab (Elab a)`` is a type although an ``Elab`` computation
  can't return an ``Elab`` computation of its own universe.

The check runs after the elaborator, on the elaborated definitions: it
infers the type of every subterm again and records the constraints. They are
inconsistent exactly when they contain a cycle with a strict step, which is
then reported, naming the ``Type`` occurrences and the definitions involved,
for instance::

    Error: Universe inconsistency: these constraints form a cycle with a strict step: [E0107]
        the universe of `Type` at Hurkens:15:5--15:9 <= the universe of `Type` at Hurkens:16:10--16:14 (from Hurkens.sigma)
        the universe of `Type` at Hurkens:16:10--16:14 < the universe of `Type` at Hurkens:15:5--15:9 (from Hurkens.U)

Each declaration is checked when it has been elaborated, so the error is
reported at the definition which completes the cycle. The constraints of a
module are saved in its TTC file, and checked again together with those of
the other imports when a module is imported.

The option can be given on the command line or in the ``opts`` of a package.
It changes neither elaboration nor the TTC files beyond recording the
constraints, so modules built with and without it can be mixed, but the
check is only as complete as the set of modules built with it (see below).

Universe polymorphism
=====================

Terms do not record at which universes a global definition is used, so a
definition can only be polymorphic in universes which evaluation can never
produce: if ``T = Type`` could be used at a different universe each time,
``T : T`` would be accepted. The universes which are never renamed ("fixed")
are those occurring in the right hand side of a clause (or in the solution of
a metavariable used there or in the definition's type), and those in a field
of a constructor: the contents of a data type do not depend on the universe
it is used at. A definition is polymorphic in the other universes of its
type and of its left hand sides; each use of it renames them and copies the
constraints which its own checking put on them. A data type and its
constructors are renamed together, and the universes of a parameter in a
constructor are made equal to those in the data type. This covers ``id``,
``(.)``, ``map`` and other functions, and data types such as ``List``, ``Pair``
or ``Vect``: a list of types can contain lists of types.

To keep these renamings independent, the elaborator gives the universes in
the type of a global a fresh name at each use when the option is on (it
copies parts of those types into the terms it builds). A universe which
also occurs in the type of another definition is renamed only if that
definition is polymorphic in it and was checked completely before.

A definition is used with its own universes (monomorphically) until it has
been checked completely, so recursive and mutual uses are monomorphic, and so
are definitions which used a metavariable that was still unsolved when they
were checked.

How far it gets
===============

With ``--check-universes``, the ``prelude`` library is checked completely, at
a cost of about 20% more instructions for building it. ``base`` is not
accepted: universes in the fields of a constructor are monomorphic, and the
methods of an interface are such fields, so a method which quantifies over
types (``(>>=) : m a -> (a -> m b) -> m b``) is at the same universe in every
implementation. ``Language.Reflection`` then needs the method universes of
``Functor``/``Monad`` to be both above and below the universe of the fields of
``Elab``. This is a limitation, not an inconsistency: lifting it needs
definitions which are polymorphic in the universes of their fields, which
needs the universe instance of a use to be recorded in terms. For the same
reason a type such as ``data HList : List Type -> Type`` can't contain an
``HList`` of its own universe.

What is not covered
===================

* Modules built without ``--check-universes`` contribute no constraints.
  When a module built with the option imports one built without it, the
  compiler warns, and the check covers only the modules built with it. To
  check a program completely, every library it uses (including ``prelude``
  and ``base``) has to be built with the option, which is not possible yet for
  ``base`` (see above).
* The elaborator does not always produce terms which are well typed when
  checked again: it builds the motive of a ``rewrite`` by abstraction without
  checking it, and it compares types without the arguments which other
  arguments determine. The check compares types the same way as a last
  resort; when even that fails, or when it meets something else it can't
  check, it carries on, but reports the definition in a warning as not
  checked completely, and does not make it polymorphic.
* Definitions which do not go through the declaration processor are not
  checked: terms built by the REPL and by interactive editing.
* The check is about universes only. Matching on types in a way that makes a
  type constructor invertible (upstream issues #1116 and #1326) is a
  separate source of inconsistency, which the totality checker rejects
  (error ``E0705``), with or without this option.
* ``believe_me``, ``assert_total``, ``%unsafe`` and foreign functions can
  prove anything and are out of the scope of the check.
* Where the elaborator leaves a part of a term erased, no constraints come
  from that part.
