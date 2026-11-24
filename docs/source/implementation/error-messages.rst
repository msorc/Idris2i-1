.. _sect-error-messages:

**********************
Writing error messages
**********************

This page is the reference for the text of the compiler's errors and
warnings: how a message is laid out, which parts of it are fixed, and how to
check a change to it. Messages are built in ``src/Idris/Error.idr``
(``perrorRaw`` for errors, ``pwarningRaw`` for warnings) from the ``Error``
and ``Warning`` types of ``src/Core/Core.idr``.

Structure of a message
======================

A message has up to four parts, in this order:

1. **Headline**: one sentence that says what is wrong, ending with a full
   stop: ``Mismatch between: Nat and String.``, ``Undefined name foo.``.
   The context it was found in comes before it, as a sentence of its own
   (``While processing right hand side of f.``). The headline should make
   sense on its own; tools and ``failing`` blocks often see nothing else.
2. **Source excerpt**: the location (``File:12:5--12:9``) and the lines
   around it with the range underlined, printed by ``ploc`` (or ``ploc2``
   for two ranges). A message shows each excerpt once: a message about
   several attempts at the same place (the candidates of an ambiguous name)
   shows the place once for all of them. Excerpts are left out of JSON
   diagnostics (``--error-format json``), which have the location as fields.
3. **Details**: lines that explain the headline, each starting with a label
   or indented under it: the expected and the actual type, the missing
   cases, the calls on a non-terminating path.
4. **Suggestion**: what to try, starting with ``Suggestion:`` or ``Did you
   mean``, last.

Stable phrases are an interface
===============================

Users match messages in ``failing "..."`` blocks, and the test suite pins
them in ``expected`` files. ``failing`` compares the text of the message,
without the source excerpts and with all white space collapsed, and succeeds
if the given string occurs in it. These phrases are relied on and must stay
as they are, with their operands in the same order:

* ``Mismatch between: A and B.``
* ``When unifying``
* ``Can't solve constraint between: A and B.``
* ``Can't find an implementation for``
* ``is not covering``
* ``is not total``
* ``Undefined name``
* ``Sorry, I can't find any elaboration which works. All errors:``
* ``Ambiguous elaboration``
* ``While processing``

A change may add labels, lines, grouping, ordering and context around them,
but not reword them, split them, or swap their operands. Before changing the
text around one of them, search the ``failing`` blocks
(``grep -rn 'failing "' tests libs docs``) for strings that span the part
you change.

Expected and actual types
=========================

When one type is the type an expression has and the other the type its
context expects, they are labelled, expected first, aligned:

.. code-block:: none

    Error: While processing right hand side of f. When unifying:
        Expected: Vect (S n) a
        Got:      Vect n a
    Mismatch between: n and S n.

When the inner mismatch is about the same two types, it comes first and the
labelled pair follows, so that the pair is not printed twice without labels:

.. code-block:: none

    Error: While processing right hand side of wrong. Mismatch between: a and Vect ?k ?a.
    When unifying:
        Expected: Vect ?k ?a
        Got:      a

The order is known where the elaborator checks an expression against the
type expected of it (``checkExp``, ``convert`` in ``TTImp.Elab.Check``,
which throw ``WhenUnifying`` with ``GotExpected``). A constraint postponed
while doing so keeps the order (``termOrder`` of ``UnifyInfo``, noted on the
``Constraint``), and so does the error when it fails as it is retried later
(``retry`` in ``Core.Unify``); a constraint posted anywhere else is
``Unordered`` and printed without labels, as ``When unifying: X and: Y``.
Only label a pair when the order is certain at the place the error is
thrown.

Postponed constraints
=====================

A constraint that cannot be solved yet is postponed and retried when a
metavariable is solved. When it fails then, the message names the
metavariables of the constraint solved since it was posted, with their
solutions and the place of the unification that solved them (noted in
``solvedAt`` of the unification state while there are constraints left):

.. code-block:: none

    This was postponed, and failed after inferring ?f = \arg => String (at Postponed:6:7--6:35).

A constraint left unsolved at the end of a definition is reported with the
others left with it, each at the place it was posted, at most 5:

.. code-block:: none

    Error: While processing right hand side of leftover. Can't solve constraint between: String and ?f 1.
    ...
    Also left unsolved:
        Nat and ?f 0 (at Postponed:13:17--13:26)

Candidates of an ambiguous name
===============================

When every candidate of an overloaded name fails, the message lists the
errors of the candidates (``AllFailed``):

