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
name the owners when two of the same name meet. A definition with variables
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

At a reference to a definition with variables, outside the definition (and
what is defined inside it), each variable gets a quantity:

* if the reference is not applied and its expected type is known, the
  quantities of the expected type at the same positions of the two types,
  as far as they have the same shape (Pi binders, after the implicit
  arguments that will be inserted; their domains; applications), except
  ``0``, which is never taken;
* ω for the others (in particular for every applied reference).

There are no quantity metavariables and unification is unchanged. The
reference is elaborated as ``let f' : T' = f in f'``, where ``T'`` is the
type of ``f`` with the chosen quantities, so that ``LinearCheck`` checks
the uses of ``f'`` against ``T'``, as elaboration did. Inside its own
definition the variables are rigid: a recursive call uses them as they are.

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
* Instantiation: the type ``T'`` given to ``f'`` is ``T`` with the chosen
  quantities, which are ``1``, ω or products of the caller's variables. The
  definition of ``f`` was accepted with its variables rigid, so (by this
  claim, for ``f``) it is well typed for every choice of ``1`` or ω for
  them, in particular for the choice that σ makes of the chosen quantities.
  A wrong choice can only make the caller's checks fail.
* Variables of different owners are different, so substituting into one
  definition's variables never changes another's. When a definition is
  unfolded during conversion, its variables stay its own and rigid: at
  worst a spurious mismatch (``Reject.idr``, ``staleOmega``, ``staleNext``).

What is not covered
===================

* The postulated ``Preorder`` proofs and the multiplication laws for
  products, above.
* The argument is on paper, about the code as described; nothing is
  mechanised, and the places that test quantities were reviewed by hand
  (every use of ``isLinear``, now ``isOne`` or ``isCounted``, of
  ``elimSemi``, ``branchOne``, ``branchVal``, ``<``, ``glb`` and ``lub`` on
  quantities). A test of a quantity that was missed would be a hole.
* Owners are compared by the printed full name of the definition. Two
  different definitions that print the same would share variables.
  Definitions with machine-generated names (in ``where`` blocks, case
  blocks) are not known to collide, but this was not proved.
* "Inside the definition" is decided by the stack of definitions being
  elaborated (``defsStack``). Something elaborated for the definition later,
  outside that stack, would instantiate the definition's own variables (at
  ω); that can only reject.
* Holes: the types of holes are updated with counted variables as they are
  with linear ones; a program with holes does not run.
* The Scheme evaluator (``Core.SchemeEval``) carries products as strings
  and was not tested with them.
* Interface methods, data types and records with variables are not
  supported (they are rejected). A local function (in a ``where`` block)
  with variables of its own is accepted, but references to it are never
  instantiated: its variables stay rigid where it is used, which can only
  reject. References that do not go through the elaboration of a name
  (a solution found by ``%search``, for one) are not instantiated either,
  with the same effect.
* Reflection: ``Count`` has no variables; reflecting a quantity variable is
  an error ("Can't reflect the quantity %q"), so ``Elab`` scripts cannot
  observe or make one.
