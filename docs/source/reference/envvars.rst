.. _ref-sect-envvars:

*********************
Environment Variables
*********************

Idris2i-1 recognises a number of environment variables, to decide where to look
for packages, external libraries, code generators, etc. It currently recognises,
in approximately the order you're likely to need them:

Build-time
----------

These are variables of the ``Makefile`` that builds Idris2i-1 itself, given in
the environment or on the command line of ``make`` (``make help`` lists them
with their current values):

* ``PREFIX`` - Default way to set the Idris2i-1 installation prefix.
* ``IDRIS2I_1_PREFIX`` - Alternative way to set the Idris2i-1 installation prefix.
* ``DESTDIR`` - Directory prepended to ``PREFIX`` by ``make install``, for
  staged installs (packaging).
* ``IDRIS2I_1_BOOT`` - The Idris2i-1 compiler that builds the compiler (default:
  ``idris2i-1``).
* ``IDRIS2I_1_CG`` - The code generator that the compiler is built with:
  ``refc`` (the default), ``chez`` or ``racket``.
* ``LIBS_INC_CGS`` - The code generators that the libraries are also compiled
  with for incremental builds (``IDRIS2I_1_INC_CGS``; only ``chez`` has them).
  The default is ``chez`` when ``IDRIS2I_1_CG`` is ``chez`` or when the compiler
  in ``build/exec`` runs on Chez Scheme (as after ``make bootstrap``), and
  none otherwise.
* ``IDRIS2I_1_JOBS`` - How many modules of the compiler and of the libraries are
  built in parallel (default: the number of processors, at most 16; ``1``
  builds them one after the other).
* ``LIBS_PARALLEL`` - How many libraries that do not depend on each other are
  built at the same time (default: 3 with RefC, 1 with the Scheme backends).
* ``LTO`` - ``1`` compiles the C of a compiler built with RefC with ``-O2``
  and link time optimisation: slower to build, about 4% faster to run. The
  default is ``0`` (``-O1``), except for the compiler that ``make
  bootstrap-c`` leaves for installing.
* ``BOOT_JOBS`` - ``make bootstrap-c``: how many C compilers compile the
  first compiler of the bootstrap in parallel (default: the number of
  processors, up to 16, and on Linux up to one per 1.5 GB of available
  memory).
* ``BOOT_PARTS`` - ``make bootstrap-c``: how many parts the C of that first
  compiler is compiled in (default: 16, or ``BOOT_JOBS`` when it is more).
* ``BOOT_CFLAGS`` - ``make bootstrap-c``: the C flags of that first compiler
  (default: ``-O1``).
* ``SCHEME`` - ``make bootstrap``: the Chez Scheme executable.

Runtime
-------

* ``EDITOR`` - Editor used in REPL ``:e`` command.

Both
----

* ``IDRIS2I_1_CG`` - Codegen backend.
* ``IDRIS2I_1_PATH`` - Directories where Idris2i-1 looks for import files, in addition
  to the imports in packages
* ``IDRIS2I_1_PACKAGE_PATH`` - Directories where Idris2i-1 looks for Idris2i-1 packages,
  in addition to the defaults (which are under the ``IDRIS2I_1_PREFIX`` and in the
  ``depends`` subdirectory of the current working directory).
  Directories are separated by a ``:`` on MacOS and \*NIX systems, or a ``;`` on
  Windows
* ``IDRIS2I_1_DATA`` - Directories where Idris2i-1 looks for data files. These are
  typically support code for code generators.
* ``IDRIS2I_1_LIBS`` - Directories where Idris2i-1 looks for libraries (for code
  generation).
* ``CHEZ`` - Chez backend: location of the ``chez`` executable.
* ``RACKET`` - Racket backend: location of the ``racket`` executable.
* ``RACKET_RACO`` - Racket backend: location of the ``raco`` executable.
* ``IDRIS2I_1_INC_CGS`` - Code generators to use (comma separated) when compiling
  modules incrementally.
* ``IDRIS2I_1_BUILD_JOBS`` - How many processes build the modules of a package in
  parallel (see ``--jobs``).
* ``IDRIS2I_1_TTC_CACHE_MB`` - How many megabytes of TTC files a process keeps,
  once it has read them, for the modules it checks next (default: 32; ``0``
  keeps none). A process that checks several modules (a build without
  ``--jobs``, the REPL) then reads each import once instead of once for every
  module that imports it. A file is read again when it changes.
