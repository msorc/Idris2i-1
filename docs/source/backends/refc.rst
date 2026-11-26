*************************
C with Reference Counting
*************************

The default code generator compiles to an executable via C,
using a reference counting garbage collector. This is intended as a lightweight
(i.e. minimal dependencies) code generator that can be ported to multiple
platforms, especially those with memory constraints.

Performance is often not as good as with the Scheme based code generators: on
the programs of the ``benchmark`` directory, the time ranges from 0.8 to 2.5
times that of the Chez backend.  Programs that allocate many short-lived
values, or apply many closures, are the slowest, as every value is reference
counted and freed as soon as it is no longer used.  On the other hand they
usually need much less memory.  ``benchmark/refc-perf.sh`` measures them
(instructions, cycles and peak memory).  The
main goal is portability: the generated code should run on any platform that
supports a C compiler.

Small values are allocated from pages of values of the same size rather than
with ``malloc``.  The pages (64KB each) are cut from regions of 1MB to 16MB
that the program maps from the system (with ``mmap``; ``_aligned_malloc`` on
Windows), so that a page costs no memory besides its own, and one system call
serves many pages.  A page that holds no value any more can be used for values of
another size; every OS thread of the program keeps up to 16 such pages (1MB),
and gives the memory of the others back to the system (with ``madvise``; the
regions themselves are kept, for the pages to be used again).  The environment
variable ``IDRIS2I_1_REFC_KEEP_PAGES`` sets that number.  When the program runs under Valgrind, and the support library
was built with the Valgrind headers available, every value comes from
``malloc``, so that Valgrind can check them.  For other memory checkers (such
as AddressSanitizer), compile the support library and the program with
``-DIDRIS2I_1_REFC_NO_POOLS``: ``make install-support-refc-asan PREFIX=<prefix>``
installs such a support library, built with AddressSanitizer and UBSan, and the
comment at the top of ``support/refc/Makefile`` gives the flags for the
programs.

Two environment variables make a program report on its memory when it exits
(on the standard error):

- ``IDRIS2I_1_REFC_MEMSTATS=1`` prints the pages of the allocator and the values
  that they hold, by size.
- ``IDRIS2I_1_REFC_LEAKCHECK=1`` looks for the values that are still alive once
  the main expression is done, and that the constants of the program (the
  definitions without arguments, which are kept until the program exits) do
  not hold: those values leaked, from a cycle of references for example.
  ``IDRIS2I_1_REFC_LEAKCHECK=2`` also shows some of them.  The check is skipped
  when other threads still run, or when the program exits early (with
  ``exitWith``, say).  Large values (more than 256 bytes) are only counted.

The threads that still run stop before the report (at the end of an
iteration of a loop, or when they block), so that it does not look at
memory that changes under it.  When a thread does not stop within a second
(it makes a system call, say), the report is skipped.

When the support library and the program are both compiled with
``-DIDRIS2I_1_REFC_STATS`` (``IDRIS2I_1_CPPFLAGS=-DIDRIS2I_1_REFC_STATS`` for the
program), ``IDRIS2I_1_REFC_MEMSTATS=1`` also prints counts of what the program
did: allocations by size and by kind of value (constructor, closure, string,
boxed number, other), and the bytes allocated; the reference count operations
(taking a reference, dropping one, and the drops that the release of a value
makes on its fields), each by what it found (``NULL``, an unboxed value, an
immortal value, or a real count, which the report gives by kind of value and
says how many were atomic); the values released, and every value freed, by
kind and size; uniqueness tests, by kind of value and outcome; constructors
reused in place; and closure applications by kind.  Such a build is slower
(about 1.6 times the instructions), and only meant to find out where the time
goes.

This code generator can be accessed via the REPL command:

::

    Main> :set cg refc

Alternatively, you can set it via the ``IDRIS2I_1_CG`` environment variable:

::

    $ export IDRIS2I_1_CG=refc

The C compiler it invokes is determined by either the ``IDRIS2I_1_CC`` or ``CC``
environment variables. If neither is set, it uses ``cc``.  It is the name or
the path of a program (which may contain spaces), not a command line: to use
``ccache gcc``, point ``IDRIS2I_1_CC`` to a script or link that runs it.

Both ``:exec`` and ``:c`` work at the REPL: ``:exec`` compiles the expression
to a temporary executable in the build directory and runs it.

Also note that, if you link with any dynamic libraries for interfacing with
C, you will need to arrange for them to be accessible via ``LD_LIBRARY_PATH``
when running the executable. The default Idris2i-1 support libraries are
statically linked.

Directives
==========

The directives of the RefC back end, given with ``--directive`` or with
``%cg refc`` in a module (whose directives every program that imports it
gets), are:

- ``refc-lib=<names>``, ``refc-archive=<files>`` and
  ``refc-pkg-config=<names>``: what the program is linked with, see
  :ref:`sect-ffi-linking`.
- ``refc-backtrace``: backtraces, see "Backtraces" below.
- ``refc-split-size=<bytes>``: the size of C from which a program is compiled
  in units, see "Big programs".
- ``refc-no-gc-sections``: keep the code that nothing calls, see "Code that
  nothing calls".
- ``refc-no-...``, ``refc-size-reuse``, ``refc-check-layout`` and
  ``refc-no-flat-arrays``: see "Optimisations" below.

A directive that starts with ``refc-`` and is not one of these, or whose value
cannot be, is an error.  The headers of a ``%foreign "C:fn,,header.h"`` are
looked for in the support directories of the run time, in the ``lib``
directories of the packages that the program depends on, and where the flags of
the user (``IDRIS2I_1_CFLAGS``, ``IDRIS2I_1_CPPFLAGS``) and of
``refc-pkg-config`` tell.

The stamp of the executable of a package (which skips its compilation when
nothing changed, see ``--log package.stamp:5``) covers the directives, the
archives of ``refc-archive`` and the output of pkg-config: the executable is
linked again when one of them changes.

Big programs
============

A program of more than 4MB of C (the Idris2i-1 compiler itself is 140MB) is
compiled in units, by C compilers running in parallel: ``IDRIS2I_1_CC_JOBS`` of
them at once (the number of processors, up to 16, by default).  Besides
``<name>.c``, which has the whole program, the compiler writes
``<name>.u<k>.c``, one file per unit with the definitions of the unit and
only the prototypes and constants that they use, and compiles those to
``<name>.u<k>.o``.

When the program is compiled again, the object file of a unit is reused if
nothing that decides it has changed: the text of the unit (it is compared with
the file of the last compilation, not hashed), the C compiler and its version,
its flags (``IDRIS2I_1_CC``, ``IDRIS2I_1_CFLAGS``, ``IDRIS2I_1_CPPFLAGS``, ``-fpic``,
the include directories), a few environment variables that it reads (``CPATH``
and the like) and the contents of the header files of the runtime (in the
``refc`` and ``c`` support directories).  If the program includes a header
that is not one of them (``%foreign "C:f,lib,header.h"``), the C compiler is
asked (with ``-M``) which files that header is made of (the headers it
includes, and so on), and their contents count too; when it cannot tell,
nothing is reused (``--log compiler.refc.cc:2`` tells why the object files are
not reused).
The text of a unit stays the same when other parts of the program change: the
definitions are put in units by their modules (a big module in several, by the
names of its definitions), the number of units depends only on the size of the
program, constants are named after their values, and so are not renumbered when
another one is added.  Changing a module therefore compiles only the units of
its definitions again, and those that refer to something that changed.

