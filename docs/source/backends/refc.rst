*************************
C with Reference Counting
*************************

There is an experimental code generator which compiles to an executable via C,
using a reference counting garbage collector. This is intended as a lightweight
(i.e. minimal dependencies) code generator that can be ported to multiple
platforms, especially those with memory constraints.

Performance is not as good as the Scheme based code generators: programs that
allocate many small values typically take two to four times as long as with
the Chez backend, as every value is reference counted and freed as soon as it
is no longer used.  On the other hand they usually need much less memory.  The
main goal is portability: the generated code should run on any platform that
supports a C compiler.

Small values are allocated from pages of values of the same size rather than
with ``malloc``.  When the program runs under Valgrind, and the support library
was built with the Valgrind headers available, every value comes from
``malloc``, so that Valgrind can check them.  For other memory checkers (such
as AddressSanitizer), compile the support library and the program with
``-DIDRIS2_REFC_NO_POOLS``: ``make install-support-refc-asan PREFIX=<prefix>``
installs such a support library, built with AddressSanitizer and UBSan, and the
comment at the top of ``support/refc/Makefile`` gives the flags for the
programs.

Two environment variables make a program report on its memory when it exits
(on the standard error):

- ``IDRIS2_REFC_MEMSTATS=1`` prints the pages of the allocator and the values
  that they hold, by size.
- ``IDRIS2_REFC_LEAKCHECK=1`` looks for the values that are still alive once
  the main expression is done, and that the constants of the program (the
  definitions without arguments, which are kept until the program exits) do
  not hold: those values leaked, from a cycle of references for example.
  ``IDRIS2_REFC_LEAKCHECK=2`` also shows some of them.  The check is skipped
  when other threads still run, or when the program exits early (with
  ``exitWith``, say).  Large values (more than 256 bytes) are only counted.

When the support library and the program are both compiled with
``-DIDRIS2_REFC_STATS`` (``IDRIS2_CPPFLAGS=-DIDRIS2_REFC_STATS`` for the
program), ``IDRIS2_REFC_MEMSTATS=1`` also prints counts of what the program
did: allocations by size, reference count operations (on unboxed values, on
values counted in place, on values shared between threads, on immortal values),
uniqueness tests, constructors reused in place, and closure applications by
kind.  Such a build is slower, and only meant to find out where the time goes.

This code generator can be accessed via the REPL command:

::

    Main> :set cg refc

Alternatively, you can set it via the ``IDRIS2_CG`` environment variable:

::

    $ export IDRIS2_CG=refc

The C compiler it invokes is determined by either the ``IDRIS2_CC`` or ``CC``
environment variables. If neither is set, it uses ``cc``.

This code generator does not yet support `:exec`, just `:c`.

Also note that, if you link with any dynamic libraries for interfacing with
C, you will need to arrange for them to be accessible via ``LD_LIBRARY_PATH``
when running the executable. The default Idris 2 support libraries are
statically linked.

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
the first NUL character of the Idris string.  Reading a line from a file
(``fGetLine``) also stops at a NUL character.

``show`` prints a ``Double`` like the Chez backend: the shortest digits that
read back as the same number (``0.1``, ``1e-10``, ``+inf.0``).

The ``C`` and ``RefC`` calling conventions pass strings differently.  With
``%foreign "C:f"``, a ``String`` argument is a ``char *``, and a ``String``
result is a ``char *`` that the generated code copies and leaves to the
function (so it may be a literal or a static buffer, like the result of
``getenv``).  With ``%foreign "RefC:f"``, a ``String`` is an Idris value
(``Idris2_Value *``, an ``Idris2_String`` with its length ``len`` and its
bytes ``str``), like ``Integer`` and foreign objects: the arguments are
borrowed, a result is a new reference (``idris2_mkStringN`` makes one).

Building Idris 2 with RefC
==========================

The compiler can itself be compiled with RefC, which gives a way to bootstrap
it with only a C compiler: ``make bootstrap-c`` (see ``INSTALL.md``).  A
compiler built this way has no Chez Scheme evaluator, so ``:set eval scheme``
reports an error.

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

To run a compiled Idris program, call the ``int main(int argc, char *argv[])``
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
fully qualified Idris name of that function.

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
Chez backend (mutexes are recursive, a channel holds at most one value, and
a forked thread inherits the thread local data of its parent), but they are
implemented by the RefC scheduler rather than by the operating system.

A program has a single worker until it forks its first thread.  Then there
is one worker per processor, or as many as the ``IDRIS2_WORKERS``
environment variable says (``IDRIS2_WORKERS=1`` runs every green thread on
the main OS thread).  The green threads run in parallel, one per worker at a
time: a worker with nothing to run takes threads from a busy one.  A thread
that wakes another one up (by putting a value in a channel, say) leaves it to
run next on the same worker, so that threads that pass values back and
forth do not need the operating system to switch between them.

Within a worker, scheduling is mostly *cooperative*: a green thread runs
until it blocks on a synchronisation object, sleeps, forks a thread, or
finishes.  A thread that has run for more than 10ms while other threads wait
for its worker yields at its next safepoint (the end of an iteration of a
loop); ``IDRIS2_PREEMPT=0`` turns this off.  With a single worker, threads
are never preempted.  This has a few consequences:

* A thread that computes without looping (deep recursion, say) keeps the
  other threads of its worker waiting, until an idle worker takes them over.

* A blocking system call, such as reading from standard input, blocks the
  worker that makes it, but not the others.  The ``sleep`` and ``usleep``
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

Values are reference counted.  A value that only one thread can see is
counted with plain increments and decrements; once a value is handed over to
another thread (it is captured by the action of ``fork``, put in a channel,
or written to an ``IORef`` or an array that other threads can see), it and
everything it refers to become *shared*, and their counts are updated
atomically.  Shared values are never updated in place.  Every worker
allocates from memory of its own, without locks.

Much of the library is not tail recursive (``map``, ``++``, ``sort``, ...),
so working on a long list needs a deep stack.  Like in the Chez backend,
where the stack grows as needed, the main expression runs on a large stack
of its own: 4GB on 64-bit systems and 64MB on the others, which can be
changed with the ``IDRIS2_MAIN_STACK_SIZE`` environment variable (in bytes).
The memory is only used as the stack grows, and ``ulimit -s`` does not apply
to it.  If the stack cannot be allocated, the main expression runs on the
stack of the process.

Every forked thread gets a stack of its own too.  The size of these stacks
defaults to 8MB, which matches the stack of a typical process, and can be
changed with the ``IDRIS2_THREAD_STACK_SIZE`` environment variable (in bytes,
at least 65536).  Every stack is followed by a guard page, so that a stack
overflow crashes the program rather than corrupting its memory.
