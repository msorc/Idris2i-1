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
It changes neither elaboration nor the TTC files beyond recording the
constraints, so modules built with and without it can be mixed, but the
check is only as complete as the set of modules built with it (see below).

Universe polymorphism
=====================

Terms do not record at which universes a global function is used, so a
function can only be polymorphic in universes which evaluation can never
produce: if ``T = Type`` could be used at a different universe each time,
``T : T`` would be accepted. The universes which are never renamed ("fixed")
are those occurring in the right hand side of a clause (or in the solution of
a metavariable used there or in the definition's type). A function is
polymorphic in the other universes of its type and of its left hand sides;
each use of it renames them and copies the constraints which its own checking
put on them. The solved metavariables of a type (the inferred type of a
parameter, for instance) are part of it and renamed with it.

A use of a type constructor does record its universes: with the option on,
the elaborator gives each use the names of its own copy of the universes in
the fields of the data type (its *universe instance*), and conversion between
two uses of the same type constructor makes their instances equal. So the
fields of a data type are polymorphic too: a list of types can contain lists
of types, an ``HList`` can contain ``HList`` s, and two implementations of an
interface can use its methods at different universes. The other universes of
a data type (of its parameters, indices and of the data type itself) are
renamed at each use, and the universes of a parameter in a constructor are
made equal to those in the data type. A use without an instance stands for
the data type's own universes. The recursive uses of a data type in its own
constructors are at its own universes.

Why this is sound, in short:

#. A data type ``F`` has a list of field universes and the constraints which
   checking its declaration produced (each field no bigger than ``F``'s
   universe, strictly when the field is a type). A use ``F{s}`` is the copy of
   ``F`` whose field universes are ``s``, with those constraints renamed.
#. A constructor gets fresh universes at each use; the type it builds,
   ``F{s'}``, meets the expected type ``F{s}`` only through conversion, which
   makes ``s'`` and ``s`` equal. So a value of ``F{s}`` stores fields of the
   copy ``s``, and matching on it (the pattern's type is made equal to the
   type of the value) gives them back at ``s``.
#. Matching on a *type* gives back types of the copy given at run time, which
   is not known: so every variable bound by a pattern on a type is put no
   lower than the universe of the type matched.
#. Every identification the check relies on goes through its own conversion
   calls, so two different copies never convert silently (unification may
   ignore instances: the check sees the elaborated term again).
#. Unfolding a definition gives its right hand side with its own universes,
   instances included, which are fixed, never renamed.
#. Any part of the compiler which builds a use of a type constructor without
   an instance makes it monomorphic: more constraints, never fewer.

Implementations of interfaces stay monomorphic: their right hand sides (the
lambdas of the methods, the solved implicit arguments) fix their universes.

How far it gets
===============

With ``--check-universes``, the ``prelude`` library is checked completely, at
a cost of about twice the instructions of building it without the option.
``base`` is not accepted yet. ``Language.Reflection`` passes, and
``Deriving.Common`` does too when the ``Prelude`` interfaces give their
parameter type (see below); ``Deriving.Traversable`` does not: its cycles go through the method
universes of implementations (``Monad Elab``, the monads of ``StateT`` and
``EitherT``), which are monomorphic, so all uses of ``>>=`` through one
implementation share them, and one of these uses binds a type (the result of
``check {expected = Type}``). The ``Prelude`` interfaces whose parameter type
is inferred also make the universes of that parameter fixed; giving the type
(``interface Functor (0 f : Type -> Type)``) avoids it.

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
