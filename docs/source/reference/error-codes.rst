.. _sect-error-codes:

***********
Error codes
***********

.. This page is printed by `idris2i-1 --list-error-codes` from the registry in
   src/Idris/ErrorCode.idr; edit that and print it again, as the test
   idris2i-1/error/errorcodes001 compares the two.

Each kind of error and warning has a code, printed in brackets at the end
of the first line of its message (unless ``--no-error-codes`` is given), and
as the ``code`` field of JSON diagnostics (``--error-format json``). Errors
have codes ``E`` followed by four digits, warnings ``W`` and four digits;
the first two digits are the area. ``idris2i-1 --explain E0101`` (or
``:explain E0101`` at the REPL) prints the explanation of a code.

Codes are never renumbered and never given to another kind of error. A
kind that is no longer reported keeps its code, and a new kind takes the
next free code of its area.

Summary
=======

.. list-table::
   :header-rows: 1

   * - Code
     - Meaning
   * - E0000
     - An error without a code of its own (an internal error, or a message from a library or an elaborator script)
   * - E0001
     - A time limit was reached
   * - E0101
     - Type mismatch
   * - E0102
     - A constraint between two types was left unsolved
   * - E0103
     - A pattern variable stands for a value that is known
   * - E0104
     - A metavariable would have to contain itself (a cyclic solution)
   * - E0105
     - A term that is not a function is applied to arguments
   * - E0106
     - The type of an argument can't be inferred
   * - E0107
     - Universe inconsistency
   * - E0201
     - Undefined name
   * - E0202
     - A name exists, but is not in scope here
   * - E0203
     - A name is ambiguous: several definitions of it are in scope
   * - E0204
     - A definition refers to a definition that is less visible
   * - E0205
     - A definition has no type declaration
   * - E0206
     - A name is already defined
   * - E0207
     - The return type of a type constructor is not a type
   * - E0208
     - A data constructor does not return the type it belongs to
   * - E0301
     - Ambiguous elaboration
   * - E0302
     - No meaning of an overloaded name works
   * - E0303
     - The maximum depth of nested ambiguous names was exceeded
   * - E0304
     - An implicit argument can't be bound here
   * - E0305
     - Implicit arguments must be bound explicitly
   * - E0306
     - A name can't be bound implicitly with this type
   * - E0307
     - Implicit lazy functions are not supported
   * - E0308
     - An operator is used with a fixity that does not match its declaration
   * - E0309
     - Named arguments that the function does not have
   * - E0401
     - Can't find an implementation
   * - E0402
     - An implementation can't be chosen: an argument that determines it is not known
   * - E0403
     - Several implementations match
   * - E0501
     - Unsolved holes
   * - E0502
     - A named hole was solved by unification
   * - E0601
     - A definition is not covering: cases are missing
   * - E0602
     - A definition is not covering: it calls a function that is not
   * - E0603
     - An impossible clause is possible
   * - E0604
     - A pattern variable is used more than once in a pattern
   * - E0605
     - A pattern is not valid
   * - E0606
     - A dot pattern is not valid
   * - E0607
     - A case tree can't be built for the clauses
   * - E0608
     - A literal pattern has nothing to match on
   * - E0609
     - A lazy function can't be defined by pattern matching
   * - E0610
     - A pattern is more specific than its type allows
   * - E0701
     - Not total: a type is not strictly positive
   * - E0702
     - Not total: it calls a function that is not total
   * - E0703
     - Not total: a function that is not total is reachable
   * - E0704
     - Not total: possibly not terminating
   * - E0705
     - Not total: a type is matched on
   * - E0801
     - A linear variable is used more or less than once
   * - E0802
     - A variable is used with the wrong multiplicity
   * - E0803
     - A borrowed value is partially applied
   * - E0804
     - A borrowed value has a partially applied type
   * - E0901
     - The type of a record update can't be inferred
   * - E0902
     - A record update sets the same field twice
   * - E0903
     - A field is not part of the record
   * - E0904
     - A record update is applied to something that is not a record
   * - E0905
     - Field updates are not compatible with each other
   * - E1001
     - A rewrite changes nothing in the goal
   * - E1002
     - The term used to rewrite is not an equality
   * - E1003
     - An elaborator script returned a bad result
   * - E1101
     - Parse error
   * - E1102
     - Lexical error
   * - E1103
     - A literate source file can't be parsed
   * - E1104
     - A multi-line string is not laid out correctly
   * - E1201
     - Module not found
   * - E1202
     - Modules import each other in a cycle
   * - E1203
     - A compiled module (TTC file) has a format of another version
   * - E1204
     - A compiled module (TTC file) is corrupt
   * - E1205
     - A file can't be read or written
   * - E1206
     - A package can't be found
   * - E1301
     - No back end accepts a foreign specifier
   * - E1401
     - A failing block did not fail
   * - E1402
     - A failing block failed with another error
   * - W0000
     - A warning without a code of its own
   * - W0001
     - A warning from the parser
   * - W0002
     - Unreachable clause
   * - W0003
     - A name bound implicitly shadows a global definition
   * - W0004
     - A local binding shadows another
   * - W0005
     - A forward declaration and its definition have different visibilities
   * - W0006
     - Deprecated definition
   * - W0007
     - A local definition without arguments is recomputed at each use
   * - W0008
     - The universe checker could not check some definitions completely
   * - W0009
     - Imported modules were built without the universe check

