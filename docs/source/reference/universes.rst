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
* a pattern which matches on a type (``elemOf (List a) = a``, or a function
  type) binds its variables in universes no smaller than that of the type
  it matches, since the type given at run time can be any type of that
  universe;
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
        the universe of `Type` at Hurkens:16:10--16:14 < an inferred universe (from Hurkens.U)
        an inferred universe <= the universe of `Type` at Hurkens:16:10--16:14 (from Hurkens.sigma)

Each declaration is checked when it has been elaborated, so the error is
reported at the definition which completes the cycle. The constraints of a
module are saved in its TTC file, and checked again together with those of
the other imports when a module is imported.

The option can be given on the command line or in the ``opts`` of a package.
It changes what elaboration does only by the universe names in the terms it
builds (the universe instances, see below), and the TTC files only by these
and the constraints, so modules built with and without it can be mixed, but
the check is only as complete as the set of modules built with it (see
below).

Universe polymorphism
=====================

Every definition is universe polymorphic, as in Coq and Lean: a use of a
global definition is a *copy* of it, in which the definition's universes are
renamed. With the option on, the elaborator gives each reference to a
function or a type constructor which has been checked completely a *universe
instance*: fresh names for the definition's universes, in the order of its
*universe schema*. The schema of a function covers the universes of its
type, of its left hand sides and right hand sides, and of the instances of
the references in them; that of a data type covers the universes of its
fields (the other universes of a data type, of its parameters, indices and
of the data type itself, are renamed at each use, and those of a parameter in
a constructor are made equal to those in the data type). Unfolding a
reference with an instance gives the definition's right hand side renamed to
the instance; conversion between two references to the same definition
makes their instances equal; and the checker types a reference with the
definition's type renamed to the instance, together with the constraints
which checking the definition put on its universes. So ``T = Type`` is
``Type a`` at one use and ``Type b`` at another, a list of types can contain
lists of types, an ``HList`` can contain ``HList`` s, and two uses of one
implementation of an interface can be at different universes.

A reference without an instance stands for the definition's own universes,
which are never renamed. References have none:

* within a *group*: a definition and the case blocks, with blocks and local
  definitions lifted out of it; an implementation of an interface and its
  methods (the record of the implementation refers to the method bodies
  before they are checked); the definitions of a ``mutual`` block; and a
  definition's references to itself. A group has one schema, and a
  reference from one of its definitions to another is renamed with the
  definition it is in;
* to a definition which met an unsolved metavariable, or which could not be
  checked completely (see below): it is not made polymorphic;
* to a primitive (an ``%extern`` or ``%foreign`` function, or a builtin): it
  has no body, so a use renames the universes of its type afresh, as for a
  constructor. The declared type of a primitive is an assumption, as it is
  for anything a primitive does; a function declared before its clauses is
  not a primitive;
* when built by parts of the compiler which do not make instances, or read
  from a TTC file written without the option.

A universe of a definition which another definition has too (in its type or
clauses) is not renamed, unless both are in one group. A copy renames fewer
universes than the definition has, because every reference to a function has
an instance of all the universes of the function's body, which are the
universes of the references in that body too, and so on:

* a universe made equal to another one goes with it, and one which is not in
  the definition's type and has a single lower bound, which it can equal, is
  set to it;
* a universe which no constraint connects, through the definition's own
  universes, to a universe of its type is not renamed at all: the copies
  share it (it can only be seen by unfolding the definition);
* a function whose clauses have none of the universes left is used without
  an instance: unfolding it gives the same body at every use, so the
  checker gives its type fresh universes at each use, as for a constructor;
* a group with more than 256 universes left is not made polymorphic (each
  reference to it would carry them all).

Each of these only gives copies less freedom (or none), which can reject a
program that full polymorphism would accept, never the other way round.

Why this is sound, in short:

#. A reference ``f{s}`` stands for the copy of ``f`` at ``s``: ``f``'s
   checking is closed under renaming its universes, so the copy is well typed
   when ``f``'s constraints, renamed, hold, and they are added where the copy
   is used. Setting universes of the copy to values which satisfy those
   constraints (the minimisation above) gives a copy too.
