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

Planned: universe instances on all references
=============================================

Implementations of interfaces are monomorphic today, and ``base`` needs them
to be polymorphic (see below). The plan is to record a universe instance on
every reference to a global definition, not only on type constructors, as Coq
and Lean do. This is the argument it has to meet, written before the
implementation.

#. **What a definition's schema is.** All universes of its type, of its left
   hand sides and of its right hand side, and the instances of the references
   in them, are the definition's own. A reference ``f{s}`` stands for the copy
   of ``f`` with them renamed by ``s``. A reference inside ``f``'s body to
   another global ``g`` carries an instance made of ``f``'s own names, so it is
   renamed with ``f``: unfolding ``f{s}`` gives ``g{s(t)}``. A reference
   without an instance (one built by a part of the compiler that does not
   make instances, or read from a TTC file written without the option) stands
   for ``g``'s own universes, which are not ``f``'s: it is never renamed, so
   it only adds constraints. A constructor carries no instance: its type is
   fixed by the type it is expected at, whose type constructor instance is
   one of ``f``'s names.
#. **Unfolding.** Unfolding ``f{s}`` gives ``f``'s right hand side renamed by
   ``s``. This is what replaces the old rule that the universes evaluation
   can produce are fixed: they are now renamed with the reference. With
   ``T = Type``, ``T{a}`` unfolds to ``Type a`` and has type ``Type a'`` with
   ``a < a'``. So ``x : T; x = T`` is ``x : T{a} = T{b}``, which needs
   ``b < a``: it is accepted, as in Coq, because it says no more than
   ``Type b : Type a``. What the old rule prevented, ``T : T`` at one
   universe, is still rejected wherever the two uses are the same copy: in
   ``T``'s own mutual group, or through a monomorphic alias. ``Wrap``/``Pack``
   and Russell's paradox through an interface stay rejected for the reason
   they are now: the ``Wrap`` held and the ``Wrap`` holding it are made one
   copy by conversion.
#. **Conversion.** Two references to the same definition are compared by
   recording that their instances are equal (through the existing hook) and
   comparing their arguments, without unfolding; unfolding happens only when
   the heads differ or the arguments do not convert. Recording eagerly is
   sound (it only adds constraints) and can reject a program that unfolding
   would accept (two copies of a definition whose body does not depend on the
   differing universes); that is the side to err on. It also keeps the cost
   of the check close to that of the conversion the elaborator does anyway.
#. **Recursion.** The references of a definition to itself and to the other
   members of its mutual group carry no instance: they are at the group's
   own universes, as in Coq. An implementation, its methods and the default
   methods elaborated for it are one group in this sense: the dictionary
   refers to the method bodies before they are checked.
#. **Metavariables.** A definition which met an unsolved metavariable is not
   made polymorphic, as now: a solution found later can't change a schema
   that uses have already been renamed by.
#. **References not made by the elaborator's name lookup.** A reference that
   proof search builds (an implementation found for a constraint, a hint, a
   parent implementation) gets a fresh instance where search builds it, like
   one written by the user; the checker relates it to its uses. The
   dictionary of an implementation refers to its method bodies and parents:
   the bodies are in its group (above), the parents are found by search.
   Default method bodies are elaborated again for each implementation, as
   definitions of their own.
#. **Case blocks, with blocks, local definitions.** They are lifted to top
   level but share their parent's universes: the parent's reference to them
   carries the parent's own names as instance, so they are renamed with the
   parent, and they are checked with the parent.
#. **Other sources of terms.** Copies made by partial evaluation and the
   right hand sides of ``%transform`` rules are used at run time only and
   are not part of any type. A term quoted by elaborator reflection loses its
   instances; a declaration given to ``Declare`` goes through the declaration
   processor, and a ``Check`` or ``Infer`` result is spliced back as
   ``TTImp``, which is elaborated again: either way it gets fresh instances
   and is checked as part of the definition that contains it, so no term
   enters unchecked. TTC files written without the option give references
   without instances (monomorphic), and their modules contribute no
   constraints, as now.
#. **The rest of the check.** The rule for patterns on types and the
   cumulativity of indices do not change: a pattern on a type matches a type
   constructor, and the variables it binds are bounded by the universe of
   the type matched whatever the instances.

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
