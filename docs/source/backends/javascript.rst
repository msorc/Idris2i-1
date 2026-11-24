***********************************
Javascript and Node Code Generators
***********************************

There are two javascript code generators, ``node`` and ``javascript``. There are two
differences between the two: the ``javascript`` code generator when called to
output an HTML file will also generate a basic HTML document with the
generated code inside a ``<script>`` tag; the other distinction is on the ffi
that will be explained below.

**Note**: The JavaScript codegen uses the new BigInt, hence Node.js 10.4 or higher is required.

Javascript FFI Specifiers
=========================

There are three main kinds of javascript ffi specifiers ``javascript``,
``node`` and ``browser``. ``javascript`` is for foreigns that are available on
node and the browser, ``node`` for foreigns that are only available on node and
``browser`` for browser only foreigns.

For ``node`` there are two ways of defining a foreign:

.. code-block:: idris

    %foreign "node:lambda: n => process.env[n]"
    prim_getEnv : String -> PrimIO (Ptr String)

here ``lambda`` means that we are providing the definition as a lambda
expression.


.. code-block:: idris

    %foreign "node:lambda:fp=>require('fs').fstatSync(fp.fd, {bigint: false}).size"
    prim__fileSize : FilePtr -> PrimIO Int

``require`` can be used to import javascript modules.

For completion below an example of a foreign available only with ``browser`` codegen:

.. code-block:: idris

    %foreign "browser:lambda:x=>{document.body.innerHTML = x}"
    prim__setBodyInnerHTML : String -> PrimIO ()


Short Example
-------------

An interesting example is creating a foreign for the setTimeout function:

.. code-block:: idris

    %foreign "javascript:lambda:(callback, delay)=>setTimeout(callback, delay)"
    prim__setTimeout : (PrimIO ()) -> Int -> PrimIO ()

    setTimeout : HasIO io => IO () -> Int -> io ()
    setTimeout callback delay = primIO $ prim__setTimeout (toPrim callback) delay

Note: Previous versions of the javascript backends treated ``Int`` as a
64 bit signed integer represented by ``BigInt`` in javascript land. This is no
longer the case: ``Int`` is now treated as a 32 bit signed integer represented
by ``Number``. This should facilitate interop between Idris2i-1 and the backend.

However, unless you have good reasons to do otherwise, consider using
one of the other fixed precision integral types. They are supposed to behave
the same across all backends. All signed and unsigned integrals of up to
32 bit precision (``Int8``, ``Int16``, ``Int32``, ``Bits8``, ``Bits16``, and ``Bits32``)
are represented by ``Number`` while ``Int64``, ``Bits64``, and ``Integer``
are represented by ``BigInt``. The example above could therefore be
improved by using ``Int32`` instead of ``Int``:

.. code-block:: idris

    %foreign "javascript:lambda:(callback, delay)=>setTimeout(callback, delay)"
    prim__setTimeout : (PrimIO ()) -> Int32 -> PrimIO ()

    setTimeout : HasIO io => IO () -> Int32 -> io ()
    setTimeout callback delay = primIO $ prim__setTimeout (toPrim callback) delay

Browser Example
===============

To build JavaScript aimed to use in the browser, the code must be compiled with
the javascript codegen option. The compiler produces a JavaScript or an HTML file.
The browser needs an HTML file to load. This HTML file can be created in two ways

- If the ``.html`` suffix is given to the output file the compiler generates an HTML file
  which includes a wrapping around the generated JavaScript.
- If *no* ``.html`` suffix is given, the generated file only contains the JavaScript code.
  In this case manual wrapping is needed.

Example of the wrapper HTML:

.. code-block:: html

    <html>
     <head><meta charset='utf-8'></head>
     <body>
      <script type='text/javascript'>
      JS code goes here
      </script>
     </body>
    </html>

As our intention is to develop something that runs in the browser questions naturally arise:

- How to interact with HTML elements?
- More importantly, when does the generated Idris2i-1 code start?

Starting point of the Idris2i-1 generated code
----------------------------------------------