Explanations
============

E0101: Type mismatch
--------------------

An expression has a type other than the one its context expects, or two types that must be the same are different. The message says which two types were compared, labelled `Expected:` (what the context needs) and `Got:` (what the expression has) when that is known, and then the part of them that differs (`Mismatch between: A and B.`).

When the two types only differ in a part that was inferred, the message says what was inferred and where (`This was postponed, and failed after inferring ...`).

.. code-block:: idris

    length : List a -> Nat

    f : List Int -> Int
    f xs = length xs        -- length gives a Nat, f must return an Int

Usual fixes:

* Convert the value: `cast (length xs)` here.
* Fix the type of the definition, if it is the type that is wrong.
* Check the arguments: a missing or an extra argument makes the type of an application differ.

E0103: A pattern variable stands for a value that is known
----------------------------------------------------------

In a pattern, a variable (or an implicit argument) must be free to match anything. When unification finds that it can only be one particular value, because of the type of another argument, the variable does not really bind anything new, and Idris2i-1 reports it.

This often happens with implicit arguments that are named in the pattern, or when an argument's type forces another one.

.. code-block:: idris

    data Vect : Nat -> Type -> Type where
      Nil  : Vect Z a
      (::) : a -> Vect k a -> Vect (S k) a

    f : Vect n a -> Nat
    f {n = m} [] = m      -- m can only be Z here

Usual fixes:

* Write the value that the variable must have (`f {n = Z} [] = 0`), or leave the argument out of the pattern.
* Use a dot pattern (`.(Z)`) to say that the argument is forced by the others.

E0107: Universe inconsistency
-----------------------------

