.. _sect-execs:

************************
Compiling to Executables
************************

.. note::

   The documentation for Idris has been published under the Creative
   Commons CC0 License. As such to the extent possible under law, *The
   Idris Community* has waived all copyright and related or neighboring
   rights to Documentation for Idris.

   More information concerning the CC0 can be found online at: http://creativecommons.org/publicdomain/zero/1.0/

Idris 2 (the language) is designed to be independent of any specific code
generator. Still, since the point of writing a program is to be able to run it,
it's important to know how to do so! By default, Idris compiles to executables
via C, with the :doc:`RefC code generator <refc>`.

You can compile to an executable as follows, at the REPL:

::

     Main> :c execname expr

...where ``execname`` is the name of the executable file to generate, and
``expr`` is the Idris expression which will be executed. ``expr`` must have
type ``IO ()``. This will result in an executable file ``execname``, in a
directory ``build/exec``, relative to the current working directory.

You can also execute expressions directly:

::

    Main> :exec expr

Again, ``expr`` must have type ``IO ()``. When the program exits with a code
other than 0 (with ``exitWith``, or when it crashes), the REPL says so, for
example ``The program exited with code 3``, and goes on.

The same can be done from the command line with ``--exec`` (or ``-x``):

::

    $ idris2 hello.idr --exec main

This exits with the exit code of the program (as a program compiled with
``-o`` would), or with 1 if the expression does not compile. A program killed
by a signal gives 128 + the number of the signal, as shells report it.

Finally, you can compile to an executable from the command line by adding
the ``-o <output file>`` option:

::

    $ idris2 hello.idr -o hello

This will compile the expression ``Main.main``, generating an executable
``hello`` (with an extension depending on the code generator) in the
``build/exec`` directory.

By default, Idris 2 is a whole program compiler - that is, it finds all the
necessary function definitions and compiles them only when you build an
executable. This gives plenty of optimisation opportunities, but can also
be slow for rebuilding. However, if the backend supports it, you can build
modules and executables *incrementally*:

.. toctree::
   :maxdepth: 1

   incremental

If the backend supports it, you can generate profiling data by setting
the ``profile`` flag, either by starting Idris with ``--profile``, or
running ``:set profile`` at the REPL. The profile data generated will depend
on the back end you are using. Currently, the Chez and Racket back ends
support generating profile data.

There are five code generators provided in Idris 2, and there is
a system for plugging in new code generators for a variety of targets. The
default is to compile via C with the RefC backend, with alternatives via Chez Scheme, Racket or Gambit.
You can set the code generator at the REPL with the ``:set cg`` command
(for instance ``:set cg chez``), with the ``--cg`` option, or via the
``IDRIS2_CG`` environment variable.

.. toctree::
   :maxdepth: 1

   chez
   racket
   gambit
   javascript
   refc
   refc-flat-layout
   custom
   backend-cookbook

There are also external code generators that aren't part of the main Idris 2
repository and can be found on Idris 2 wiki:

`External backends <https://github.com/idris-lang/Idris2/wiki/External-backends>`_

There is work in progress support for generating
libraries for other languages from idris2 code.

.. toctree::
   :maxdepth: 1

   libraries