The generated JavaScript for your program contains an entry point. The ``main`` function is compiled
to a JavaScript top-level expression, which will be evaluated during the loading of the ``script``
tag and that is the entry point for Idris2i-1 generated program starting in the browser.

Interaction with HTML elements
------------------------------

As sketched in the Short Example section, the FFI must be used when interaction happens between Idris2i-1
generated code and the rest of the Browser/JS ecosystem. Information handled by the FFI is
separated into two categories. Primitive types in Idris2i-1 FFI, such as Int, and everything else.
The everything else part is accessed via AnyPtr. The ``%foreign`` construction should be used
to give implementation on the JavaScript side. And an Idris2i-1 function declaration  to give ``Type``
declaration on the Idris2i-1 side. The syntax is ``%foreign "browser:lambda:js-lambda-expression"`` .
On the Idris2i-1 side, primitive types and ``PrimIO t`` types should be used as parameters,
when defining ``%foreign``. This declaration is a helper function which needs to be called
behind the ``primIO`` function. More on this can be found in the FFI chapter.

Examples for JavaScript FFI
---------------------------

console.log
-----------

.. code-block:: idris

    %foreign "browser:lambda: x => console.log(x)"
    prim__consoleLog : String -> PrimIO ()

    consoleLog : HasIO io => String -> io ()
    consoleLog x = primIO $ prim__consoleLog x

String is a primitive type in Idris2i-1 and it is represented as a JavaScript String. There is no need
for any conversion between the Idris2i-1 and the JavaScript.

setInterval
-----------

.. code-block:: idris

    %foreign "browser:lambda: (a,i)=>setInterval(a,i)"
    prim__setInterval : PrimIO () -> Int32 -> PrimIO ()

    setInterval : (HasIO io) => IO () -> Int32 -> io ()
    setInterval a i = primIO $ prim__setInterval (toPrim a) i

The ``setInterval`` JavaScript function executes the given function in every ``x`` millisecond.
We can use Idris2i-1 generated functions in the callback as far as they have the type ``IO ()`` .

HTML Dom elements
-----------------

Lets turn our attention to the Dom elements and events. As said above, anything that is not a
primitive type should be handled via the ``AnyPtr`` type in the FFI. Anything complex that is
returned by a JavaScript function should be captured in an ``AnyPtr`` value. It is advisory to
separate the ``AnyPtr`` values into categories.

.. code-block:: idris

    data DomNode = MkNode AnyPtr

    %foreign "browser:lambda: () => document.body"
    prim__body : () -> PrimIO AnyPtr

    body : HasIO io => io DomNode
    body = map MkNode $ primIO $ prim__body ()

We create a ``DomNode`` type which holds an ``AnyPtr``. The ``prim__body`` function wraps a
lambda function with no parameters. In the Idris2i-1 function ``body`` we pass an extra ``()`` parameter
and the we wrap the result in the ``DomNode`` type using the ``MkNode`` data constructor.

Primitive values originated in JavaScript
-----------------------------------------

As a continuation of the previous example, the ``width`` attribute of a DOM element can be
retrieved via the FFI.

.. code-block:: idris

    %foreign "browser:lambda: n=>(n.width)"
    prim__width : AnyPtr -> PrimIO Bits32

    width : HasIO io => DomNode -> io Bits32
    width (MkNode p) = primIO $ prim__width p

Handling JavaScript events
--------------------------

.. code-block:: idris

    data DomEvent = MkEvent AnyPtr

    %foreign "browser:lambda: (event, callback, node) => node.addEventListener(event, x=>callback(x)())"
    prim__addEventListener : String -> (AnyPtr -> PrimIO ()) -> AnyPtr -> PrimIO ()

    addEventListener : HasIO io => String -> DomNode -> (DomEvent -> IO ()) -> io ()
    addEventListener event (MkNode n) callback =
      primIO $ prim__addEventListener event (\ptr => toPrim $ callback $ MkEvent ptr) n


In this example shows how to attach an event handler to a particular DOM element. Values of events
are also associated with ``AnyPtr`` on the Idris2i-1 side. To separate ``DomNode`` form ``DomEvent``
we create two different types. Also it demonstrates how a simple callback function defined in
Idris2i-1 can be used on the JavaScript side.