* ``IDRIS2I_1_CC`` - RefC backend: location of the C compiler executable.
* ``IDRIS2I_1_CFLAGS`` - RefC backend: C compiler flags.
* ``IDRIS2I_1_CC_JOBS`` - RefC backend: how many C compilers compile a big program in parallel (default: the number of processors, up to 16).
* ``IDRIS2I_1_REFC_SPLIT_SIZE`` - RefC backend: the size in bytes of C from which a program is compiled in units (default: 4000000); to try the units on small programs. ``--directive refc-split-size=N`` takes precedence.
* ``IDRIS2I_1_CPPFLAGS`` - RefC backend: C preprocessor flags.
* ``IDRIS2I_1_LDFLAGS`` - RefC backend: C linker flags.
* ``IDRIS2I_1_LDLIBS`` - RefC backend: C linker library names or flags.
* ``CC`` - RefC backend: C compiler executable (IDRIS2I_1_CC takes precedence).
* ``CFLAGS`` - RefC backend: C compiler flags (IDRIS2I_1_CFLAGS takes precedence).
* ``CPPFLAGS`` - RefC backend: C preprocessor flags (IDRIS2I_1_CPPFLAGS takes precedence).
* ``LDFLAGS`` - RefC backend: C linker flags (IDRIS2I_1_LDFLAGS takes precedence).
* ``LDLIBS`` - RefC backend: C linker library names or flags.
* ``NODE`` - NodeJS backend: ``node`` executable.
* ``PATH`` - PATH variable is used to search for executables in certain
  codegens.
* ``IDRIS2I_1_LINE_EDITING`` - Set to ``0`` to turn off the REPL's line editing
  (key bindings, history and highlighting).
* ``IDRIS2I_1_HISTORY_FILE`` - File where the REPL keeps its history (default:
  ``~/.idris2i_1_history``). If empty, the history is not saved.
* ``TERM`` - The REPL's line editor is turned off when ``TERM`` is unset or
  ``dumb``.
* ``DESTDIR`` - Directory prepended to the installation directory of a
  package by ``--install``, ``--install-with-src`` and ``--dump-installdir``,
  for staged installs.
* ``NO_COLOR`` - Instruct Idris2i-1 not to print colour to stdout. Passing the
  --colour/--color option will supersede this environment variable.
* ``GAMBIT_GSI`` - Gambit backend: location of the ``gsi`` executable.
* ``GAMBIT_GSC`` - Gambit backend: location of the ``gsc`` executable.
* ``GAMBIT_GSC_BACKEND`` - Gambit backend: arguments passed to ``gsc``.

Programs compiled with RefC
---------------------------

A program compiled with the RefC backend (the default) reads these when it
runs; see :doc:`../backends/refc` for the details:

* ``IDRIS2I_1_WORKERS`` - How many OS threads run the green threads, once the
  program forks a thread (default: the number of processors; ``1`` runs them
  all on the main OS thread).
* ``IDRIS2I_1_PREEMPT`` - ``0`` turns off the preemption of a green thread that
  has run for more than 10ms while others wait, or that runs when the sleep
  or the timed wait of another one is over.
* ``IDRIS2I_1_BLOCKING_THREADS`` - How many OS threads may run the blocking
  calls of ``idris2i_1_blockingCall`` at once (default: 64; they are started as
  needed).
* ``IDRIS2I_1_MAIN_STACK_SIZE`` - The size in bytes of the stack of the main
  expression (default: 4GB on 64-bit systems, 64MB on the others; the memory
  is only used as the stack grows).
* ``IDRIS2I_1_THREAD_STACK_SIZE`` - The size in bytes of the stack of every
  forked thread (default: 8MB, at least 65536).
* ``IDRIS2I_1_REFC_KEEP_PAGES`` - How many empty pages of the allocator every OS
  thread keeps instead of giving them back to the system (default: 16).
* ``IDRIS2I_1_REFC_MEMSTATS`` - ``1`` prints the pages of the allocator and the
  values that they hold when the program exits.
* ``IDRIS2I_1_REFC_LEAKCHECK`` - ``1`` reports the values that are still alive
  when the main expression is done (they leaked); ``2`` also shows some of
  them.

Programs compiled with Node
---------------------------

A program compiled with the Node backend reads this when it runs; see
:doc:`../backends/javascript` for the details:

* ``IDRIS2I_1_MAIN_STACK_SIZE`` - The size in bytes of the stack of the worker
  thread that runs the main expression (default: 1GB; the memory is only used
  as the stack grows).  ``0`` runs it on the main thread of Node, whose stack
  is about 1MB.
