****************************************
Quantity variables (experimental)
****************************************

.. warning::

   This is a prototype. The syntax, the rules and the representation may
   change or go away. Nothing in the libraries uses it.

A *quantity variable* ``%q`` stands for a quantity that is either ``1`` or
unrestricted (ω), never ``0``. It lets one function serve a linear and an
unrestricted caller:

.. code-block:: idris

    map : ((%q _ : a) -> b) -> (%q xs : LList a) -> LList b
    map f [] = []
    map f (x :: xs) = f x :: map f xs

    mapLin : ((1 _ : a) -> b) -> (1 xs : LList a) -> LList b
    mapLin = map          -- %q is 1

    mapW : (a -> b) -> LList a -> LList b
    mapW = map            -- %q is unrestricted

This page gives the rules and the argument that they accept only programs
that are well typed for every choice of ``1`` or ω for the variables. The
tests are ``tests/idris2/linear/linear023`` (``Poly.idr`` what is accepted,
``Reject.idr`` what must be rejected).

Syntax and scope
================

``%q`` (a pragma token whose name starts with a lower case letter and is not
one of the pragmas of the language) can stand where a quantity can:
``(%q x : a) -> b``, ``{%q x : a} -> b``, ``(%q _ : a) -> b``, and
``\ %q x => e``. A sigil is needed: ``(q x : a)`` already means two binders
``q`` and ``x`` of type ``a``, and no rule on lower case names could tell
the two apart without breaking programs.