Stack depth
===========

JavaScript engines give a program a small stack (about 1MB with Node, and
similar in browsers), which they cannot grow, and they do not eliminate tail
calls.  The code generators make up for this as follows.

Tail calls of a toplevel function to itself, or between toplevel functions
that call each other, are compiled to loops (a function that only calls
itself becomes a ``while`` loop, functions that call each other a loop
through a function of the group).  This covers the usual loops in
``IO`` as well (``loop n = do act n; loop (n - 1)``), since the inliner turns
them into such calls.

Other tail calls go to functions that are not known when the code is
generated: the continuation of a ``>>=`` in a ``Maybe``, ``Either`` or
unknown monad, or in continuation-passing code.  They go through a
trampoline: such a call is made directly while there are fewer than 64 of
them on the stack, and beyond that it returns a pending call to the nearest
caller that needs the value, which makes it.  So a loop through any monad
runs in constant stack space.  A function given to foreign code (an argument
whose type is a function) is wrapped so that its calls run the pending calls;
the same function gets the same wrapper every time (so foreign code can
remove a callback it was given before, as with ``removeEventListener``), with
the ``length`` of the function, and the functions that it returns are
wrapped too.  A pending call never reaches foreign code: while a foreign
function runs, and outside Idris2i-1 code (from the event loop, or a
``%nomangle`` function called from JavaScript), the tail calls are made
directly.  So a closure that reaches foreign code in another way, such as
inside an ``AnyPtr`` or a record, returns its value when JavaScript calls
it, but its tail calls to unknown functions take stack as they do without
the trampoline; the foreign code can call it through ``__resFn(f)``, the
wrapper above, to run them in constant stack.  ``--directive no-trampoline``
makes all these calls directly, as before.

The library builds ranges (``[1..n]``), and runs ``and`` and ``or`` on
lists, with loops; ``map``, ``filter``, ``(++)`` and ``concat`` on lists are
tail recursive.  ``traverse``, ``for``, ``sequence``, ``traverse_``,
``for_``, ``sequence_`` and ``foldlM`` on lists, and ``*>`` (``foldr (*>)
(pure ())`` on a list of actions), are loops in ``IO``, in ``State``,
``Reader``, ``Writer`` and ``RWS``, in ``StateT``, ``ReaderT``, ``WriterT``
and ``RWST`` over ``IO``, in ``StateT`` over ``Either e`` and ``Maybe``, and
in ``EitherT e IO`` and ``MaybeT IO``; ``traverse`` and friends (not
``foldlM`` and ``*>``) on lists in ``Control.App``; ``traverse_``, ``for_``
and ``sequence_`` on ``SnocList``, ``List1`` and ``Vect`` in ``IO``, and
``traverse``, ``for`` and ``sequence`` on ``SnocList`` and ``List1`` in
``IO``; ``many`` of ``Data.String.Parser`` (and ``some``, ``takeWhile`` and
the like, which use it).  These loops are ``%transform`` rules of the
library to functions that do the same with ``>>=`` (``bindTraverseList``
and the like in ``Control.Monad.Trans``, where the rest of the list is the
continuation, which the trampoline runs in constant stack), and they have
the effects of the original in the same order (in ``EitherT`` and
``MaybeT``, where ``<*>`` runs both actions also after a ``Left``, the
actions in ``IO`` all run and their results are combined after).  Explicit
recursive loops in these monads (``loop n = do step n; loop (n - 1)``, also
through ``when``) run in constant stack as they are: their ``>>=`` calls the
continuation as a tail call.