``<name>.c`` is a single file that can be compiled by itself.  With
``-DIDRIS2I_1_PARTS=p -DIDRIS2I_1_PART=i`` the C compiler builds only the ``i``-th of
``p`` parts of it (this is how the Idris2i-1 compiler is bootstrapped).  Add
``-flto`` (or ``-flto=auto``) to the C flags to keep the inlining across units.
The units are only compiled, not meant to be read: their lines are not
indented and their prototypes are short (no names of parameters), which
makes them a quarter smaller.  ``<name>.c`` keeps the readable layout.

Functions with the same code
----------------------------

Two functions whose C code is the same but for their own names (a
specialisation of a function at types that are erased, the methods of two
implementations that do the same, ...) are written once: the other one is a
macro, ``#define Main_sumU Main_sumT``, in the prototypes.  The names of the
functions that they call count as the same when those functions are merged
themselves: once ``sumU`` is ``sumT``, a function that calls ``sumU`` is
merged with one that calls ``sumT``, and so on, in rounds until nothing
changes.  Two functions that call each other are not merged with two others
that do the same (each pair would have to be merged before the other).

In a program compiled in units, a function is replaced by one of another unit
only when it is bigger than 1,500 bytes of C, or when it is only made into
closures: the whole program never calls it by its name (nor its worker),
it only passes it around.  A small function that moved to another unit could
no longer be inlined by the C compiler where it is called; a big one is not
inlined anyway, and a call through a closure never is.  The other functions
are merged with those of their unit only.  With ``--directive
refc-backtrace`` every function is written, so that a backtrace shows the
names of the functions that ran.  ``--directive refc-no-merge-rounds`` merges
only the functions whose code is the same but for their own names (one
round), and ``--directive refc-no-merge-closures`` merges the small functions
that are only made into closures with those of their unit only.

A function written for functions of other units is written by a name made
of a hash of its code, ``idris2i_1_same_<hash>``, and the names of all of
them are macros for that one: when the one that was written is removed or
renamed, the copy moves to the unit of another one, and the units that
refer to the others are the same as before (they are compiled again only
when their text changes, see above).

Built by itself at ``-O2``, the Idris2i-1 compiler has 52.5MB of machine code
when only the functions that differ in their own names are merged, 50.0MB
with the rounds, and 49.3MB when the functions only made into closures are
also merged across units.

Code that nothing calls
-----------------------

On Unix systems other than macOS (Linux and the BSDs), every function of the
generated C is compiled in a section of its own (``-ffunction-sections``), the
runtime libraries are built with ``-ffunction-sections -fdata-sections``, and
the program is linked with ``-Wl,--gc-sections``: the linker leaves out what
the program never reaches.  A hello world keeps the parts of the runtime that
start and stop it (the scheduler, the trampolines, reference counting, the
backtrace and the memory reports at exit) and loses the others (casts,
string and arithmetic primitives that it does not use): its executable goes
from 165KB to 82KB.  A big program loses the out-of-line copies of the
functions that the C compiler inlined everywhere (0.3% of the machine code
of the compiler, and 1.4% when the functions with the same code are not
merged, see above: the two overlap).  The speed is the same.
``--directive refc-no-gc-sections`` compiles and links as before;
``IDRIS2I_1_CFLAGS=-fno-function-sections`` keeps the generated code in one
section but still lets the linker drop the unused parts of the runtime.

The runtime reaches its scheduler, its reactor and the code that shares values
between workers through function pointers that are set when the program first
needs them, so that a program that never needs them does not link them: the
loop of the scheduler is set when the program makes something that threads
block on (a channel, a mutex, ...), sleeps, waits for a descriptor or forks;
what a yield and a preemption do, and the stop of the other workers at exit,
by the first ``fork``; the poller of the reactor, by the reactor when it is made (the first
wait for a descriptor); the marking of the constants as shared, when the
second worker starts.  These calls were all on slow paths already (a yield
or a preemption, a poll, the evaluation of a constant, the exit, the making
of a channel or a mutex): the paths that run often (allocation, reference
counting, the trampoline, the safepoints, a thread that blocks or sleeps)
are the same.  A hello world loses about 10KB of machine code this way (71KB
instead of 82KB), and a program that does not fork, like the benchmarks of
``benchmark/``, 5 to 11% of its file.  What a hello world still has is what
any program may need at run time: the reports of ``IDRIS2I_1_REFC_LEAKCHECK``
and ``IDRIS2I_1_REFC_MEMSTATS`` (about 7KB) and the backtraces of
``IDRIS2I_1_REFC_BACKTRACE`` (about 6.5KB), which environment variables turn on
when the program runs, and the trampolines, the application of closures and
the allocator.

The executable keeps its symbol table, for the backtraces.  To strip it, pass
``-s`` to the linker: ``IDRIS2I_1_LDFLAGS=-s`` (a hello world is then 61KB);
a backtrace then shows ``??`` for the functions of the program.

Strings and characters
======================

A ``String`` is stored as a NUL-terminated sequence of bytes in UTF-8, so it
can be passed to C functions as a ``char *``.  As in the other backends, the
string primitives work on Unicode code points: ``length "λ"`` is ``1``, and
``unpack`` gives one ``Char`` per code point.  Bytes that are not part of a
valid UTF-8 sequence (for example in a file that is not UTF-8) are read as
``U+FFFD``, one byte at a time.  Because indexing a UTF-8 string has to walk
it, ``strIndex``, ``substr`` and ``length`` take time linear in the length of
the string.

A ``Char`` holds a full code point.  Casting a number that is not a Unicode
scalar value to ``Char`` gives ``'\0'``.  A ``Char`` passed to a C function
through the FFI is still a C ``char``.

A string stores its length, so it may contain the NUL character.  It is also
followed by a NUL, so a C function receives a usual C string, which ends at
the first NUL character of the Idris2i-1 string.  Reading a line from a file
(``fGetLine``) also stops at a NUL character.

``show`` prints a ``Double`` like the Chez backend: the shortest digits that
read back as the same number (``0.1``, ``1e-10``, ``+inf.0``).