Only with `--check-universes`. Each `Type` stands for a universe, and the universes must be ordered: `Type : Type` is not allowed, a type is in a universe above those of its parts, and the fields of a constructor are in a universe no bigger than that of their data type. The definitions checked so far need a universe to be strictly bigger than itself, through the chain of constraints that the message lists, with the place of each `Type` involved and the definition each constraint comes from. Without the check such a program can prove `Void` (Girard's paradox).

See the reference page on universe checking for what is checked.

.. code-block:: idris

    data U : Type where
      MkU : Type -> U       -- a U holds a type of the universe of U

    u : U
    u = MkU U               -- U itself is not in a smaller universe

Usual fixes:

* Read the cycle: one of its steps is usually a type stored in a data type (or interface) of its own universe, or a type used at itself.
* Make the data type a parameter of what it stores (`data U : Type -> Type`) instead of storing a `Type` in it.
* A definition is universe polymorphic only in the universes which evaluation can't produce; give a second copy of the definition if it is needed at two universes.

E0201: Undefined name
---------------------

A name is used that is not defined, or not defined in any module that is imported. The message suggests names that are spelt alike, and the modules in the build directory or in the packages in use that export a definition of that name.

.. code-block:: idris

    main : IO ()
    main = printLn (sort [3, 1, 2])     -- sort is in Data.List

Usual fixes:

* Import the module that defines it (`import Data.List`), or add the package that provides it to `depends` in the `.ipkg` file, or pass `-p` to `idris2i-1`.
* Fix the spelling.
* Define the name before it is used in a `mutual` block, or declare its type first.

E0202: A name exists, but is not in scope here
----------------------------------------------

The name is defined, but it can't be used here: it is private to the module or namespace that defines it, or it is in a module that is not imported explicitly (a module imported by an imported module is not visible unless it is imported with `import public`).

.. code-block:: idris

    -- in module A
    secret : Nat
    secret = 42

    -- in module B
    import A
    x : Nat
    x = secret      -- secret is private to A

Usual fixes:

* Export the definition: `export` makes its type visible, `public export` its definition too.
* Import the module that defines it explicitly.
* Use a function that the module exports instead.

E0204: A definition refers to a definition that is less visible
---------------------------------------------------------------

A definition that is exported can only refer, in the parts that are exported, to definitions that are exported as well: a `public export` definition can't use a private or `export` one in its body, and the type of an `export` definition can't use a private one. Otherwise a module that imports it would see a name that it can't use.

.. code-block:: idris

    data Secret = MkSecret

    public export
    reveal : Secret     -- Secret is private
    reveal = MkSecret

Usual fixes:

* Make the definition referred to visible enough (`export` or `public export`).
* Make the definition that refers to it less visible.
* Export only the type (`export` instead of `public export`) if the body need not be visible.

E0301: Ambiguous elaboration
----------------------------

An overloaded name (a name defined in several namespaces, or a literal or syntax with several meanings) has more than one meaning that type checks here, and nothing says which one is meant. The message lists the results.

.. code-block:: idris

    namespace A
      export
      val : Nat
      val = 1

    namespace B
      export
      val : Nat
      val = 2

    x : Nat
    x = val

Usual fixes:

* Qualify the name with its namespace (`A.val`).
* Give the expected type (`the Nat val`) if the meanings have different types.
* Hide one of the definitions with `%hide`.

E0302: No meaning of an overloaded name works
---------------------------------------------

Every meaning of an overloaded name (a name defined in several namespaces, a list literal, a `do` block, ...) failed to type check. The message lists the error of each meaning, the one that got furthest first; meanings that fail in the same way at the same place are listed together under one excerpt.

.. code-block:: idris

    import Data.Vect

    xs : Vect 2 Nat
    xs = [1, 2, 3]     -- both List and Vect literals fail

Usual fixes:

* Read the first error of the list: it is the meaning that came closest.
* Qualify the name (`Vect.(::)`) or give the expected type to say which meaning you want, so that its error is reported alone.
* `--candidate-error-count 0` shows all the meanings when some are left out.

E0304: An implicit argument can't be bound here
-----------------------------------------------

An implicit argument (`{x}`, `@{x}`) is given or bound where the function does not have one of that name, or in a form that is not allowed there.

.. code-block:: idris

    f : Nat -> Nat
    f {m} n = n       -- f has no implicit argument m

Usual fixes:

* Check the name of the implicit argument against the type of the function (`:t f` at the REPL).
* Bind the argument in the type first (`f : {m : Nat} -> Nat -> Nat`).

E0401: Can't find an implementation
-----------------------------------

An interface constraint (or an `auto` argument) could not be satisfied. The message says why, as far as it can be told:

* no implementation of the interface matches the type at all;

* an implementation matches, but needs another constraint that fails: the message names the implementation (by its type and where it is defined) and the chain of constraints down to the one that fails;

* the implementation that would match is not visible here;

* a local implementation (a constraint of the function, or an `auto` argument) is in scope, but for other types;

* the type is not known yet (it has a `?` in it), so no implementation can be chosen.

.. code-block:: idris

    data Colour = Red | Green

    describe : Colour -> String
    describe c = show c      -- there is no Show Colour

Usual fixes:

* Write the implementation (`Show Colour where show Red = "Red" ...`), or derive one where a deriving library is available.
* Import the module that defines the implementation.
* Add the missing constraint to the type of the function (`Show a => a -> String`) when it is about a type variable.
* Say what the type is (with a type annotation or `the`) when the message shows a `?` in the goal.

E0402: An implementation can't be chosen: an argument that determines it is not known
-------------------------------------------------------------------------------------

Some arguments of an interface determine which implementation is used (all of them, unless the interface says otherwise with `|`). If one of them is still unknown when the search runs, no implementation can be chosen, even if there is only one. The message names the argument that could not be inferred.

.. code-block:: idris

    interface Default a where
      def : a

    Default Nat where
      def = 0

    x : String
    x = show def      -- the type of def is not known

Usual fixes:

* Give the type: `show (the Nat def)`, or a type annotation on a `let`.
* Pass the implementation explicitly with `@{...}`.
* For a numeric literal, the default (`Integer`) is only used when nothing else says what the type is.

E0403: Several implementations match
------------------------------------

More than one implementation (or local constraint) satisfies an interface constraint, and the search does not choose between them. The message lists them, by their types and where they are defined; named implementations are listed by name.

.. code-block:: idris

    interface Describe a where
      describe : a -> String

    Describe Int where
      describe _ = "Int"

    [other] Describe Int where
      describe _ = "other"

    %hint
    otherHint : Describe Int
    otherHint = other

    f : Int -> String
    f = describe

Usual fixes:

* Choose one explicitly: `describe @{other}`.
* Remove the `%hint`, or one of the implementations.
* Name an implementation (`[name] Describe Int where`) so that it is only used when asked for.

E0501: Unsolved holes
---------------------

A definition still contains holes that unification could not fill: implicit arguments, or `_` that it could not infer. The message lists them with where they were introduced. (Holes written as `?name` are allowed, and do not cause this error.)

.. code-block:: idris

    f : List a -> Nat
    f xs = length []     -- the type of the elements of [] is unknown

Usual fixes:

* Give the missing value or type explicitly (`length {a = Nat} []`, `the (List Nat) []`).
* Bind the implicit argument in the type of the definition.

E0601: A definition is not covering: cases are missing
------------------------------------------------------

A definition declared `covering` or `total` (or every definition, with `%default covering` or `%default total`) does not have a clause for every possible input. The message lists the missing cases, written as patterns that can be pasted as clauses.

.. code-block:: idris

    %default total

    isZero : Nat -> Bool
    isZero Z = True

Usual fixes:

* Add the missing clauses.
* Add a final clause with a variable or `_` that covers the rest.
* If a case is impossible, write it with `impossible` so that Idris2i-1 checks it.

E0602: A definition is not covering: it calls a function that is not
--------------------------------------------------------------------

A definition that must be covering calls a function that is not covering (or is only `partial`). The call is shown, and why the function called is not covering.

.. code-block:: idris

    %default total

    partial
    first : List a -> a
    first (x :: _) = x

    f : List Nat -> Nat
    f xs = first xs

Usual fixes:

* Make the function called covering (`first : List a -> Maybe a`, for example).
* Mark the calling definition `partial` if it really is.

E0603: An impossible clause is possible
---------------------------------------

A clause marked `impossible` type checks, so it is not impossible: there are values that match it. Or the clause fails to type check for another reason than a contradiction, which the message gives.

.. code-block:: idris

    f : Nat -> Nat
    f Z impossible     -- Z is a Nat

Usual fixes:

* Write a right hand side for the clause.
* Check the pattern: the impossible case is often a different pattern than the one written.

E0608: A literal pattern has nothing to match on
------------------------------------------------

A string, numeric or character literal in a pattern, at a type other than a primitive one, stands for `fromString "..."`, `fromInteger 3`, ... of that type. The pattern can only be matched if that application reduces to a constructor applied to arguments. For some types it does not: a `ByteString` is built by a foreign function, and a type whose conversion is not `public export` does not reduce outside its module. Then there is nothing to compare the value with, and the clause (or the `case` alternative) is rejected.

This used to be accepted, and the clause then matched every value.

.. code-block:: idris

    import Data.ByteString

    route : ByteString -> String
    route "/" = "home"        -- fromString "/" is not a constructor form
    route _ = "other"

Usual fixes:

* Bind a variable and compare it with `==`: `route p = if p == "/" then "home" else "other"`.
* For a type of your own, match on its constructor (`MkName "me"`), or make its conversion `public export` so that it reduces in patterns.

E0701: Not total: a type is not strictly positive
-------------------------------------------------

A data type refers to itself to the left of an arrow in the type of one of its constructors. Such a type allows non-terminating programs to be written without recursion, so it is not total.

.. code-block:: idris

    data Bad = MkBad (Bad -> Nat)

Usual fixes:

* Change the representation so that the type only occurs to the right of arrows.
* Mark the type (and what uses it) `partial` if that is acceptable.

E0702: Not total: it calls a function that is not total
-------------------------------------------------------

A definition that must be total calls a function that is not. The message shows the call, and why the function called is not total.

.. code-block:: idris

    covering
    loop : Nat -> Nat
    loop n = loop n

    total
    f : Nat -> Nat
    f n = loop n

Usual fixes:

* Make the function called total.
* Mark the calling definition `covering` or `partial`.

E0703: Not total: a function that is not total is reachable
-----------------------------------------------------------

A definition that must be total calls, through a path of other functions, a function that is not total. The message shows the path.

.. code-block:: idris

    covering
    loop : Nat -> Nat
    loop n = loop n

    g : Nat -> Nat
    g = loop

    total
    f : Nat -> Nat
    f = g

Usual fixes:

* Make the function at the end of the path total.
* Mark the definitions on the path `covering` or `partial`.

E0704: Not total: possibly not terminating
------------------------------------------

A definition calls itself (or a cycle of definitions calls round) with arguments that are not known to get smaller. The message shows the recursive call, and how each argument compares to the pattern it must be smaller than.

.. code-block:: idris

    total
    count : Nat -> Nat
    count n = count (S n)

Usual fixes:

* Recurse on a structurally smaller argument (a variable bound inside a constructor pattern).
* Use `assert_smaller` or `assert_total` where you know the call terminates but Idris2i-1 can't see it.
* Recurse on a separate argument that decreases (a fuel argument, `Nat`).

E0705: Not total: a type is matched on
--------------------------------------

A clause takes a type apart by pattern matching, and the type is neither `Type` nor small, so the match can't be checked to terminate.

.. code-block:: idris

    total
    f : (a : Type) -> Nat
    f Nat = 0
    f _ = 1

Usual fixes:

* Pass a value that describes the type (a data type of codes) instead of the type itself.
* Mark the definition `covering`.

E0801: A linear variable is used more or less than once
-------------------------------------------------------

A variable bound with multiplicity 1 must be used exactly once in the body of its definition. The message says how many times it is used.

.. code-block:: idris

    dup : (1 x : a) -> (a, a)
    dup x = (x, x)

Usual fixes:

* Use the variable exactly once, or pass it to a function that returns what is needed of it.
* Drop the multiplicity 1 from the binder, if the value need not be linear.

E0802: A variable is used with the wrong multiplicity
-----------------------------------------------------

A variable is used in a context that needs another multiplicity: an erased (0) variable is used at run time, or a linear (1) one is passed where it may be used many times.

.. code-block:: idris

    f : (0 n : Nat) -> Nat
    f n = n       -- n is erased, it can't be returned

Usual fixes:

* Bind the variable with the multiplicity it is used at (`(n : Nat)`).
* Use it only in types or other erased positions.

E0903: A field is not part of the record
----------------------------------------

A record update (`{ field := value } r`) or a projection (`r.field`) names a field that the record type does not have.

.. code-block:: idris

    record Point where
      constructor MkPoint
      x, y : Double

    move : Point -> Point
    move = { z := 0 }

Usual fixes:

* Check the spelling of the field, and the record type it is used on.
* Give the type of the record when it can't be inferred (`the Point`).

E1101: Parse error
------------------

The source can't be parsed. The message says what was expected at the place shown; when several alternatives were tried, each is listed with its error.

.. code-block:: idris

    f : Nat -> Nat
    f x = (x + 1

Usual fixes:

* Look at the place shown and just before it: a missing bracket, a missing `=` or `->`, or a line that is not indented enough.
* Check the indentation of `where`, `do`, `let` and `case` blocks: their lines must start in the same column.

E1102: Lexical error
--------------------

The source contains characters that do not form a token: an unterminated string or character literal, a comment that is not closed, or a character that can't appear there.

.. code-block:: idris

    greeting : String
    greeting = "hello

Usual fixes:

* Close the string, the character literal or the comment.
* Escape special characters in strings (`\"`, `\\`).

E1201: Module not found
-----------------------

An imported module can't be found in the source directory, in the build directory or in any package in use.

.. code-block:: idris

    import Data.Lists      -- the module is Data.List

Usual fixes:

* Fix the name of the module.
* Add the package that provides it to `depends` in the `.ipkg` file, or pass `-p <package>` to `idris2i-1`.
* Check `sourcedir` in the `.ipkg` file, and that the file is where its module name says (`Data/Foo.idr` for `Data.Foo`).

E1202: Modules import each other in a cycle
-------------------------------------------

A module imports, directly or through other modules, itself. Modules are checked one after another, so their imports can't form a cycle. The message lists the modules of the cycle.

.. code-block:: idris

    -- A.idr
    module A
    import B

    -- B.idr
    module B
    import A

Usual fixes:

* Move the definitions that both modules need into a third module that both import.
* Merge the modules, or use `mutual` blocks within one module.

E1203: A compiled module (TTC file) has a format of another version
-------------------------------------------------------------------

A `.ttc` file was written by another version of the compiler, which stores modules in another format. This happens after the compiler is upgraded, or when the build directory or an installed package was built by another compiler.

Usual fixes:

* Remove the build directory (`rm -r build`, or `idris2i-1 --clean <package>.ipkg`) and build again.
* Reinstall the packages in use with the current compiler.
* Check that the `idris2i-1` in the `PATH` is the one the packages were installed with (`idris2i-1 --version`, `idris2i-1 --paths`).

W0002: Unreachable clause
-------------------------

A clause can never be used: the clauses before it match everything it matches. It is probably a mistake in the order of the clauses, or in a pattern (a variable where a constructor was meant: a lower case name in a pattern is a new variable, not a reference to a definition).

.. code-block:: idris

    isRed : String -> Bool
    isRed colour = False
    isRed "red" = True

Usual fixes:

* Put the more specific clause first.
* Check the patterns of the earlier clauses: a variable matches everything.
* Remove the clause if it is not needed.

W0003: A name bound implicitly shadows a global definition
----------------------------------------------------------

In a type, a lower case name that is not bound is bound implicitly, as an argument of the definition. When a global definition of that name exists, this is often a mistake: the global definition was meant, but it is a new variable. The message lists the names and the definitions they shadow.

.. code-block:: idris

    x : Nat
    x = 3

    f : Vect x Int -> Int     -- x here is a new variable, not 3

Usual fixes:

* Rename the variable, or bind it explicitly (`{x : Nat} -> ...`) if a variable is meant.
* Qualify the global name (`Main.x`) if the global definition is meant.

W0004: A local binding shadows another
--------------------------------------

A local variable (in a pattern, a `let`, a lambda) has the name of another one in scope, which is no longer accessible.

.. code-block:: idris

    f : Nat -> Nat -> Nat
    f x y = let x = y in x

Usual fixes:

* Rename one of the variables.

W0006: Deprecated definition
----------------------------

A definition marked `%deprecate` is used. It will be removed in a later version; its documentation usually says what to use instead, and is printed with the warning.

.. code-block:: idris

    import Data.SortedSet

    xs : List Nat
    xs = SortedSet.toList (fromList [1])

Usual fixes:

* Use what the documentation of the definition suggests instead.

W0008: The universe checker could not check some definitions completely
-----------------------------------------------------------------------

Only with `--check-universes`. The universe checker checks the elaborated definitions again. Some elaborated terms are not well typed as far as it can tell (the motive of a `rewrite`, for instance, is built without being checked), so it checks what it can of them, but can't claim that they are consistent, and does not make them universe polymorphic. The warning lists them; `--log universe:1` says what was not checked in each.

Usual fixes:

* Nothing needs to be done; the definitions are checked as far as possible.

W0009: Imported modules were built without the universe check
-------------------------------------------------------------

Only with `--check-universes`. The universe constraints of a module are saved in its TTC file when it is built with the option. Modules built without it contribute no constraints, so only the definitions of the modules built with it are checked.

Usual fixes:

* Build the imported modules (and the libraries they come from) with `--check-universes` too, for instance by adding it to the `opts` of their packages.