In the browser, a function that returns a constructor with a call of itself
in a field (tail recursion modulo cons: ``zipWith f (x :: xs) (y :: ys) = f
x y :: zipWith f xs ys``) is compiled to a loop too: it makes the cell first,
with a hole that the call, now a tail call, fills.  This covers ``zip``,
``zipWith``, ``take``, ``intersperse``, ``iterateN``, ``delete``, the merge
of ``sort``, ``lines``, ``words``, ``unwords``, ``transpose`` and the like,
``tails`` and such functions of the program, also with a cell inside a cell
(``x :: y :: f xs``), several calls in the cell (the last one is the hole),
or the call in a ``case`` in the cell (``xs :: case xs of ...``, if the
other fields only allocate).  The
fields after the call must do nothing but allocate (variables, constants,
constructors, lambdas): ``Node (f l) (g x) Leaf`` stays a recursion.  With
Node, whose main expression runs on a large stack (see below) where these
loops cost 8 to 15% on the benchmarks, ``--directive trmc`` makes them;
``--directive no-trmc`` turns them off in the browser.

In the browser, the other functions that call themselves where the call is
not a tail call (``foldr c n (x :: xs) = c x (foldr c n xs)``, or ``span``,
whose call is the scrutinee of a ``case``: ``let (ys, zs) = span p xs in
(x :: ys, zs)``) are compiled to loops on an explicit stack: a call of the
function in an argument, a ``case`` scrutinee or a ``let`` becomes a jump
back to the start of the loop, which first pushes a frame with what is left
to do after the call (and the variables that it needs) on a stack in the
heap; a value returned goes to the frame on top of the stack.  This covers
``foldr`` (and what is defined with it) on lists, ``traverse``, ``for`` and
``sequence`` on lists in ``Maybe``, ``Either`` and the like, the functions
that return a pair (``span``, ``break``, ``splitAt``, ``partition``,
``unzip``, ``group``), recursion on trees (``size l + size r``, the
``treeInt`` benchmark) and such functions of the program.  The order of
evaluation stays the same: a call whose loop would change it (a ``case`` or
a ``let`` inside an argument after the call, which the code generator would
compute before the call) stays a recursion, as do calls under a lambda or
in a lazy value, and functions in a group of several that call each other by
tail calls.  With Node, ``--directive explicit-stack`` makes these loops,
and ``--directive no-explicit-stack`` turns them off in the browser.  They
cost little on lists (5 to 8% more instructions with lists of 1000 elements
on Node, none on the benchmarks) but more on shallow recursion that does
little else (2.4 times the instructions for ``fib``); on deep recursion they
are faster than Node's large stack (``foldr`` on 10^6 elements takes 72%
fewer instructions).

What is left needs a stack as deep as the recursion: recursion through
several functions that call each other where the calls are not tail calls,
and through closures: running a chain of actions as long as the list where
each action runs the rest before it returns, as ``traverse`` builds in an
applicative that the library does not turn into a loop.  On 10^5 elements,
of the shapes above (``traverse``, ``for``, ``sequence``, ``traverse_``,
``for_``, ``sequence_``, ``foldlM``, ``foldr (*>)``, ``foldr (<*)``, a loop
with ``when``, a recursive loop) in ``IO``, ``State``, ``Reader``,
``Writer``, ``RWS``, ``StateT s IO``, ``ReaderT r IO``, ``WriterT w IO``,
``EitherT e IO``, ``MaybeT IO``, ``StateT s (Either e)``, ``Either e``,
``Maybe`` and ``Identity``, and ``traverse`` and ``traverse_`` on
``SnocList``, ``List1`` and ``Vect`` in ``IO`` and ``State``, these still
overflow: ``foldr (<*) (pure ())`` in all of these monads but ``Either``,
``Maybe`` and ``Identity`` (``a <* b`` gives the value of ``a`` after
``b``, so each action of the chain has something left to do after the rest
of it); ``traverse`` on a ``Vect`` in ``IO``; ``traverse`` and
``traverse_`` on ``SnocList``, ``List1`` and ``Vect`` in ``State``; and
these functions in other combinations (the transformers over another
transformer, ``ReaderT r (StateT s IO)``, or over a monad of the program;
another container in a transformer; a ``Traversable`` of the program).
``many`` and ``some`` of ``Text.Parser`` on long inputs overflow too:
``doParse`` calls itself from the functions that its ``case`` blocks are
compiled to, which the explicit stack does not follow.  Making every
call of a closure that is not a tail call go through the explicit stack (in
effect, compiling the whole program in continuation-passing style) would
cost much more than these loops: on small programs written by hand in that
style, 3 to 3.7 times the instructions of direct calls on a chain of
closures and on ``fib`` through a closure (1.1 times on ``map`` with a
closure).  Capturing the stack when it gets deep and resuming it on an empty
one (with an exception that each frame catches and adds its variables to)
costs 10 to 40% while the stack is shallow, 13 times the heap stack once it
is deep, and needs every function to be compiled so that it can resume in
the middle.  Neither is done.  With
Node, the main expression therefore runs on a stack of its own of 1GB, in a
worker thread, as it does with the RefC backend, which is enough for lists
of millions of elements.  The ``IDRIS2I_1_MAIN_STACK_SIZE``
environment variable gives the size of this stack in bytes; with ``0``, or
when the generated file is loaded with ``require`` instead of being the
script that Node runs, the program runs on the main thread.  The worker
writes to stdout and stderr synchronously and asks the main thread to change
the working directory and to listen to signals, and the exit code and
uncaught exceptions are passed on, so that programs behave as on the main
thread.  Signals reach the main thread, which passes them on at once (see
below).  The library reads stdin from file descriptor 0, synchronously;
when foreign code first uses ``process.stdin`` in the worker, the main thread
starts reading file descriptor 0 as a stream and passes the input on to
``process.stdin`` of the worker, so that such code works as on the main
thread.  As there, a program should not read stdin both ways: each would get
part of the input.  Starting the worker costs about 25ms and 12MB.  Deep
recursion is slow with V8, as every garbage collection walks the whole
stack: ``traverse`` on a list of a million elements takes 12 times as long
as on one of 100,000.