The ``C`` and ``RefC`` calling conventions pass strings differently.  With
``%foreign "C:f"``, a ``String`` argument is a ``char *``, and a ``String``
result is a ``char *`` (or a ``const char *``) that the generated code copies
and never frees, as in the other backends (so it may be a literal or a static
buffer, like the result of ``getenv``; a string that the caller must free is
leaked, see below).  The ``char *`` of an argument points into the Idris2i-1
string: it is only valid until the function returns, and must not be changed.
With ``%foreign "RefC:f"``, a ``String`` is an Idris2i-1 value
(``Idris2i_1_Value *``, an ``Idris2i_1_String`` with its length ``len`` and its
bytes ``str``), like ``Integer`` and foreign objects: the arguments are
borrowed, a result is a new reference (``idris2i_1_mkStringN`` makes one).
A string must not be changed once other code has seen it: the runtime keeps
the number of its characters (``codePoints``), counted the first time that it
is needed.

A ``Struct`` of ``System.FFI`` is a pointer to a C ``struct`` that C code
owns, passed to and returned from foreign functions as a ``void *``.
``getField`` and ``setField`` read and write its fields in place.  As in the
Chez backend, the layout is that of the C ``struct`` whose fields have the C
types of the fields of the Idris2i-1 type, in order: ``Int`` is ``int``, ``Char``
is ``char``, ``Double`` is ``double``, ``Int8`` to ``Bits64`` are ``int8_t``
to ``uint64_t``, ``Ptr t`` and ``AnyPtr`` are ``void *``, and a ``Struct`` is
a *pointer* to that struct (a struct that C nests by value cannot be
described).  The generated C defines these structs itself, with names of its
own, so no header is needed and a header that defines them does no harm.
The compiler reports a struct with a field of another type, and two
``Struct`` types of the same name with different fields.  The fields of a
struct are known when a ``%foreign`` function of the program has the struct
in its type, and the names of the struct and of the field must be known
where ``getField`` or ``setField`` is used (not in a function that works for
any struct name): the compiler reports the other uses.

Memory
======

A value is freed as soon as its last reference goes away.  There is no
collector of cycles: values that refer to each other are never freed.  In
Idris2i-1, a cycle can only be made through a mutable value: an ``IORef`` or an
array that holds a value that refers to it, a closure stored in an ``IORef``
that refers to that ``IORef``, or the finaliser of a ``GCPtr`` (see
``onCollect``) that refers to the pointer itself.  ``IDRIS2I_1_REFC_LEAKCHECK=1``
(see above) finds such values in a test run.

The definitions without arguments (constants, like ``primes : List Integer``)
are evaluated once, the first time that they are needed, and kept until the
program exits, with all the values that they refer to.

The count of references of a value is 16 bits; the references beyond that are
counted in a table on the side, so a value with very many references is still
freed in the end.

A function, and so a closure, has at most 65535 arguments, and a constructor at
most 65535 fields: the compiler reports a program with a bigger one.

Ownership through the FFI
-------------------------