#. Unfolding ``f{s}`` gives ``f``'s right hand side renamed to ``s``,
   references in it included (their instances are made of ``f``'s universes,
   so they are renamed with it); the solutions of the metavariables in it are
   put in place first, so that they are renamed too. A reference without an
   instance is not renamed: it is the same copy wherever it is. So the term
   a reference stands for and the type it is given always agree.
#. A constructor carries no instance: its type is fixed by the type it is
   expected at, through conversion with the type constructor's instance. So
   a value of ``F{s}`` stores fields of the copy ``s``, and matching on it
   (the pattern's type is made equal to the type of the value) gives them
   back at ``s``. Matching on a *type* gives back types of the copy given at
   run time, which is not known: so every variable bound by a pattern on a
   type is put no lower than the universe of the type matched.
#. Every identification the check relies on goes through its own conversion
   calls, which record that the instances of two references to the same
   definition are equal (unification may ignore instances: the check sees
   the elaborated term again). Two different case blocks are not taken to be
   the same, as the elaborator does when they come from the same place.
#. Recursion and groups use one copy, as in Coq: ``T : T`` is still rejected
   wherever the two uses are the same copy, for instance in a ``mutual``
   block or among the local definitions of one definition. ``x : T; x = T``
   outside one is ``x : T{a} = T{b}`` with ``Type b : Type a``, and is
   accepted, as in Coq.
#. A definition which met an unsolved metavariable is not made polymorphic:
   a solution found later can't change a schema that uses have already been
   renamed by. References built by proof search get a fresh instance where
   search builds them, like one written in the source. Terms quoted by
   elaborator reflection lose their instances, and are elaborated (so given
   instances) again before they are part of a definition; copies made by
   partial evaluation and ``%transform`` rules are only used at run time.

How far it gets
===============

With ``--check-universes``, the ``prelude`` library is checked completely, at
a cost of about 2.3 times the instructions of building it without the option
(the TTC files are 2.4 times bigger: every reference carries its instance).
``base`` is not accepted yet: ``Language.Reflection``, ``Deriving.Common`` and
``Deriving.Traversable.derive'`` pass, ``Deriving.Traversable.derive`` does
not. Its cycle goes through the copies of ``MonadError e (EitherT e m)`` and
``Monad Elab`` which it uses at ``m = Elab``: the index universe of ``Elab``
is above ``Elab``'s own (``Join`` takes an ``Elab (Elab a)``), and ``EitherT``
stores an ``m (Either e a)``. Interfaces whose parameter type is inferred make
the universes of that parameter shared by all their methods; giving the type
(``interface Functor (0 f : Type -> Type)``) avoids it, and the ``Prelude``
and ``base`` interfaces do.

The shapes which still fail are reduced in the test ``universe010``. Two are
not typeable in a predicative hierarchy: a monad whose bind is a constructor
(``Elab``, ``L`` of ``Control.Linear.LIO``) hides the intermediate type in a
field strictly below its own universe, and a transformer over it
(``EitherT``) binds through it at a type which holds the same copy of it
(every ``Monad`` dictionary holds a ``join``); and ``join`` of
``Text.Parser.Core`` puts a grammar into the hidden field of the same copy.
The third is a limit of this check: the compiler's
``Libraries.Data.WithData.AddMetadata`` matches on a type ``WithData ls a``
whose ``ls`` holds types. A pattern on a type puts every universe in the type
of what it binds no lower than the universe ``w`` of the type matched, but the
types inside a run time ``ls`` are only strictly below ``w``: the exact
requirement is ``w <= f + 1``, which the check can't express (it has no
successor constraints), so it rejects the definition. ``Mu`` of the paper
``Control.DivideAndConquer`` is impredicative and is rejected for good.

Each binder of a declared type whose type is a universe gets a universe of
its own: the elaborator infers the type of a type variable by unification
(in ``f a``, as the domain of ``f``), where cumulativity only needs it to be
no bigger.

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