The browser has no such worker: there, the recursion that is left
overflows the stack at a few thousand levels.  Use ``foldl``,
tail-recursive functions, or ``Data.SnocList`` there for longer lists.

Signals
-------

With Node, ``System.Signal`` works as with the other backends, with one
limit.  Node runs the listeners of signals on its main thread, from its
event loop, which does not run while the program does; so the listeners of
``collectSignal`` live on the main thread, and record a signal in memory
that the thread of ``main`` shares, where ``handleNextCollectedSignal``
reads it.  When ``main`` runs in its worker thread (the default), the idle
main thread records the signals of other processes as they arrive, and a
signal cuts ``sleep`` and ``usleep`` short, as in C.  When ``main`` runs on
the main thread (``IDRIS2I_1_MAIN_STACK_SIZE=0``, or a program loaded with
``require``), signals from other processes are only recorded after ``main``
has returned, although ``ignoreSignal`` works.  ``raiseSignal`` and
``sendSignal`` to the program itself handle a collected or ignored signal at
once in both cases, as ``raise`` does in C.  ``SIGKILL`` and ``SIGSTOP``
cannot be collected or ignored.

No helper thread can receive the signals of other processes for the main
thread: Node delivers a signal to its main thread only, and a signal for which
only a worker thread has a listener has its default action (it ends the
program).  So that limit stays.

Child processes
---------------

``popen`` (for reading and for writing), ``pclose``, ``popen2``,
``popen2Wait``, ``system``, ``run`` and ``runProcessingOutput`` work with
Node as with the C backends.  The child runs at the same time as the
program, and the pipes behave as in C: a program that reads an empty pipe
waits, and the child waits when it writes to a pipe that is full (so
``popen2`` has the deadlocks that its documentation warns of).  The pipes
are FIFOs that the program makes with the ``mkfifo`` utility and opens with
``fs.openSync`` (Node gives the pipes that it makes for a child process as
streams only, whose file descriptors are not part of its API), so ``main``
reads and writes them synchronously like any file.  When ``main`` runs in
its worker thread (the default), the main thread, whose event loop runs
meanwhile, starts the child and sees it exit.  When ``main`` runs on the
main thread (``IDRIS2I_1_MAIN_STACK_SIZE=0``), whose event loop does not run
until ``main`` returns, a small Node process started for each child waits
for it and passes its exit status on through a pipe (which costs some 60ms
per child).  The process id is that of the command (``sh -c cmd``), which
gets the default action of every signal.  The exit status is the exit code
of the command, or 128 plus the number of the signal that killed it, as for
``system``.  Output that the child writes to its inherited stdout
or stderr appears when the child writes it, so a program that wants it in
order with its own output flushes stdout first (``fflush stdout``).  Windows
is not supported by ``popen``, ``popen2`` and ``popen2Wait``.