A plain ``Ptr`` is not managed: free what it points to, or use a ``GCPtr``
(``onCollect``).  A C function that returns a string from ``malloc`` must not
be given the result type ``String``, which copies the string and leaves the
buffer alone: declare its result as a ``Ptr String``, convert it and free it
(the way that works with every backend, see "Returning a string that the
caller frees" in :ref:`sect-ffi-string`), or go through a ``RefC`` wrapper that
calls ``idris2i_1_mkStringOwned``, which copies the string and frees it.
A foreign function is called without taking a reference to its arguments (they
are *borrowed*): C code that keeps an argument beyond the call, in a data
structure of its own say, takes a reference with ``idris2i_1_newReference`` and
releases it with ``idris2i_1_removeReference``.  That is for the Idris2i-1 values of
the ``RefC`` calling convention; the ``char *`` of a ``String`` argument of the
``C`` convention has no reference to take, so C code that keeps it copies it.  The same holds for the Idris2i-1
functions that the compiler found to only look at some of their arguments
(see below), which matters for C code that calls the generated functions
directly.

An Idris2i-1 function passed to a foreign function is not a C function pointer
but the closure itself, an ``Idris2i_1_Value *``, which C applies to one argument
at a time with ``idris2i_1_apply_closure`` (the call consumes a reference to the
closure and one to the argument, so take a new reference with
``idris2i_1_newReference`` to a closure that is applied again; the result is a
new reference).
A library that wants a function pointer therefore needs a ``RefC:`` wrapper
with a C function of its own that applies the closure, kept with
``idris2i_1_newReference`` for as long as the library may call it. Such a
function must be called by the OS thread that runs the Idris2i-1 code (in the
foreign call, or later from a call that Idris2i-1 makes): a thread that C started
would use the memory of the main thread of the run time.

A foreign function cannot return a function: the compiler reports it (return a
``Ptr`` or ``AnyPtr`` instead).

Optimisations
-------------

The code generator does the following, each of which a directive turns off
(``--directive refc-no-...``), for measurements or to find the culprit of a bug:

- ``refc-no-borrow``: the parameters that a function only looks at are
  borrowed: the caller keeps its reference, and no reference is taken and
  released around the call.
- ``refc-no-direct-results``: the calls of the functions that always return a
  value (rather than a call left to the trampoline of their caller) are not
  trampolined.
- ``refc-no-exact-rebuild``: a branch of a ``case`` that builds again the
  value it matched, the same constructor with the fields that the branch
  bound in the same order (``Left e => Left e`` in the bind of a monad of
  ``Either``, where the types of the two differ), gives the value itself: it
  neither takes the cell over when it is unique nor copies it when it is not.
  The constructors are the same when their names and tags are, which fixes
  the layout of the fields (raw fields included); an erased value written in
  the constructor is not taken for a field, and constructors without fields
  are left alone.  This is only done where it is less work on every path:
  when the branch uses neither the fields nor the value anywhere else, and
  the constructor is its result or the value of a ``let`` that leads to it,
  not inside a ``case`` of the branch.  (In ``merge (x :: xs) (y :: ys) = if
  x < y then x :: merge xs (y :: ys) else ...``, giving the second list for
  ``y :: ys`` would keep it alive in both paths, which take over both cells
  now.)
- ``refc-no-local-closures``: a closure that a function makes and applies only
  once is not made: the application is a call.
- ``refc-no-merge-rounds`` and ``refc-no-merge-closures``: see "Functions
  with the same code" above.
- ``refc-no-workers``: a function whose parameters of a fixed width integer
  type (``Int``, ``Bits64``, ...) are C integers in its body, or whose result
  is one that it computes, has a second C function, its worker, that takes
  and gives these C integers; its calls by name call the worker, so that the
  integers are not boxed (allocated, for those that do not fit in 32 bits) by
  the caller and unboxed by the callee.  The closures and partial
  applications of the function call the function itself, which calls the
  worker.  The types are read through aliases (``Hash = Bits64``) and
  newtypes over these types (a ``record`` with one field of such a type).  A
  function in ``IO`` whose actions take the world (``f x = do ...``) has a
  worker too: it takes the world as its last parameter, and gives the result
  of the action as a C integer.  So does a function in ``IO`` whose body
  gives its action without a bind first (``loop acc n = if n == 0 then pure
  acc else loop ...``), which the compiler gives the world as a parameter
  when what the body computes before its action is cheap.  (When it is not,
  ``f x = let y = expensive x in pure y``, the function gives an action: its
  worker takes the integers but gives the action.)  A foreign function of
  C (``C:`` or ``RefC:``) that takes or gives fixed width integers has a
  worker too, which passes the C integers to the C function and gives its
  result as it is: a pure foreign read such as ``getBufferUInt8`` in a loop
  is a call of the C function (an inline one for the reads of a ``Buffer``,
  see ``buffer.h``), with no value made for the index or the byte, and no
  reference count changed.  Its other arguments are borrowed.  (This is not
  turned off by the directive, which is about the Idris2i-1 functions.)
- ``refc-no-unbox-double``: the ``Double`` values that the primitives compute
  (arithmetic, comparisons, ``sqrt``, ``exp`` and the other functions of
  ``Double``, the casts to and from the integer types) are C doubles while
  they go from one primitive to another, as the fixed width integers are:
  a value is made (allocated) only where one is needed, to be stored in a
  constructor or a closure, or passed to a function that takes it as a
  value.  The parameters and results of type ``Double`` cross the calls as C
  doubles, by the workers of the functions (see ``refc-no-workers``), and so
  do those of the foreign functions of C that take or give a ``double``.
  The results are those of the values: the arithmetic of C on doubles, with
  each result rounded to a double (on a 32 bit x86 without SSE2 too, see
  ``IDRIS2I_1_DOUBLE`` in ``mathFunctions.h``), and the casts of the runtime.
- ``refc-no-cycle-safepoints``: the functions that call each other in a
  cycle, or call themselves other than in tail position, have no safepoint
  at their start (see `Green threads`_); a thread that computes in them
  cannot be preempted then.  For measurements: the safepoints cost about
  0.4% more instructions to the compiler.
- ``refc-no-trmc``: a function that makes a cell of a call to itself
  (``map f (x :: xs) = f x :: map f xs``) loops instead of recursing: it makes
  the cell first, with a hole for the result of the call, so that it needs no
  stack for a long list (tail recursion modulo cons).

- ``refc-no-static``: a closure that holds no argument yet (a function passed
  as a value), and a constructor whose fields are all such values, constants
  or other static constructors (the dictionary of an implementation), are
  data of the C program instead of values allocated every time.  In a branch
  of a ``case`` that matched a constructor without fields, the value is known
  to be such data (or ``NULL``): no reference to it is taken or dropped.
- ``refc-no-multi-reuse``: a branch that matches several cells of the same
  constructor (the merge of two lists matches a cons cell of each) keeps all
  of them for the constructors that it builds, instead of the first one only
  (the others are freed, and the constructors allocate new cells).
- ``refc-no-reuse-copy``: the cell of a value that a branch does not use any
  more, kept for a constructor of the branch, is the value itself when it is
  unique, and otherwise a new cell with references to the fields, made where
  the uniqueness test fails: the branch then goes on the same way in both
  cases, without a test of its own, and the constructor does not store again
  the fields that it leaves where they are.  With the directive, the
  constructor allocates a cell (and stores every field) when the value was
  not unique.
- ``refc-no-raw-fields``: the fields of a constructor whose type says that
  they always hold a ``Double``, an ``Int``, an ``Int64`` or a ``Bits64``
  (a field of that type, or of a newtype of it; see ``Core.FieldRep``) are
  stored in its cell as C numbers, after the fields that are values, instead
  of being values themselves (a ``Double`` is a cell of its own otherwise):
  a record of four ``Double`` is one cell instead of five.  A field is read
  as a C number, and a constructor is built from C numbers, with no value
  made where none is needed (see ``refc-no-unbox-double``).  Code that
  reads the fields of such a cell in C (through ``AnyPtr``, say) must use
  ``idris2i_1_rawField`` (see ``memoryManagement.h``): ``total`` counts the
  fields that are values only.  A ``believe_me`` between two data types
  whose constructors lay their fields out differently is undefined
  behaviour, as it is between types that the enumeration and newtype
  optimisations represent differently; ``--directive refc-check-layout``
  makes every match on a constructor test that the cell has its number of
  fields that are values, and stop with a message otherwise.
  The design is in :doc:`refc-flat-layout`.  A constant with such fields,
  whose fields are literals, is static data of the program.

In a program that uses the flat arrays (that reaches
``Data.IOArray.newFlatArray``, ``readFlatArray`` or ``writeFlatArray``, or
the linear arrays of ``Data.Linear.Array.Flat``), RefC stores the elements
of the arrays made by ``newFlatArray`` inline: for the primitive numbers and ``Char``,
and for the records of one constructor whose fields are all stored raw (for
which the compiler makes the ``Flat`` implementation, see
``Data.IOArray.Flat``), each slot is a word that tells whether it is empty,
then the element.  ``readFlatArray`` and ``writeFlatArray`` access them
inline; the other functions of ``Data.IOArray`` read and write them through
values.  In the functions that access them, an element read is its fields,
as C numbers, and one written is written from its fields
(``Compiler.RefC.FlatOpt``), so that no value is made for it where it is
only looked at (see :doc:`refc-flat-layout`).  A program that does not use
them is compiled as it would be without flat arrays (the same C).
``--directive refc-no-flat-arrays`` turns them off: the flat arrays are then
arrays of values.  ``--directive refc-flat-arrays``, which turned them on
when they were opt-in, is accepted and changes nothing (a program that does
not use them has no array with a layout).

- ``refc-no-lazy-constants``: an expression that occurs several times inside
  delayed code is a constant like the other repeated expressions, evaluated
  the first time that it is needed, instead of a delayed constant that is
  evaluated again every time that it is forced.

The reference counting of immortal values (the static values, the constants
of a program) is tested in line, which saves calls of the runtime.  Compiling
the C code with ``-DIDRIS2I_1_REFC_SMALL_CODE`` (in ``IDRIS2I_1_CFLAGS``) leaves that
test to the runtime: the code is about 10% smaller and compiles as much
faster, and runs a few percent slower.

A call in tail position is a jump when the C compiler can make one: with GCC
15 or later (``__attribute__((musttail))``; not with Clang), when the callee
takes no more arguments than the caller, or no more than are passed in
registers (6 on x86-64, 4 on x86-64 Windows, 8 on AArch64 and RISC-V 64).  Otherwise the call is left to the
trampoline of the caller, which costs more but needs no support from the C
compiler.  It is always the trampoline on 32 bit x86 and ARM, which pass
arguments on the stack, where GCC cannot make every such call a jump.  Two macros, given in ``IDRIS2I_1_CPPFLAGS`` or ``IDRIS2I_1_CFLAGS``,
change this: ``-DIDRIS2I_1_NO_MUSTTAIL`` makes no jumps at all, and
``-DIDRIS2I_1_MUSTTAIL_REG_ARGS=0`` only the jumps to functions that take no
more arguments than their caller.

Two macros change how green threads (see below) are run:
``-DIDRIS2I_1_SINGLE_WORKER``, given to both the support library and the
program, runs every green thread on the main OS thread, without starting
other OS threads; ``-DIDRIS2I_1_USE_UCONTEXT``, given to the support library,
switches between green threads with ``swapcontext(3)`` instead of the
hand-written code for x86-64 and AArch64.

The cell of a value that is not used any more, and that nothing else refers
to, is reused in place for a new value of the same constructor.
``--directive refc-size-reuse`` reuses it for any constructor with as many
fields; it is off by default, as the code that it gives makes GCC very slow
on some big functions.

Code that is generic in an interface (``Ord a => ...``) applies the closures of
a dictionary for every method call.  The (experimental) compiler option
``--spec-interfaces`` makes copies of the small or recursive functions that
take implementations, for the implementations that are known where they are
called, as if they were declared ``%spec`` on them (see
:doc:`../reference/pragmas`): the copies call the methods directly.  It costs
compile time (checking the compiler takes 1.1 times the instructions, and
some of its modules 3 times; building the libraries 1.07 times), and makes a
big difference for code that uses ``compare`` or ``(<)`` of a known type a lot (a
tree sort of ``Integer``\ s runs with 38% fewer instructions).

Backtraces
==========

A program that dies of a fatal error can print the functions that it was
in, the innermost first, on the standard error after the message of the error.
This works for ``idris_crash``, a missing case in ``partial`` code, a division
by zero, a missing foreign function, and the signals ``SIGSEGV``, ``SIGBUS``,
``SIGFPE``, ``SIGILL`` and ``SIGABRT`` (raised by foreign code, or by a stack
overflow), on any green thread:

::

    $ idris2i-1 --directive refc-backtrace -o prog Main.idr
    $ ./build/exec/prog
    ERROR: Unhandled input for Main.name at Main:13:1--13:17
    Backtrace of the main thread, innermost call first:
      Main.name (Main:11:1)
      Main.describe (Main:16:1)
      Main.main (Main:33:1)

A program killed by a signal prints what caused it first, and still dies of
the signal (here a profile of the ``mergeInt`` benchmark, interrupted by a
``kill -SEGV``):

::

    RefC: segmentation fault (SIGSEGV)
    Backtrace of the main thread, innermost call first:
      Prelude.Types.List.reverseOnto (Prelude.Types:553:3)
      Data.List.7787:8508:splitRec (Data.List:760:5)
      _PE.PE_sortBy_ac12a6c39c600e8e, 13 frames
      Main.doSort (mergeInt:17:1)
      Main.{doSort:3} (mergeInt:17:1)

- ``--directive refc-backtrace`` puts a table of the functions of the program
  in it: their C names, their Idris2i-1 names and where they are defined (where
  their declaration begins, pragmas included), and turns the backtraces on by
  default.  It also compiles every function with ``noinline``, so that every
  call that is not in tail position has a frame of its own.
- The environment variable ``IDRIS2I_1_REFC_BACKTRACE`` turns them on (``1``) or
  off (``0``) when the program runs, with or without the directive.  Without
  it, the frames show the C names of the functions (``Main_describe``).

The stack is walked by the unwinder of the C compiler (with the ``.eh_frame``
tables that GCC and Clang write in every binary), and the return addresses are
looked up in the symbol table of the executable, which the program reads from
``/proc/self/exe``: none of this costs anything until a fatal error happens,
and a program runs the same code with backtraces on or off.  A program whose
symbols were removed (``strip``) only shows its exported functions.  What a
backtrace does not show:

- the calls in tail position: a jump (with GCC 15 or later) or a call made by
  the trampoline of the caller leaves no frame;
- without the directive, the functions that the C compiler inlined (the
  ``noinline`` of the directive made no measurable difference to the
  benchmarks of ``benchmark/``: within 0.04% of their instructions); and, with
  or without it, the functions that the Idris2i-1 compiler inlined (``%noinline``
  keeps a function);
- where in a function the call is: only the line where the function is
  defined.

Inside a crash boundary (see `Crash boundaries`_), the backtrace of a crash
that the boundary catches is not printed: the boundary gets it as text, from
the crash down to the boundary.

The frames of foreign C functions show their C names, and those of shared
libraries the name of the library (``malloc [libc.so.6]``); the frames of the
runtime are left out.  A deep stack (that of a stack overflow) shows its 48
innermost frames and its 12 outermost ones, with consecutive frames of the same
function on one line (``Main.depth (Main:8:1), 48 frames``); the stack is not
walked beyond 5 million frames (which takes about a second).  A stack overflow
is reported on an alternate signal stack, which every OS thread of the program
gets when backtraces are on; the program then dies of the signal, as it would
without the backtrace.

On Linux, the backtrace is printed without allocating memory, by functions
that can be called in a signal handler, but for the unwinder (which glibc's own
``backtrace(3)`` relies on too, and which is called once at startup so that it
is ready) and ``dladdr(3)`` for the frames of shared libraries (which takes a
lock of the dynamic loader: a crash in ``dlopen`` would hang).  On macOS and
the BSDs, only the exported functions of the executable are found (with
``dladdr``); on Windows and WebAssembly there are no backtraces.

Profiling with perf
-------------------

``perf`` profiles RefC programs well, as they are C programs: the functions of
the program are those of the Idris2i-1 program, with their C names.  Compile it
with ``--directive refc-backtrace`` to see their Idris2i-1 names (the
``noinline`` of the directive also keeps the functions apart in the profile,
at the cost of a few percent), and with ``-g`` in ``IDRIS2I_1_CFLAGS`` for
``perf annotate`` to show the C source:

::

    $ IDRIS2I_1_CFLAGS=-g idris2i-1 --directive refc-backtrace -o prog Main.idr
    $ perf record -g ./build/exec/prog
    $ perf report --stdio --no-children | IDRIS2I_1_REFC_DEMANGLE=1 ./build/exec/prog

With ``IDRIS2I_1_REFC_DEMANGLE`` set, the program does not run: it copies its
standard input to its standard output, with every C name of one of its
functions replaced by the Idris2i-1 name (``Main_describe`` and
``Main_describe.cold``, a part of it that GCC moved away, become
``Main.describe`` and ``Main.describe.cold``).  This works on the output of
``perf report``, ``perf script`` or ``perf annotate``, and of any other
tool that prints C names.  The C names are mostly readable by themselves: the
namespace and the name are joined by ``_`` (``Data_List_sortBy``), and the
characters that C does not allow are spelt out (``Prelude_EqOrd__eq_eq_Eq_Int``
is ``==`` of ``Eq Int``); ``Main_f_0`` is ``Main.{f:0}``, a function that the
compiler made of a part of ``Main.f`` (a lambda, a ``where`` block),
``n__...`` nested functions and ``case__...`` case blocks.  The functions of
the runtime begin with ``idris2i_1_``.

Building Idris2i-1 with RefC
============================

The compiler can itself be compiled with RefC, which gives a way to bootstrap
it with only a C compiler: ``make bootstrap-c`` (see ``INSTALL.md``).  A
compiler built this way has no Chez Scheme evaluator, so ``:set eval scheme``
reports an error.

The C code of the compiler is big, and compiling it takes most of the time of
a build.  A plain ``make`` compiles it with ``-O1``, which is quick.
``make LTO=1`` compiles it with ``-O2`` and link time optimisation (when the C
compiler has it), which makes the compiler about 4% faster and the C build
about twice as long; ``make bootstrap-c`` does that for the compiler that it
leaves for installing (``make bootstrap-c LTO=0`` does not).  ``IDRIS2I_1_CFLAGS``
or ``CFLAGS`` replace these flags.

Extending RefC
==============

RefC can be extended to produce a new backend for languages that support C
foreign functions. For example, a
`Python backend for Idris <https://github.com/madman-bob/idris2-python>`_.

In your backend, use the ``Compiler.RefC`` functions ``generateCSourceFile``,
``compileCObjectFile {asLibrary = True}``, and
``compileCFile {asShared = True}`` to generate a ``.so`` shared object file.

.. code-block:: idris

    _ <- generateCSourceFile defs cSourceFile
    _ <- compileCObjectFile {asLibrary = True} cSourceFile cObjectFile
    _ <- compileCFile {asShared = True} cObjectFile cSharedObjectFile

To run a compiled Idris2i-1 program, call the ``int main(int argc, char *argv[])``
function in the compiled ``.so`` file, with the arguments you wish to pass to
the running program.

For example, in Python:

.. code-block:: python

    import ctypes
    import sys

    argc = len(sys.argv)
    argv = (ctypes.c_char_p * argc)(*map(str.encode, sys.argv))

    cdll = ctypes.CDLL("main.so")
    cdll.main(argc, argv)

Extending RefC FFIs
-------------------

To make the generated C code recognize additional FFI languages beyond the
standard RefC FFIs, pass the ``additionalFFILangs`` option to
``generateCSourceFile``, with a list of the language identifiers your backend
recognizes.

.. code-block:: idris

    _ <- generateCSourceFile {additionalFFILangs = ["python"]} defs cSourceFile

This will generate stub FFI function pointers in the generated C file, which
your backend should set to the appropriate C functions before ``main`` is
called.

Each ``%foreign "lang: foreignFuncName, opts"`` definition for a function
will produce a stub, of the appropriate function pointer type. This stub will
be called ``cName $ NS (mkNamespace lang) funcName``, where ``funcName`` is the
fully qualified Idris2i-1 name of that function.

So the ``%foreign`` function

.. code-block:: idris

    %foreign "python: abs"
    abs : Int -> Int

produces a stub ``python_Main_abs``, which can be backpatched in Python by:

.. code-block:: python

    abs_ptr = ctypes.CFUNCTYPE(ctypes.c_int64, ctypes.c_int64)(abs)
    ctypes.c_void_p.in_dll(cdll, "python_Main_abs").value = ctypes.cast(abs_ptr, ctypes.c_void_p).value

Green threads
=============

The RefC backend supports concurrency through *green threads*: user level
threads that the runtime runs on a pool of OS threads, the *workers*.
Switching between green threads is done by a few lines of assembly on x86-64
and AArch64, and with ``swapcontext(3)`` on the other POSIX systems (which is
slower, as it makes a system call on every switch).  Green threads are only
supported on POSIX systems (Linux, macOS and the BSDs) for now.  On Windows and WebAssembly the backend still builds and runs programs,
but forking a thread reports an error.

The ``fork`` and ``threadWait`` functions of ``Prelude.IO``, as well as the
whole of ``System.Concurrency`` (mutexes, condition variables, semaphores,
barriers, channels and thread local data), are implemented in terms of green
threads.  The synchronisation objects behave like their counterparts in the
Chez backend (mutexes are recursive, a channel of ``makeChannel`` holds at
most one value, and a forked thread inherits the thread local data of its
parent), but they are implemented by the RefC scheduler rather than by the
operating system.  The channels of ``makeBufferedChannel n`` hold up to
``n`` values, and the ones of ``makeUnboundedChannel`` any number; they are
the same ``Channel`` type, and a thread that waits for one of them gives up
its worker like a thread that waits for a channel of one value.

The atomic operations of ``Data.IORef`` (``atomicModifyIORef``,
``atomicModifyIORef_`` and the compare-and-swap ``casIORef``) are made of a
compare-and-swap of the value in the ``IORef``, under the lock that guards a
shared ``IORef`` (see below).  A ticket of ``readForCAS`` holds a reference
to the value that it read, so that value cannot be freed while the ticket
lives, and the swap compares addresses: it succeeds when the ``IORef``
holds that very value (or, for the values that are not allocated, such as
small integers, the same one).  ``atomicModifyIORef`` runs its function with
no lock held, and runs it again when another thread wrote the ``IORef`` in
the meantime.

A program has a single worker until it forks its first thread.  Then there
is one worker per processor, or as many as the ``IDRIS2I_1_WORKERS``
environment variable says (``IDRIS2I_1_WORKERS=1`` runs every green thread on
the main OS thread).  The green threads run in parallel, one per worker at a
time: a worker with nothing to run takes threads from a busy one.  A thread
that wakes another one up (by putting a value in a channel, say) leaves it to
run next on the same worker, so that threads that pass values back and
forth do not need the operating system to switch between them.

Within a worker, scheduling is mostly *cooperative*: a green thread runs
until it blocks on a synchronisation object, sleeps, forks a thread, or
finishes.  A thread that has run for more than 10ms while other threads wait
for its worker yields at its next safepoint (the end of an iteration of a
loop, or the start of a function that is in a cycle of calls: functions
that call each other, or a function that calls itself other than in tail
position).  So does a thread that runs while the sleep or the timed wait of
another one is over and every worker is busy, so that the other one wakes
up in time.  ``IDRIS2I_1_PREEMPT=0`` turns both off.  With a single worker,
threads are only preempted for the threads whose sleep or timed wait is
over, which then run first.  This has a few consequences:

* A thread that computes in a cycle made only of calls of closures that
  are not in tail position (a recursion through the methods of an
  interface, say) has no safepoint, and keeps the other threads of its
  worker waiting until an idle worker takes them over.

* A program built with ``-DIDRIS2I_1_SINGLE_WORKER`` has no safepoints at all
  (nor a monitor): its threads are never preempted, so a thread that
  computes keeps every other one waiting, a server's among them.  Run a
  server with ``IDRIS2I_1_WORKERS=1`` instead, which preempts.

* A blocking system call, such as reading from standard input, blocks the
  worker that makes it, but not the others.  A thread can wait for a file
  descriptor without blocking its worker instead (see `Waiting for file
  descriptors`_).  The ``sleep`` and ``usleep``
  functions of ``System`` are implemented in terms of the scheduler, so the
  other green threads keep running while a thread sleeps.

* Like in the Chez backend, the program ends when the main expression is
  done: the threads that are still running, sleeping or blocked are
  abandoned.  Use ``threadWait`` to wait for a thread to finish.  If every
  thread is blocked forever while the main expression is still running, the
  program reports a deadlock and exits with an error.

* The arguments of a function are evaluated before the call, so in
  ``fork (channelPut ch (work x))`` the work is done by the parent, before
  the thread starts.  Write ``fork (do pure (); channelPut ch (work x))`` to
  do it in the new thread.

The futures of ``System.Future`` (in ``contrib``) are green threads too:
``fork`` starts a thread that computes the value, and ``await`` waits for
it, like ``threadWait``.  On the platforms without green threads, the value
of a future is computed when the future is made.

The random numbers of ``System.Random`` (in ``contrib``) come from a
generator of the support library (xoshiro256**) that the threads of the
program share.  It is seeded from the clock the first time that it is used,
unless the program called ``srand``; after ``srand``, a program that draws
its numbers from a single thread gets the same ones every time.

Values are reference counted.  A value that only one thread can see is
counted with plain increments and decrements; once a value is handed over to
another thread (it is captured by the action of ``fork``, put in a channel,
or written to an ``IORef`` or an array that other threads can see), it and
everything it refers to become *shared*, and their counts are updated
atomically.  Shared values are never updated in place.  A shared ``IORef``
is read and written under a spin lock of its own: a reader takes a
reference to the value while the lock keeps a writer from replacing and
dropping it in the meantime.  Every worker
allocates from memory of its own, without locks.  The generated code finds
the worker of its OS thread, at every allocation, with one instruction on
x86-64 (a thread local variable of the local exec model, which only an
executable can have); code compiled with ``-fpic``, as the runtime and a
program built as a library are, uses the initial exec model, which works in
shared libraries too.

Much of the library is not tail recursive (``map``, ``++``, ``sort``, ...),
so working on a long list needs a deep stack.  Like in the Chez backend,
where the stack grows as needed, the main expression runs on a large stack
of its own: 4GB on 64-bit systems and 64MB on the others, which can be
changed with the ``IDRIS2I_1_MAIN_STACK_SIZE`` environment variable (in bytes).
The memory is only used as the stack grows, and ``ulimit -s`` does not apply
to it.  If the stack cannot be allocated, the main expression runs on the
stack of the process.

Every forked thread gets a stack of its own too.  The size of these stacks
defaults to 8MB, which matches the stack of a typical process, and can be
changed with the ``IDRIS2I_1_THREAD_STACK_SIZE`` environment variable (in bytes,
at least 65536).  Every stack is followed by a guard page, so that a stack
overflow crashes the program rather than corrupting its memory.

Crash boundaries
----------------

``System.Crash.catchCrash act`` (in ``base``) runs ``act`` in a *crash
boundary*: a crash of the green thread inside it ends the action instead of
the program, and ``catchCrash`` returns what happened, a ``CrashInfo`` with
the kind, the message and, when backtraces are on, the backtrace as text
(down to the boundary).  ``crashesCaught`` counts the crashes caught.  The
HTTP server of the ``http`` library runs every handler in one.

What is caught, and why:

- ``idris_crash`` and a missing case of compiled code (``Unhandled input
  for``, from ``idris2i_1_crash``), a hole or an impossible case (from
  ``idris2i_1_crashMsg``): raised by the code of the thread, never under a lock
  of the runtime.
- An access out of a ``Buffer`` (``idris2i_1_bufferRangeError``): the check comes
  before the access.
- The failed checks of the support code (``idris2i_1_crashCheck``): a division by
  zero, an invalid length of an array or a buffer, an ``Integer`` shifted too
  far, a mismatch found by ``--directive refc-check-layout`` (found when the
  value is matched, before its fields are read).

What stays fatal inside a boundary, and why:

- A crash in a finaliser (``onCollect``): a finaliser runs at any release,
  those of the runtime under its spin locks included.
- A crash of another thread, one forked inside the boundary say: a boundary is
  for its own thread.
- A stack overflow (``SIGSEGV`` on the guard page) and the other signals
  (``SIGSEGV``, ``SIGBUS``, ``SIGFPE``, ``SIGILL``, ``SIGABRT``): they may come
  in the allocator, in ``malloc`` or under a lock, and nothing says that what
  they interrupt can be abandoned.
- Out of memory, a broken invariant of the runtime (``IDRIS2I_1_REFC_VERIFY``), a
  failure of the scheduler, a deadlock, a missing foreign function: the state
  of the runtime may be wrong.
- A ``Mutex`` released by a thread that does not hold it, a ``conditionWait``
  without the mutex: the synchronisation of the program is broken.
- ``exit`` and ``exitWith`` exit, as asked.

The boundary is a ``sigsetjmp`` on the stack of the thread (in
``support/refc/crash.c``), and a crash that it catches jumps back to it with
``siglongjmp``: the C frames in between are abandoned.  This is sound because
a crash is a call made by the thread itself: the thread is running (not
parked, not waiting for a descriptor or a deadline), holds no lock of the
runtime and is not in the allocator, and it goes on after the boundary, so its
state in the scheduler stays consistent (it may have moved to another worker
since the boundary started: it is the same stack).  A constant (a definition
without arguments, which the first thread that needs it evaluates while the
others wait) whose evaluation crashed is given back to the other threads,
which evaluate it themselves.

What a caught crash leaves behind:

- the values that the abandoned code held are never released: the closure of
  the action (about 50 bytes), and what the code still needed when it
  crashed (a handler of the HTTP server that crashes while it still needs its
  request leaks it: about 400 bytes for a small request, measured with
  10,000 crashes; one that is done with it leaks about 50 bytes).  Nothing
  reclaims them; a long-running program can watch ``crashesCaught``;
- a ``Mutex`` that the code held stays held, by the thread of the boundary
  (which may release it); other threads that wait for it wait on;
- what the code wrote to ``IORef``\ s, arrays, buffers and files stays
  written.  A value updated in place had one reference, that of the code that
  updated it, so nothing outside the boundary sees it half done;
- a crash in an Idris2i-1 callback of a C library abandons the frames of the
  library too.

A program that does not use ``catchCrash`` runs as before: a crash prints its
message and exits with the same code.  The cost of a boundary is a
``sigsetjmp`` (which does not save the signal mask) and a few stores in C,
plus the closure that runs the action and the ``Right`` of its result: about
400 instructions in a loop that does nothing else, and 90 per request (0.4%)
for the ``hello`` route of ``benchmark/http`` (HTTP/1.1, one worker), whose
handler was a closure call already.  Nothing changes for code that does not
use it (the channel ping-pong runs the same instructions).

Waiting for file descriptors
============================

``System.IO.Wait`` (in ``base``) waits for a file descriptor to become
readable or writable, with an optional deadline, and ``System.IO.Fd`` reads
and writes non-blocking descriptors (into a ``Buffer``) and makes pipes.  A
green thread that waits parks in the scheduler, like one that waits for a
channel: the other threads of its worker keep running.

The runtime has a *reactor* (``support/refc/reactor.c``), which asks the
operating system which descriptors are ready: epoll on Linux, kqueue on
macOS and the BSDs (not tested yet), and ``poll(2)`` elsewhere, or when the
support library is built with ``-DIDRIS2I_1_REACTOR_POLL``.  A descriptor is
registered the first time that a thread waits for it, and the readiness is
*edge triggered*: the reactor learns when a descriptor becomes ready, not
that it still is.  So:

* Wait only after a read or a write failed with ``EAGAIN`` (the
  ``wouldBlock`` result of ``readFd`` and ``writeFd``) on a descriptor made
  non-blocking with ``setNonBlocking``.  ``readFdWait`` and ``writeFdWait``
  do that loop.
* A wait may say ``Ready`` while the descriptor is not ready (another
  thread took the data first, or the readiness was reported earlier): try
  again, and wait again on ``EAGAIN``.  Several threads waiting for one
  descriptor are all woken up.
* Close a descriptor that a thread waited for with ``closeFd``: the threads
  that wait for it are woken up, their wait returning ``WaitError EBADF``,
  and the reactor forgets it.  Before handing such a descriptor over to
  code that closes it (``fdopen``, a C library), call ``forgetFd``.  A
  descriptor closed otherwise stays registered, and a new descriptor with
  the same number may never be reported ready.
* A regular file is always ready.
* ``writeFd`` to a pipe or a socket whose reader is gone returns
  ``-EPIPE`` instead of killing the program with ``SIGPIPE``: the signal is
  blocked in the calling thread for the call, and the one that the write
  raised is discarded.  The disposition of ``SIGPIPE`` in the process is
  left alone, so ``prog | head`` still ends ``prog`` when it writes to
  standard output with ``putStr``.

While threads wait for descriptors, the idle worker that looks after the
deadlines (the watcher) waits in the poller of the operating system instead
of sleeping, the busy workers look at the descriptors without blocking when
they have nothing queued and every 64 switches (unless a worker waits in
the poller), and when no worker looked
for a millisecond, the monitor asks a worker to: it wakes an idle one up
(the watcher may have left to run the threads that it woke up), or, when
every worker runs a thread, asks one of them to yield at its next safepoint
(not with ``IDRIS2I_1_PREEMPT=0``).  So a descriptor that is ready waits about
a millisecond at most, or up to about 11ms when the workers have just
become busy (the monitor looks every 10ms otherwise).  A worker that finds
threads ready as it polls runs the first one itself, without waking up
another worker for it.  A
program whose threads all wait, some of them for a descriptor, is not
reported as deadlocked: data may still come.  The waits work before the
first ``fork``, with ``IDRIS2I_1_WORKERS=1``, and in a program built with
``-DIDRIS2I_1_SINGLE_WORKER`` (which has no preemption: a thread that computes
keeps the others waiting until it blocks).

C code that has to make a call that blocks (a DNS lookup, say) can run it
with ``idris2i_1_blockingCall(fn, arg)`` (``reactor.h``): ``fn(arg)`` runs on a
thread of a pool of plain OS threads, while the green thread that called it
parks.  ``fn`` must not touch Idris2i-1 values nor call the runtime.  The pool
starts threads as the calls need them, up to ``IDRIS2I_1_BLOCKING_THREADS``
(64 by default); more calls wait for a thread.  Without several workers the
call runs in the calling thread.

On the Chez backend, whose threads are OS threads, a wait
blocks its thread in ``poll(2)``, and closing a descriptor does not wake up
a thread that waits for it.  On Windows and WebAssembly, which have no green
threads, a wait blocks the program (on Windows it returns at once, as the
descriptors of the C library cannot be polled there).  The JavaScript
backends do not support these modules.

Non-blocking sockets
--------------------

``Network.Socket.Async`` (in ``network``) has sockets for programs that hold
many connections, a green thread each.  Its sockets are non-blocking and
closed when the program runs another one, and every operation that cannot
go on at once waits for the socket as above: ``accept``, ``connect``,
``recv`` and ``send`` (into and from a ``Buffer`` at an offset),
``sendAll``, ``recvExactly``, ``sendAll2`` (two ranges with one
``sendmsg(2)``), ``recvFrom`` and ``sendTo`` for datagrams.  Each takes an
optional deadline on the clock of ``System.IO.Wait.now`` and returns
``Either NetError a``, where an error is ``Timeout``, ``Closed`` (the socket
was closed, maybe by another thread while this one waited), ``SysError``
(an errno code and its message) or ``ResolveError``.  For inner loops, the
same operations return a plain ``Int`` (``recvCode``, ``sendCode``,
``sendAllCode``, ...): a count or minus an errno code, ``-ETIMEDOUT`` at the
deadline, with no allocation on the way; ``tryRecv`` and ``trySend`` do not
wait at all.  There are also ``listenOn`` (a socket bound with
``SO_REUSEADDR`` and listening), ``shutdown``, ``localAddress`` and
``peerAddress``, and ``setOption`` and ``getOption`` for ``SO_REUSEADDR``,
``SO_REUSEPORT``, ``TCP_NODELAY``, ``SO_KEEPALIVE``, ``SO_RCVBUF``,
``SO_SNDBUF``, ``SO_LINGER``, ``IPV6_V6ONLY`` and ``SO_BROADCAST``.

Addresses (``Network.Socket.Address``) are numeric, IPv4, IPv6 or the path
of a Unix socket, so that no call looks a name up behind the caller's back.
``Network.Socket.DNS.resolve`` looks a name up with ``getaddrinfo(3)``,
which runs on the pool of blocking calls on RefC (see
``idris2i_1_blockingCall`` above), and ``connectHost`` resolves a name and
connects to its addresses in turn.

A socket of this module must be closed with its ``close``, which goes
through ``closeFd``.  Before handing one over to code that blocks, call
``makeBlocking``, which also makes the reactor forget it; ``fdopen``-ing a
socket (as the IDE mode of the compiler does with ``--ide-mode-socket``)
does that by itself.  A write to a socket whose peer is gone fails with
``EPIPE`` instead of raising ``SIGPIPE``, in this module and in
``Network.Socket`` (``MSG_NOSIGNAL`` on each call, or ``SO_NOSIGPIPE`` on
each socket on macOS): the RefC runtime does not ignore ``SIGPIPE``, which
would end the program, and ignoring it for the whole program would change
what a program writing to a closed pipe does.

On the Chez backend the same module works, a wait blocking its
OS thread in ``poll(2)``; the name lookup blocks the calling thread there.
It does not work on Windows yet (every operation fails with ``ENOSYS``), nor
on the JavaScript backends.

TLS connections over these sockets, with OpenSSL 3, are in the optional
``tls`` library: see :doc:`../libraries/tls`.
