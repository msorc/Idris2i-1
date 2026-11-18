**************************
Chez Scheme Code Generator
**************************

The Chez Scheme code generator is not the default one (that is
:doc:`RefC <refc>`): select it with ``--cg chez`` on the command line,
with ``IDRIS2_CG=chez`` in the environment, or via a REPL command:

::

    Main> :set cg chez

To run the programs that it generates you will need to install
`Chez Scheme <https://www.scheme.com/>`_. Chez Scheme is open source, and
available via most OS package managers.

You can compile an expression ``expr`` of type ``IO ()`` to an executable as
follows, at the REPL:

::

    Main> :c execname expr

...where ``execname`` is the name of the executable file. This will generate
the following:

* A shell script ``build/exec/execname`` which invokes the program
* A subdirectory ``build/exec/execname_app`` which contains all the data necessary
  to run the program. This includes the Chez Scheme source (``execname.ss``),
  the compiled Chez Scheme code (``execname.so``) and any shared libraries needed
  for foreign function definitions.

The executable ``execname`` is relocatable to any subdirectory, provided that
``execname_app`` is also in the same subdirectory.

You can also execute an expression directly:

::

    Main> :exec expr

Again, ``expr`` must have type ``IO ()``. This will generate a temporary
executable script ``_tmpchez`` in the ``build/exec`` directory, and execute
that.

If you invoke ``idris2 --cg chez`` with the ``-o execname`` flag, it will generate an executable script
``build/exec/execname``, again with support files in ``build/exec/execname_app``.


Chez Directives
===============

* ``--directive extraRuntime=<path>``

  Embed Scheme source from ``<path>`` directly into generated output. Can be specified more than
  once, in which case all given files will be included in the order specified.

  .. code-block:: scheme

    ; extensions.scm
    (define (my-mul a b)
      (* a b))


  .. code-block:: idris

    -- Main.idr
    %foreign "scheme:my-mul"
    myMul : Int -> Int -> Int

  ::

    $ idris2 --codegen chez --directive extraRuntime=/path/to/extensions.scm -o main Main.idr

* ``--directive lazy=weakMemo``

  Makes all non-toplevel ``Lazy`` and ``Inf`` values to be *weakly* memoised.
  That is, once this expression is evaluated at runtime, it is allowed to not to be recalculated on later accesses
  until memoised value is wiped by a garbage collector.
  Garbage collector is allowed to collect weakly memoised values at its own discretion,
  so when no free memory is available, weakly memoised values are free to be wiped.
  That's why it is safer comparing to full memoisation.

* ``--directive chez-backtrace``

  Makes a program that dies of a fatal error print a backtrace, with the Idris
  names of its functions and where they are defined: see `Backtraces`_.

Backtraces
==========

A program that dies of a fatal error can print the Idris functions that it
was in, the innermost first, on the standard error after the message of the
error, in the same form as with :doc:`RefC <refc>`.  This works for
``idris_crash``, a missing case in ``partial`` code (a division by zero is one,
in the Prelude) and an error that Chez raises and that nothing handles
(``cast`` of an infinite ``Double`` to an ``Integer``, say), on the main
thread and on the threads of ``fork``:

::

    $ idris2 --cg chez --directive chez-backtrace -o prog Main.idr
    $ ./build/exec/prog
    ERROR: too big
    Backtrace of the main thread, innermost call first:
      Builtin.idris_crash (Builtin:204:1)
      Main.sumChecked (Main:25:1), 3 frames
      Main.run (Main:44:1)
      Main.main (Main:53:1)

    Exception in exact: no exact representation for +inf.0
    Backtrace of thread 1, innermost call first:
      Main.toInteger (Main:35:1)
      Main.run (Main:44:1)

- ``--directive chez-backtrace`` puts a table of the functions of the program
  in it: their Scheme names, their Idris names and where they are defined,
  and turns the backtraces on by default.  It also keeps Chez from inlining
  the functions of the program, so that every call that is not in tail
  position has a frame of its own, and makes a crash a call that is not in
  tail position, so that the function where it happens is in the backtrace.