Threads
-------

A JavaScript program has one thread, and a worker thread shares no objects
with it, so an Idris2i-1 closure cannot run in another thread.  The JavaScript
back ends therefore have no ``fork``, and no ``System.Future`` (``fork``,
``await``, ``forkIO``): they stop the program with a message and exit code 1.
The remaining primitives of ``System.Concurrency`` mean something in a program
with a single thread, and have that meaning: a ``Mutex`` is a recursive lock,
a ``Semaphore`` a counter, a ``Channel`` a queue of one value,
``setThreadData`` and ``getThreadData`` a variable, ``getThreadId`` is 0, a
``Barrier`` for one thread does not wait, ``conditionWaitTimeout`` and
``channelGetWithTimeout`` wait for the timeout, and ``channelGetNonBlocking``
looks at the channel.  Whatever would have to wait for a thread that does not
exist (``channelGet`` on an empty channel, ``channelPut`` on a full one,
``semaphoreWait`` at zero, ``conditionWait``, ``barrierWait`` for several
threads) stops the program with a message instead of hanging.  Running the
forked action when ``fork`` is called, or when the program first waits, would
turn programs that use ``sleep`` or a channel to order the threads into
programs that print something else, so it is not done.

Data.Buffer
-----------

Every accessor of ``Data.Buffer`` works with Node, and gives the bytes and
the values of the Chez and RefC backends: ``Int8``, ``Int16``, ``Int32``,
``Bits8`` to ``Bits64``, ``Int64`` (``BigInt``, exact beyond 2^53) and
``Double``, in little-endian order.  ``Int`` has 32 bits with JavaScript (64
with the others) and takes eight bytes in the buffer, as with the others:
``setInt`` writes the value sign-extended to 64 bits, and ``getInt`` reads
the low 32 bits of the eight bytes.  The accessors do not check the offset;
Node raises a ``RangeError`` for one out of bounds.

Directives
----------

The javascript code generators accepts three different directives
about how compact and obfuscated the generated code should be.
The following examples show the code generated for the ``putStr``
function from the prelude for each of the three directives.
(``--cg node`` is used in the examples below, but the behavior is
the same when generating code to be run in browsers with ``--cg javascript``).

With ``idris2i-1 --cg node --directive pretty`` (the default, if no directive is
given), a basic pretty printer is used to generate properly indented
javascript code.

.. code-block:: javascript

    function Prelude_IO_putStr($0, $1) {
     return $0.a2(undefined)($7 => Prelude_IO_prim__putStr($1, $7));
    }

With ``idris2i-1 --cg node --directive compact``, every toplevel function
is declared on a single line, and unneeded spaces are removed:

.. code-block:: javascript

    function Prelude_IO_putStr($0,$1){return $0.a2(undefined)($7=>Prelude_IO_prim__putStr($1,$7));}

Finally, with ``idris2i-1 --cg node --directive minimal``, toplevel function
names are (with a few exceptions like the ones from the static
preamble) obfuscated to reduce the size of the generated javascript
file:

.. code-block:: javascript

    function $R3a($0,$1){return $0.a2(undefined)($7=>$R3b($1,$7));}

``idris2i-1 --cg node --directive no-trampoline`` (or ``--cg javascript``)
makes the tail calls to unknown functions directly, without the trampoline
described in the section on the stack depth above.

``idris2i-1 --cg javascript --directive no-trmc`` compiles the functions with
tail recursion modulo cons as recursions, and ``idris2i-1 --cg node --directive
trmc`` compiles them as loops (see the section on the stack depth).
Likewise, ``--directive no-explicit-stack`` and ``--directive
explicit-stack`` turn the loops on an explicit stack off and on.