* they are ranked, the most promising first (``rankFailures`` in
  ``TTImp.Elab.Check``): the attempt that got furthest, then failed searches
  and constraints, then mismatches of two types with the same head, then
  other mismatches, then wrong numbers of arguments, then the names of the
  current namespace;
* candidates that fail with the same kind of error at the same place are
  printed one line each, under one source excerpt; if they all have the
  same actual type, a summary line says so;
* at most 5 candidates are shown, followed by ``... and N more
  candidates``. ``--candidate-error-count N`` changes the number, and 0 shows
  all of them.

The location of the error (in JSON diagnostics and the IDE mode) is the
place where the ambiguous name is used, not the place where one of the
candidates failed.

Interface resolution errors
===========================

The headline of a failed search is always ``Can't find an implementation
for G.`` (``CantSolveGoal``), and the details say why, as far as it can be
told:

* when an implementation matched the goal but the search for one of its
  constraints failed, the chain of implementations, each by its type as it
  is declared and where it is defined (in full in the file of the error, by
  module elsewhere, so that a message does not change with the line numbers
  of a library), and the constraint it needs, indented, at most 4 levels
  (the first three and the last):

  .. code-block:: none

      The implementation Show a => Show (List a) (in Prelude.Show) matches, but needs Show (Box Foo).
          The implementation Show a => Show (Box a) (at Why:11:1--12:26) matches that, but needs Show Foo.
              There is no implementation of Show for Foo in scope.

* for the goal (or the last constraint of the chain) itself:
  ``There is no implementation of I for T in scope.`` when no hint of the
  interface can match its head; the implementations that match but are not
  visible; a local implementation of the interface (a constraint or an
  ``auto`` argument) that is in scope for other types; and when an argument
  that determines the implementation is an unsolved metavariable, that it
  is not known, with the default of the interface if it has one
  (``%defaulthint``) and a suggestion to give the type.

The search records the chain (``SearchNeeds``, the cause of
``CantSolveGoal``) as the failure propagates out of ``searchIfHole``, and
everything else is worked out when the message is printed
(``searchNotes``, from the hints of the context and the binders of the
goal), so that a search that succeeds costs nothing more. Keep it that way:
a candidate that fails inside a search that succeeds must not pay for a
message nobody reads.

``Multiple solutions found in search of:`` lists the solutions by the hint
they are built from, an implementation by its type and location, a named
implementation or hint by its name, and suggests ``@{name}`` for the named
ones.

Totality and coverage errors
============================

The headline names the definition and its location is that of the
definition (in JSON diagnostics and the IDE mode too), but the excerpt
shows the call that is the problem, where one is known:

* for a function that calls itself, the recursive call, and how each
  argument that is matched against a constructor compares to its pattern
  (``Argument 1 (n): passed S n, which is not smaller than the pattern S
  n.``), at most 3 of them, or one line when no argument is matched against
  a constructor;
* for a cycle of several functions, the first call of the cycle, and the
  calls of the cycle once round with their locations (the checker can find
  a cycle that goes round twice: ``onceRound`` in ``Idris.Error``);
* for a call to a function that is not total, or not covering, the call,
  and why the function called is not total, in one line.

The calls are those of the size change graph of the definition, found
again as it was built (``callArgsAt`` in ``Core.Termination.CallGraph``), so
nothing more is stored for them. Missing cases are printed so that they
can be pasted as clauses: a variable that occurs once is ``_`` and those
that occur more than once get different names without braces
(``pshowPattern``); at most 10 are printed, followed by ``... and N more``.

Source excerpts
===============

An excerpt of one line shows the four lines before it and underlines the
range. An excerpt of several lines underlines the range from where it
starts to the end of its first line, and on its last line up to where it
ends; when it is longer than 6 lines, the lines between its first two and
its last two are left out (`` .. |``).

Names
=====

* Names are printed as the user would write them: without the namespace
  when that is unambiguous, with operators in parentheses.
* Within one message a name is printed in one form. If the details print a
  name qualified (a path of calls, a list of candidates from several
  modules), the headline uses the same qualified form.
