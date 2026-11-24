**********************
Debugging The Compiler
**********************

Performance
===========

The compiler has the ``--timing`` flag to dump timing information collected during operation.

The output documents, in reverse chronological order, the cumulative time taken for the operation (and sub operations) to complete.
Sub levels are indicated by successive repetitions of ``+``.

The ``--timing-summary`` flag adds up, instead, the processor time spent in a
few parts of the compiler over the whole run, and prints it as the compiler
exits, in lines that start with ``PROFILE``: parsing (``parse``), reading
imports (``import``, with ``import.read`` for reading the TTC files and
``import.register`` for adding their definitions to the context), decoding the
definitions of imported modules when they are first used (``decode``), each
top-level declaration (``decl``), constraint solving (``solve``), the delayed
elaborators run again (``delay``), ambiguous names (``ambig``), auto implicit
search (``search``), case trees (``casetree``), coverage (``coverage``),
totality (``totality``), compiling and inlining (``compile``) and writing TTC
files (``ttc.write``). Timers nest: a timer's ``incl`` time includes the
timers run inside it (constraint solving inside a declaration, decoding inside
anything), its ``self`` time does not, so the self times add up to the time
spent under some timer, and the rest of the run is ``untimed`` (start-up and
the build driver). Counters say how often things happened: constraint scans
and the guesses they looked at, alternatives of ambiguous names elaborated and
how many succeeded, definitions decoded and their bytes (and those of their
compiled code), and so on. For each module that it builds, the compiler also
prints a line with its time, the self times and counters of the module, and
lines for its ten most expensive declarations. The peak resident set size of
the process is given too. With ``--jobs``, each process prints its own
summary; ``benchmark/typecheck/sum-profile.sh`` adds them up. The timers cost
nothing measurable when the flag is not given.

.. _sect-logging:

Logging
=======

The compiler logs various categories of information during operation at various levels.

Log levels are characterised by two things:

+ a dot-separated path of ever finer topics of interest e.g. scope.let
+ a natural number corresponding to the verbosity level e.g. 5

If the user asks for some logs by writing::

    %logging "scope" 5

they will get all of the logs whose path starts with `scope` and whose
verbosity level is less or equal to `5`. By combining different logging
directives, users can request information about everything (with a low
level of details) and at the same time focus on a particular subsystem
they want to get a lot of information about. For instance:::

    %logging 1
    %logging "scope.let" 10

will deliver basic information about the various phases the compiler goes
through and deliver a lot of information about scope-checking let binders.


You can set the logging level at the command line using::

    --log <level>

and through the REPL using::

    :log <string category> <level>

    :logging <string category> <level>

The supported logging categories can be found using the command line flag::

    --help logging

REPL Commands
=============

To see more debug information from the REPL there are several options one can set.

.. csv-table:: Logging Categories
   :header: "command", "description"
   :widths: 20, 20

   ``:di <name>``, show debugging information for a name
   ``:set showimplicits``, show values of implicit arguments

Compiler Flags
==============

There are several 'hidden' compiler flags that can help expose Idris2i-1's inner workings.

.. csv-table:: Logging Categories
   :header: "command", "description"
   :widths: 20, 20

   ``--dumpcases <file>``, dump case trees to the given file
   ``--dumplifted <file>``, dump lambda lifted trees to the given file
   ``--dumpanf <file>``, dump ANF to the given file
   ``--dumpvmcode <file>``, dump VM Code to the given file
   ``--debug-elab-check``, do more elaborator checks (currently conversion in LinearCheck)


Output Formats
==============

Debug Output
------------

Calling ``:di <name>`` dumps debugging information about the selected term.
Specifically dumped are:

.. csv-table:: Debugging Information
   :header: "topic", "description"
   :widths: 20, 20

   Full Name(s), The fully qualified name of the term.
   Multiplicity, The terms multiplicity.
   Erasable Arguments, Things that are erased.
   Detaggable argument types,
   Specialised arguments,
   Inferrable arguments,
   Compiled version,
   Compile time linked terms,
   Runtime linked terms,
   Flags,
   Size change graph,
