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
``-DIDRIS2_REFC_NO_POOLS``.

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

A string cannot contain the NUL character, since it ends the string.

``show`` prints a ``Double`` like the Chez backend: the shortest digits that
read back as the same number (``0.1``, ``1e-10``, ``+inf.0``).

The ``C`` and ``RefC`` calling conventions differ in who owns a ``String``
that a foreign function returns.  With ``%foreign "C:f"``, the generated code
copies the ``char *`` and leaves the original to the function (so it may be a
literal or a static buffer, like the result of ``getenv``).  With
``%foreign "RefC:f"``, the string must come from ``malloc``: the caller takes
it over as the Idris ``String`` and frees it when it is no longer used.
``Integer`` and foreign objects are passed to ``RefC`` functions as
``Idris2_Value *``; the arguments are borrowed, a result is a new reference.

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
threads that are multiplexed onto a single OS thread by the runtime.
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

Scheduling is *cooperative*: a green thread gives up control when it blocks
on a synchronisation object, when it sleeps, when it forks a thread, or when
it finishes.  This has a few consequences:

* Green threads provide concurrency, but not parallelism: only one green
  thread runs at any given moment, and a thread that computes without
  blocking keeps the others waiting.

* A blocking system call, such as reading from standard input, blocks every
  green thread.  The ``sleep`` and ``usleep`` functions of ``System`` are
  exceptions: they are implemented in terms of the scheduler, so that the
  other green threads keep running while a thread sleeps.

* Like in the Chez backend, the program ends when the main expression is
  done: the threads that are still running, sleeping or blocked are
  abandoned.  Use ``threadWait`` to wait for a thread to finish.  If every
  thread is blocked forever while the main expression is still running, the
  program reports a deadlock and exits with an error.

Much of the library is not tail recursive (``map``, ``++``, ``sort``, ...),
so working on a long list needs a deep stack.  Like in the Chez backend,
where the stack grows as needed, the main expression runs on a large stack
of its own: 1GB on 64-bit systems and 64MB on the others, which can be
changed with the ``IDRIS2_MAIN_STACK_SIZE`` environment variable (in bytes).
The memory is only used as the stack grows, and ``ulimit -s`` does not apply
to it.  If the stack cannot be allocated, the main expression runs on the
stack of the process.

Every forked thread gets a stack of its own too.  The size of these stacks
defaults to 8MB, which matches the stack of a typical process, and can be
changed with the ``IDRIS2_THREAD_STACK_SIZE`` environment variable (in bytes,
at least 65536).  Every stack is followed by a guard page, so that a stack
overflow crashes the program rather than corrupting its memory.