* Machine generated names are printed by their root (``MN "b" 1`` prints as
  ``b``), unless ``--show-machine-names`` is given. When this would print
  two different variables of one message alike, the variable the user named
  keeps its name and the others get a number in braces: ``b`` and ``b{1}``.
  Unsolved metavariables print as ``?`` and their root (``?a``, ``?_``);
  different ones that would print alike in one message are all numbered:
  ``?_{1}`` and ``?_{2}``. Braces cannot occur in a name in the source, so
  these cannot be confused with a variable or a hole of the program. A
  message where nothing clashes is printed without numbers; anonymous
  pattern variables (``_``) are never numbered; and each candidate of an
  ambiguous name is compared only with itself (``distinctNames`` in
  ``Idris.Error`` prints a message twice when names clash). A variable bound
  by the compiler is followed by ``(implicitly bound at ...)`` when it is a
  whole operand of a mismatch.
* Suggestions (``Did you mean``) never offer the definition the message is
  about, and read ``Did you mean: x?``, ``Did you mean: x or y?``, ``Did
  you mean any of: x, y, or z?``.

How terms are printed
=====================

Terms are printed with ``pshow``: holes are normalised, the term is
resugared (``Idris.Resugar``: operators, list and pair syntax, ``do``) and
printed with the syntax highlighting of code. Implicit arguments are hidden
unless ``--show-implicits`` is given, and so are the implicit binders of a
type, except those after an explicit binder that have no name the user gave
(``Type -> {_ : Type} -> Type``). Do not ``show`` a term or an ``Error``
into a message: ``show`` prints the internal form, and for an error it
prints the location again. A message that is only text around one term can
be thrown as ``GenericMsgTerm``, which prints the term this way. A warning that reports an error carries the
``Error`` (``ErrorWarning``), so that it is printed like the error.

Error codes
===========

Each kind of error and warning has a code (``errorCode`` and
``warningCode`` in ``Idris.ErrorCode``): ``E`` and four digits for an
error, ``W`` and four digits for a warning, the first two digits for the
area (``E01`` types and unification, ``E02`` names, ``E03`` elaboration,
``E04`` interface resolution, ``E05`` holes, ``E06`` coverage and patterns,
``E07`` totality, ``E08`` linearity, ``E09`` records, ``E10`` rewriting and
elaborator scripts, ``E11`` parsing, ``E12`` modules, files and packages,
``E13`` back ends, ``E14`` ``failing`` blocks). The rules:

* a code is never renumbered or given to another kind; a kind that is no
  longer reported keeps its entry, and a new kind takes the next free code
  of its area;
* an error that only gives context (``InRHS``, ``WhenUnifying``,
  ``MaybeMisspelling``, ...) has the code of the error inside it;
* internal errors and ``GenericMsg`` without a kind of their own share
  ``E0000``; give a message its own constructor (and code) when users meet
  it often;
* every code has an entry in ``registry``, with a title, and the common
  ones an explanation: what it means, an example of the mistake, and the
  usual fixes. ``idris2i-1 --explain E0101`` and ``:explain E0101`` print it,
  and ``docs/source/reference/error-codes.rst`` is printed from it
  (``idris2i-1 --list-error-codes``; the test ``idris2i-1/error/errorcodes001``
  fails when the page is out of date).

The code is printed in brackets at the end of the first line of the message
as it is displayed (``display`` and ``displayWarning``), not by
``perrorRaw``: ``failing`` blocks, JSON diagnostics (which have it as the
``code`` field) and the IDE mode do not see it, and ``--no-error-codes``
leaves it out.

JSON diagnostics
================

The fields of a JSON diagnostic beyond the message (``DiagnosticInfo``,
``diagnosticInfo`` in ``Idris.Error``) are documented in
``docs/source/tutorial/interactive.rst``. Fields are only ever added: tools
read the existing ones. ``headline`` and ``notes`` are the lines of the
message, so a change to a message changes them too; the fields with
structure (``expected``, ``got``, ``candidates``, ``related``,
``suggestions``) are computed from the error, so add to them when a message
gains details that a tool could use (a location, a name to suggest).

Regenerating and reviewing expected files
=========================================

After changing a message, run the whole suite::

    make test INTERACTIVE='' threads=6 < /dev/null

The failing tests are listed in ``tests/failures``; each has an ``output``
file next to its ``expected`` file. For each of them, read
``diff expected output`` and copy ``output`` to ``expected`` only if every
change is the one you meant. Never copy all of them unread: a test failing
for another reason looks the same in the list. Tests under ``tests/ttimp/``
print errors in their raw ``show`` form and are usually not affected. Check
``tests/idris2i-1/error/jsonerror001`` (the ``message`` field of JSON
diagnostics) and the IDE mode tests, which carry the same text. Make a
change that only touches white space or wording in many files a commit of
its own, so that it can be reviewed apart from changes of substance.