- The environment variable ``IDRIS2_CHEZ_BACKTRACE`` turns them on (``1``) or
  off (``0``) when the program runs, with or without the directive.  Without
  it, the frames show the Scheme names of the functions turned back into
  Idris names (``Main.describe``, without where it is), and the functions
  that Chez inlined are not there (it inlines a lot: a small function, or one
  that is called from one place only).

The frames are those of the continuation of the error, which the program
walks with the inspector of Chez when the error happens: the name of the code
of each return point is the Scheme name of a function.  Until then, the
program only reads the environment variable when it starts: without the
directive, the code of the program is the same with backtraces on or off (its
support code makes the ``.so`` file about 12KB bigger, and the programs of
``benchmark/`` run 0.03% to 0.2% more instructions).  The directive costs some
speed, since Chez inlines nothing of the program then: 2% to 18% more
instructions for the programs of ``benchmark/``, whose ``.so`` files are 20%
to 40% bigger.  What a backtrace does not show:

- the calls in tail position, which leave no frame: Chez makes every one of
  them a jump, so that a loop runs in constant space, and the backtraces of
  code written as loops have fewer frames than with RefC;
- without the directive, the functions that Chez inlined; and, with or without
  it, the functions that the Idris compiler inlined (``%noinline`` keeps a
  function), and the anonymous functions (``\x => ...``) passed to other
  functions;
- where in a function the call is: only the line where the function is
  defined;
- the frames of foreign C functions: Chez does not know them.  Chez turns a
  ``SIGSEGV`` or a ``SIGFPE`` in foreign code into an error ("invalid memory
  reference", "arithmetic overflow"), whose message is followed by a
  backtrace, but it loses the continuation of the call doing so ("Some
  debugging context lost"): the backtrace says that it has ``no frames of
  Idris functions``.

A deep continuation shows its 48 innermost frames and its 12 outermost ones,
with consecutive frames of the same function on one line (``Main.depth
(Main:39:1), 47 frames``); it is not walked beyond 5 million frames.  In an
incremental build (``IDRIS2_INC_CGS=chez``, see :doc:`incremental`), the
modules are compiled without the directive: given when the program is built,
it only turns the backtraces on, and the names are those of the Scheme code
(Chez does not inline a function of a module, which is defined at the top
level).

A fatal error ends the program as it did without the backtrace: with exit code
1 after a crash (also on a thread other than the main one: ``exit`` used to end
that thread only), with exit code 255 after an error of Chez on the main
thread.  An error of Chez on another thread ends that thread only, as without
the backtrace.  What the backtraces do not cover:

- ``SIGABRT`` and the other signals that Chez does not handle (a C library
  that calls ``abort``): the program dies of the signal without a backtrace.
  A handler of the signals in the support library could only print the C
  frames (``backtrace(3)``), not the Idris ones, which C cannot walk, and it
  would replace the handlers with which Chez turns ``SIGSEGV`` and ``SIGFPE``
  into errors: there is none;
- the errors of unsafe code: the program is compiled with ``optimize-level
  3``, where ``car`` of something that is not a pair, say, is not checked;
- a recursion without end, which does not overflow a stack with Chez: the
  continuation grows in the heap until the memory runs out, and Chez then
  prints ``out of memory`` and aborts.

Making a freestanding executable
================================

It's possible to embed the Chez Scheme system and the built Idris2 program into a freestanding executable with `chez-exe <https://github.com/gwatt/chez-exe>`_.

  * Build and install the ``compile-chez-program-tool`` by running the
    configuration script and then make:

    ::

      $ scheme --script gen-config.ss --bootpath <bootpath>

    where ``<bootpath`` is the path to where the Chez Scheme bootfiles (``petite.boot`` and ``scheme.boot``) and ``scheme.h`` are. More
    configuration is described in the chez-exe installation instructions.

  * Invoke ``compile-chez-program``:

    ::

      $ compile-chez-program --optimize-level 3 build/exec/my_idris_prog_app/my_idris_prog.ss

    Note that it can only use the ``.ss``-file and not the ``.so``-file. To
    embed the full Chez Scheme system including the compiler add the ``--full-chez`` option.

  * The finished executable still requires the libidris_support shared
    library. It's possible to also eliminate that dependency by linking with
    it statically.