The variables of a type signature of a function are bound by that signature
(they are *prenex*) and can be used in the function's clauses (including its
``where`` blocks and case blocks). Anywhere else (a data type, a record, an
interface, a lambda in another function) a variable is an error ("The
quantity variable %q is not bound here"). Each variable belongs to the
definition that binds it (its *owner*, the full name), so variables of two
definitions are never equal, even if they have the same name; the messages
name the owners when two of the same name meet. Owners are compared as
names, not as printed text. A definition with variables
has the flag ``QuantityVars`` (``Core.Context.Context.DefFlag``).

The algebra
===========

A quantity (``Algebra.ZeroOneOmega``) is ``0``, ``1``, ω, or a product of a
non-empty set of variables (kept sorted). A substitution σ maps each
variable to ``1`` or ω, and a product to ``1`` if all of its variables are
``1``, to ω otherwise. The operations are:

* ``0·x = 0``, ``1·x = x``, ``ω·x = ω`` for ``x ≠ 0``, ``S·T = S ∪ T`` (so
  ``q·q = q``);
* ``0 + x = x``, and ``x + y = ω`` when neither is ``0`` (so ``q + q = ω``);
* the order: ``0 ≤ x``, ``x ≤ ω``, ``1 ≤ S``, and ``S ≤ T`` when ``S ⊆ T``
  (a product is ω if any of its variables is), nothing else. It is partial:
  ``1`` and ``q`` are not below each other, nor ``q`` and ``r``;
* the greatest lower bound and least upper bound in that order
  (``rigMeet``, ``rigJoin``; ``glb`` and ``lub`` of ``Preorder`` are wrong for
  values that are not ordered, so they are not used on quantities).

These are *exact*: for every σ, ``σ(x·y) = σx·σy`` and ``σ(x + y) = σx + σy``;
``x ≤ y`` holds if and only if ``σx ≤ σy`` for every σ; ``x == y`` if and only
if ``σx == σy`` for every σ. (Each is checked case by case: for ``≤`` on
products, if ``S ⊆ T`` and ``σT = 1`` then every variable of ``T``, so of
``S``, is ``1``; if ``S ⊄ T``, the σ that is ω on a variable of ``S`` not in
``T`` and ``1`` elsewhere has ``σS = ω``, ``σT = 1``.) The meet and join
are not homomorphisms (``meet q r = 1``, but both may be ω), and are only
used to test whether one quantity is below another (see below).

The proofs of the ``Preorder`` instance (reflexivity, transitivity) are by
evaluation for ``0``, ``1`` and ω and *postulated* for products: they need
the laws of ``compare`` on ``String``, a primitive. The laws of addition are
proved for all values, those of multiplication for ``0``, ``1`` and ω only,
for the same reason.

The predicates used by the checks are:

``isErased``
    ``0``. A product is never ``0``, so nothing about erasure (``eraseArgs``,
    the layouts of constructors, arities) changes.
``isOne``
    exactly ``1``. A product is not ``1``.
``isCounted``
    ``1`` or a product: a variable bound at this quantity must be used
    exactly once (it may be ``1``), and a use in a context of this quantity
    counts as one use.

Checking
========

Elaboration and ``Core.LinearCheck`` (which checks every definition again
after elaboration) use the same rules; the second is the one the argument
relies on.

1. A variable bound at ``b`` can be used in a context of quantity ``c`` if
   ``c ≤ b`` (``rigSafe``; it was ``not (b < c)``, which accepts what is not
   comparable).
2. A variable bound at a counted quantity must be used exactly once in
   counted contexts (``checkUsageOK``, ``checkEnvUsage``, the arguments of
   case blocks): a use in a context ``1`` or ``S`` counts.
3. In the scope of a lambda that may be used many times (checked in an ω
   context), the variables bound at counted quantities are not usable
   (``eraseLinear``); in the scope of a lambda checked in a context ``S``
   (a product), the variables bound at ``b`` with ``S ≰ b`` are not usable
   (``eraseNotAbove``).
4. The argument of an application is checked at ``c·r`` where ``r`` is the
   quantity of the function's binder.
5. A pattern variable bound at several places of a left hand side gets the
   join of their quantities, and is rejected if two are not ``0`` and the
   meet is neither ``0`` nor ω (``combineLinear``); two uses in patterns are
   incompatible if one is counted and their sum is ω.
6. A lambda checked against ``(c x : a) -> b`` gets ``c``; an annotation
   ``\ r x`` must have ``meet r c = c``, that is ``c ≤ r``.
7. A ``case`` scrutinee or a ``let`` value that fails at ω because it uses a
   variable bound at a counted quantity ``r`` is checked again at ``r``
   (it was: at ``1`` when ``r`` is ``1``).
8. Unification and conversion require equal quantities, as before.

Instantiation
=============

At a reference to a definition with variables, outside the definition
(``TTImp.Elab.App.instantiateQuantities``), on a right hand side or in a
type (not in a pattern), each variable gets the first quantity that applies
of:

1. the one written at the reference: ``pmap {%q = 1} f xs`` (also
   ``{%q = omega}``, ``{%q = ω}``, or a variable of the enclosing
   definition, ``{%q = %r}``; ``0`` is an error);
2. the expected type. For a reference that is not applied, the quantities
   of the expected type at the same positions of the two types, as far as
   they have the same shape (Pi binders, after the implicit arguments that
   will be inserted; their domains; applications). For an application, the
   same with what is left of the function's type after the explicit
   arguments given, against the expected type of the application;
3. the explicit arguments, from left to right, as far as they tell without
   being elaborated:

   * a local variable given for an argument whose quantity is the variable
     (``(%q xs : LList a)``) gives the quantity it is bound at, if that is
     ``1`` or a product of variables (an unrestricted variable fits any
     quantity, so it says nothing);
   * a local variable, or a global without quantity variables, given for
     an argument of function type gives the quantities of its own type at
     the same positions (``pmap value ts`` with
     ``value : (1 _ : Token) -> Nat``);
   * a lambda whose binder has a written quantity (``\1 x => ...``) gives
     it to an argument of function type;

4. ω.

``0`` is never taken. The first quantity found for a variable wins, and
nothing checks that it fits the rest: a wrong choice is found by the checks
that follow, which can only reject. When an error happens in the
application, the message says what was chosen and why ("The quantities of
pmap were chosen as %q = 1 (because ts is bound at that quantity)"),
and how to write another choice. The error keeps the code of the error
inside it.

Programs that get ω and must write the quantity are those where nothing
of 1.-3. tells and a linear value is passed, for example a linear list
given as an application and a lambda without a quantity::

    noInfo : (1 ts : LList Token) -> LList Nat
    noInfo ts = pmap (\t => value t) (lreverse [] ts)   -- rejected
    ok     ts = pmap {%q = 1} (\t => value t) (lreverse [] ts)

There are no quantity metavariables and unification is unchanged. The
reference is elaborated as ``let qinst : T' = f in qinst``, where ``T'`` is
the type of ``f`` with the chosen quantities, so that ``LinearCheck``
checks the uses of ``qinst`` against ``T'``, as elaboration did; it is
printed as ``f``. Inside its own definition the variables are rigid: a
recursive call uses them as they are, and writing quantities there is an
error. "Inside" means: the definition is in the stack of definitions being
elaborated (``defsStack``), or a variable of the environment of the
reference is bound at one of its variables (which can only happen in what
the definition's own clauses bind).

A local function (in a ``where`` block or a ``let``) can have quantity
variables of its own; references to it are instantiated by the same rule.

Unfolding
=========

The compile-time case tree of a definition with variables, and of what is
defined inside it (its case blocks and ``where`` blocks), has its
variables replaced by ω (``TTImp.ProcessDef``). That tree is what the
evaluator unfolds during type checking; the clauses, which
``LinearCheck`` reads, and the run-time tree keep or do not need the
variables. Without this, ``flip f x`` unfolded in a type is
``\%q y => f y x`` with ``flip``'s own rigid ``%q``, and it is not
convertible with an ordinary lambda ``\y => f y x`` (lambdas convert only
at equal quantities), so proofs about ``flip`` and ``(.)`` stopped
checking (``contrib``'s ``Control.Validation`` did).

Why this cannot accept an ill-typed program
===========================================

Claim: if a program is accepted, then for every σ, the program with every
quantity ``x`` replaced by ``σx`` is accepted by the checks for ``0``, ``1``
and ω alone (the checker without variables, whose soundness is not argued
here).

* Arithmetic: every quantity a check computes is built with ``·`` and
  ``+`` from the quantities of the program, so by exactness σ of the
  computed quantity is what the checker without variables computes for the
  program under σ.
* Rule 1: ``c ≤ b`` implies ``σc ≤ σb``.
* Rule 2: a variable bound at ``b`` with ``σb = 1``: every use of it is in
  a context ``c ≤ b`` (rule 1), so ``σc ≤ 1``; uses in a ``0`` context are
  not counted either way, the others have ``σc = 1`` and are counted by
  both checkers, and ``c`` is counted symbolically (it is ``1`` or a
  product). So both count the same uses, and the symbolic check requires
  exactly one. If ``σb`` is ω or ``0``, the checker under σ has nothing to
  check, and the symbolic one requires at least as much.
* Rule 3: what the symbolic check makes unusable includes what the check
  under σ makes unusable (under σ, a lambda in a context of quantity ω
  makes the ``1``-bound variables unusable, and ``1 ≤ ω`` fails for them
  symbolically as well; in a context that is ``1`` under σ nothing is made
  unusable). Making more variables unusable can only reject.
* Rule 5 accepts two uses of a pattern variable only when one of the two
  quantities is ``0`` or both are ω (then the join is exact too), which σ
  preserves. Rule 6 accepts ``\ r x`` against ``c`` only when ``c ≤ r``.
* Rule 7 only changes the quantity at which something is checked and bound;
  the result is checked again by ``LinearCheck``.
* Case blocks: an argument at a counted quantity that the block uses once
  is given the quantity ``1``, one it does not use ``0``
  (``LinearCheck.updateUsage``), as for ``1`` before. Both are correct
  types for the block whatever σ is (the uses were counted by rule 2).
  Under a σ that makes the argument ω, the checker without variables would
  have kept ω: the block compiled from the symbolic program may take an
  argument erased that the other would not, which changes the compiled
  code, not what it computes.
* Unification: two quantities are equal only if they are equal under every
  σ, so no conversion holds symbolically that fails under some σ.
* Instantiation: whatever rule chooses them (written, from the expected
  type, from the arguments, by default), the type ``T'`` given to
  ``qinst`` is ``T`` with the chosen
  quantities, which are ``1``, ω or products of the caller's variables. The
  definition of ``f`` was accepted with its variables rigid, so (by this
  claim, for ``f``) it is well typed for every choice of ``1`` or ω for
  them, in particular for the choice that σ makes of the chosen quantities.
  A wrong choice can only make the caller's checks fail.
* Variables of different owners are different, so substituting into one
  definition's variables never changes another's.
* Unfolding is not covered by the claim as stated: under σ, the checker
  without variables unfolds ``(.)`` at its instance, ``\1 x => ...`` for a
  linear use, and finds it different from ``\x => ...``, where the unfolded
  tree here gives ``\x => ...``. So more conversions hold here than under
  σ, and the claim becomes: accepted here implies accepted under σ by the
  checker without variables *if the unfolded bodies are taken at ω*. The
  argument that this is harmless: a lambda bound at a variable in the
  definition was checked to use its argument exactly once, and binding a
  lambda that uses its argument once at ω is the sound direction (the one
  the eta-expansion of ``checkExp`` uses); a Pi type with a variable
  computed by the definition becomes unrestricted for every use of the
  definition alike (producer and consumer of a value of that type see the
  same type), and nothing about erasure changes (no variable is ``0``).
  Terms unfolded this way can end up in the solutions of metavariables,
  which ``LinearCheck`` checks again. This was not argued further.

What is not covered
===================

* The postulated ``Preorder`` proofs and the multiplication laws for
  products, above.
* The argument is on paper, about the code as described; nothing is
  mechanised, and the places that test quantities were reviewed by hand
  (every use of ``isLinear``, now ``isOne`` or ``isCounted``, of
  ``elimSemi``, ``branchOne``, ``branchVal``, ``<``, ``glb`` and ``lub`` on
  quantities). A test of a quantity that was missed would be a hole.
* "Inside the definition" is decided by the stack of definitions being
  elaborated and by the environment. Something elaborated for the
  definition later, outside that stack and without its variables in its
  environment, would instantiate the definition's own variables; that can
  only reject.
* Holes: the types of holes are updated with counted variables as they are
  with linear ones; a program with holes does not run.
* The Scheme evaluator (``Core.SchemeEval``) carries products as strings
  and was not tested with them.
* Interface methods, data types and records with variables are not
  supported (they are rejected). References that do not go through the
  elaboration of a name (a solution found by ``%search``, for one) are not
  instantiated: the variables stay rigid there, which can only reject.
* Reflection: ``Count`` has no variables; a quantity variable is reflected
  as ``MW``, so a type is reflected at its unrestricted instance (which is
  a type of the definition, by the claim), and ``Elab`` scripts cannot
  observe or make a variable. (It was an error; with ``%q`` in the
  Prelude's ``id``, ``derive`` reflects types that mention it.)
