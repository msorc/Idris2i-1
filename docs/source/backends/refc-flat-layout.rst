******************************************
RefC: design of a flat layout (unfinished)
******************************************

This is the design of three changes to the representation of data in the RefC
back end, and the record of the measurements that decided it.  Only the first
part (the field representation table) is implemented; the rest is the plan,
for whoever implements it.  Each stage says what decides the representation,
where the compiler reads it, the memory layout, how every existing path of
the runtime stays correct, what the user writes, and what it is expected to
gain.  The decisions that are still open are listed at the end.

.. contents::
   :local:
   :depth: 1

The problem and the evidence
============================

A record such as

.. code-block:: idris

    record Particle where
      constructor MkParticle
      px, py, vx, vy : Double
      hits : Int

is today one cell of five pointers, and each ``Double`` field is a cell of its
own (16 bytes, counted).  In an ``IOArray Particle`` (or a ``LinArray``, which
is a newtype of it) each slot holds a ``Just`` cell, which holds the record.
Reading a ``Double`` field of an element takes 7 dependent loads, an
allocation and a free (of the ``Res`` of a linear operation) and five count
operations; ``move`` (a few arithmetic operations, then a new record) makes
about 11 ``Double`` boxes and a record.

Phase 0 of the ownership experiment (``benchmark/ownc-phase0/flat`` on the
``ownc`` branch) measured hand edits of the generated C of two programs.  The
programs, the edits and the script that measures them are copied to
``benchmark/flat-layout``.  Instructions (user space, ``perf stat``, median of
3, the full inputs):

======  ====================================================================  ===============  ======
\       W1, ``particles``: 100 000 records, 250 passes                        instructions     A/x
======  ====================================================================  ===============  ======
A       as is                                                                 44 667 557 254   1.00
AD      A with the ``Double`` locals of ``move`` and ``bounce`` unboxed       27 068 908 990   1.65
SA      stage A: AD with the fields of ``MkParticle`` raw in its cell         16 579 551 398   2.69
SA0     SA with the array owned and ``Res`` returned as a C struct            11 072 563 131   4.03
FD      phase 0's flat layout: records inline in the owned array,             3 313 193 027    13.48
        unboxed ``Double`` locals, unboxed ``Res``
======  ====================================================================  ===============  ======

(The fast input, 50 passes, gives 1.66, 2.66, 3.96 and 12.68.)  Per element
update this is 1787 instructions for A, 1083 for AD, 663 for SA, 443 for SA0
and 133 for FD, against 37 for plain C.

SA and SA0 are the estimate of stage A made for this design, before any code
generator work (``benchmark/flat-layout/edits/particles_SA.c`` and
``particles_SA0.c``): ``MkParticle`` is a cell with its header and no pointer
field, followed by four ``double`` and an ``int64_t``; ``move``, ``bounce``,
``fill`` and the reading of ``checksum`` use the fields directly; the array,
its ``Just`` cells and its operations are those of AD.  In SA, a profile
(``perf record``) puts 72% of the instructions in the array operations
(``mread`` 41%, ``prim__arraySet`` 12%, ``write`` 11%, ``sweep`` 8%), 17% in
``move`` and ``bounce``, and 9% in freeing.  The second phase 0 workload, W2
(``events``, a heap of records of three ``Int`` fields), was not measured
with stage A: its ``Int`` values fit in 32 bits, so they are already
immediate (tagged in the pointer) in their fields, and stage A saves only the
tests of the count operations on them.  The gain is expected to be small; the
4.4x of phase 0 on W2 comes from the flat array.

What this says about the order of the work:

- Stage A (raw fields in ordinary cells), together with unboxed ``Double``
  locals, gives 2.7x of phase 0's 13.5x on W1, and is expected to give
  little on W2.  It needs no ownership and no new API, it applies to
  every record with ``Double`` fields (not only those in arrays), and it is
  the representation that the other stages fall back to.  It comes first.
- Without unboxed ``Double`` locals, stage A would make things worse for
  ``Double`` fields: a raw field read for an arithmetic primitive must be
  boxed again, where today the field's box is shared.  Phase 0 measured the
  same thing for the flat layout without unboxed locals (variant F: 1.04x,
  with more allocations than A).  Stage A for ``Double`` fields must land
  after (or with) unboxed ``Double`` locals; for the integer fields it does
  not matter, since those are unboxed already.
- The remaining 3.3x (SA0 to FD) is in the array: the ``Just`` cell made by
  every write, the record cell made by every ``move``, their counts and
  frees.  The flat array (stage B) removes them, but only if the elements
  that it reads are not boxed again, which needs flat values in locals and
  parameters (stage C).  B alone (reads boxed into cells) would allocate a
  ``Just`` and a record cell per read, where SA shares the array's: we
  expect it to be slower than SA on W1 (not measured).  **B and C must be
  done as one stage.**


The field representation table (implemented)
============================================

For each data constructor the compiler computes what the declared type of
each of its arguments says about the values that it holds at run time
(``Core.CompileExpr.FieldRep``):

- ``FPrim t``: always a value of the fixed width primitive type ``t``
  (``Int``, ``Int8`` to ``Int64``, ``Bits8`` to ``Bits64``, ``Char``,
  ``Double``);
- ``FBoxed``: anything else.

The table is a fact about the program, not a layout.  A back end may store an
``FPrim`` field unboxed or ignore the table (treat every field as
``FBoxed``), which is always correct.  No back end uses it yet.

The rule
--------

``Core.FieldRep.conFieldReps`` normalises the type of the constructor and
walks its Pi binders, up to the constructor's arity.  An erased binder gives
``FBoxed`` (it is not a field).  The other binders are classified by the
normal form of their type, in which each earlier binder is a stuck variable:

- a primitive type: ``FPrim t``, except ``Integer``, ``String`` and
  ``%World``, which are boxed;
- a type constructor all of whose data constructors are flagged ``ENUM k``
  (all of them nullary, so that the enumeration optimisation of
  ``Compiler.Opts.Constructor`` compiles them to constants):
  ``FPrim (enumPrimType k)``, that is ``Bits8``, ``Bits16`` or ``Bits32``,
  the type of those constants (``enumTag`` uses the same function, so the
  two cannot disagree).  ``Bool`` fields are ``Bits8``;
- a type constructor with one data constructor that is a newtype (compiled
  away to its field ``pos``) whose own table has ``FPrim t`` at ``pos``:
  ``FPrim t``.  The table of the newtype does not depend on the arguments of
  the type, so ``Identity Double`` is boxed (the field of ``Identity`` is a
  type variable), while ``record Meters where meters : Double`` is a
  ``Double``;
- anything else is boxed: a type variable or any other stuck term (a type
  that depends on an earlier field, ``if b then Int else Double``), a
  function, ``Lazy`` and ``Inf`` (``NDelayed``: the field holds a thunk),
  ``Type``, any other data type (``Nat``, which ``%builtin Natural`` makes an
  ``Integer``; ``Maybe Double``; pairs; ``Vect``), a type that is only
  declared (``data T : Type`` before its definition, or a type of the same
  mutual block defined after this one).

The rule is decidable from what the context has when the data declaration is
elaborated, and conservative: the answer is ``FBoxed`` whenever the type does
not reduce to one of the recognised forms.

Where it is computed and how it survives
----------------------------------------

- **When.** ``TTImp.ProcessData`` calls ``setConFields`` for each constructor
  of a data type at the end of its declaration, after the constructor flags
  (``calcConInfo``) and the erased arguments (``updateErasable``).  The table
  of all the arguments (erased ones included, as ``FBoxed``) is saved as the
  flag ``ConFields`` of the constructor (``:di`` shows it as ``confields``).
  Records, interfaces (their dictionaries), and data types declared by
  elaborator scripts all go through ``processData``, the only caller of
  ``addData``.
- **Once.** It is not computed again elsewhere.  In another module the types
  of the fields may reduce differently (a definition that is ``export`` but
  not ``public export`` does not reduce outside its module: see ``Opaque`` in
  the test), and a type of a mutual block may be known there when it was not
  at the declaration.  Every module that compiles a use of the constructor
  must see the same table, so the table is the one saved with the
  constructor.
- **Compiled definition.** ``Compiler.CompileExpr.toCDef`` gives ``MkCon`` the
  table without the erased arguments (the arguments of a constructor
  application in ``CExp``), or the whole table for a newtype (whose
  applications keep all their arguments until they are compiled away).  A
  constructor without the flag, a table of the wrong length, the type
  constructors (``MkCon Nothing``) and the intrinsic constructors
  (``_builtin.CONS``, ...) get ``FBoxed`` everywhere.  The table is carried
  by ``MkNmCon``, ``MkLCon`` and ``MkACon``, so every code generator has it
  in its ``CompileData``.
- **TTC.** Both the flag and ``MkCon`` are in the TTC file (the TTC version
  changed).  A program compiled from modules gets each constructor's table
  from the module that declares it.  The hash of a ``NamedDef`` (used by
  incremental compilation to decide what to rebuild) includes the table.
- **Dumps.** ``--dumpcases``, ``--dumplifted`` and ``--dumpanf`` show it as
  ``fields [Double, Double, Int]``; ``:di`` shows the flag and the compiled
  table.
- **Cost.** One normalisation of each constructor's type.  Type checking a
  copy of ``libs/prelude`` takes 0.008% more instructions.

The test ``tests/codegen/fieldrep001`` pins the table of: type variables and
all the primitive types; an indexed family; a dependent record; erased and
linear fields; enumerations (``Bool`` and one from another module);
newtypes (one of ``Double`` from another module, ``Identity Double``, a
record with ``noNewtype``); type synonyms that do and do not reduce;
``Lazy``, ``Inf`` and functions; mutual types, including an enumeration used
before its declaration in its mutual block; nested types; an interface
dictionary; records from another module, read from its TTC file.

What the table does not cover
-----------------------------

- **Intrinsic constructors.** ``Compiler.Opts.Constructor.tryIntrinsic``
  renames the constructors of every *list shaped* type (two constructors, of
  0 and 2 unerased arguments, *or a single constructor of two*: every record
  of two fields, every pair) to ``_builtin.NIL``/``_builtin.CONS``, and of
  every *option shaped* type to ``_builtin.NOTHING``/``_builtin.JUST``, at
  their uses.  Of the types of the test, ``V2`` (two ``Double``), ``VCons``,
  ``MkDep``, ``MkEL``, ``MkAliases`` and ``Node`` are renamed.  The renamed
  constructor has no table of its own, and ``Compiler.Opts.Identity`` treats
  functions that convert between two such types (``List Double`` to a list of
  ``Double`` of its own) as the identity, since their constructors have the
  same name: with ``data DL = DNil | DCons Double DL``, the conversion
  ``toD : List Double -> DL`` is compiled away and a function on ``DL`` is
  applied to the list itself.  Stage A must stop the renaming of a
  constructor whose table has an ``FPrim`` field (see below).
- **Sums of flat values** and the element types of arrays: the table is per
  constructor, while the layout of an array slot (stage B) depends on the
  element *type* (``Maybe Particle``).


Stage A: raw fields in constructor cells
========================================

The rule
--------

A field is stored raw in the cell of its constructor when its table entry is
``FPrim t`` and the back end chose to store ``t`` raw.  The proposal is to
store raw every ``FPrim`` type: ``Double`` (always a box today), ``Int``,
``Int64``, ``Bits64`` (boxed beyond 32 bits), ``Int32``, ``Bits32`` (boxed on
32 bit platforms), and the smaller ones and ``Char`` (always immediate today;
raw saves the immediate tests of the count operations and costs nothing).  A
directive ``refc-no-raw-fields`` turns it off (every field boxed, as now), and
``refc-no-raw-double-fields`` only for ``Double``, in case unboxed
``Double`` locals are switched off.

Memory layout
-------------

A cell keeps the layout of ``Idris2_Constructor`` up to its pointer fields:

.. code-block:: c

    struct {
      Idris2_header header;   // count, CONSTRUCTOR_TAG, size class, flags
      uint16_t total;         // the number of POINTER fields
      int16_t tag;
      Idris2_Value *args[np]; // the boxed fields, in their order
      // (a named constructor, tag -1: its name, as now, in args[np])
      // the raw fields: largest first, each aligned to its size
    };

- ``total`` is the number of pointer fields, so the release walk
  (``idris2_releaseValue``), the marking of shared values
  (``idris2_markShared``), the leak walk and the debug printer, which loop
  over ``args[0 .. total-1]``, need no change and never look at a raw field.
- ``idris2_freeValue`` uses the size class in the header, not ``total``:
  freeing needs no change either.
- The raw fields are sorted by decreasing size (8, 4, 2, 1 bytes), ties kept
  in field order, so that there is no padding between them; the first starts
  at the end of the pointer fields rounded up to 8 bytes.  On 64 bit
  platforms the end of the pointer fields is always a multiple of 8.  On 32
  bit platforms (``args`` of 4 bytes) there may be 4 bytes of padding before
  an 8 byte field: ``double`` and ``int64_t`` need 8 byte alignment on some 32
  bit ABIs (ARM EABI).  The cells of the pools are 8 byte aligned
  (``IDRIS2_ALLOC_UNIT``), but ``idris2_allocLarge`` (cells of more than 256
  bytes) aligns to ``sizeof(void *)``, which must become 8.  The
  generated code declares one C struct per constructor with raw fields
  (``struct Idris2_con_Main_MkParticle``) and lets the C compiler place the
  fields (``offsetof``); the order above is only to make the structs small.
- ``MkParticle`` is 8 + 4 × 8 + 8 = 48 bytes (one cell of 6 units) instead of
  a 48 byte cell and four 16 byte boxes.

The code generator
------------------

``RefC.idr`` builds a map from constructor names to tables from the
``MkACon`` definitions of the program (``compiledFieldsOf`` in
``Core.FieldRep`` gives the table of a constructor from the context, for a
constructor that is not in the definitions of the unit being compiled, as
with incremental compilation).  Then:

- **Construction** (``ACon``): allocate ``sizeof`` the constructor's struct
  (a new ``idris2_newConstructorSized(bytes, np, tag)``), store the pointer
  fields as now, store each raw field from its C value: from an unboxed local
  directly, from a value with ``idris2_vp_to_Double`` & co. followed by the
  release of the value (the release is usually of an immediate, or of a box
  that is freed at once).
- **Matching** (``AConCase``): a raw field is bound as an unboxed local of its
  type, read from the struct.  This is the new fact for ``Unbox.idr``: the
  variables bound by an alternative to ``FPrim t`` fields are C values of
  ``t``, like the ``let`` of an integer operation.  A use that needs a value
  boxes it (one use only, as for the ``let``\ s); the other uses read the C
  value.  When the cell is unique and is freed in the alternative, nothing is
  released for the raw fields.
- **Reuse** of cells: a cell is reused by name as now (same constructor, same
  struct).  With ``refc-size-reuse`` the key becomes the size of the struct
  and whether it is named: constructing writes ``total``, ``tag`` and every
  field, so two constructors of the same size can share a cell whatever
  their numbers of pointer fields.
- **Static values** (``StaticVal``): a constant with raw fields is a static
  instance of the constructor's struct with the ``IDRIS2_STOCKVAL`` header.
- **TRMC** (``refc-no-trmc``): a hole is a pointer field, so only a
  ``FBoxed`` field may be the hole of a call (the recursive positions are of
  the data type, hence boxed; this must be checked, not assumed).
- **Workers** (``idris2_raw_*``): unchanged.  The parameter types that
  ``Unbox.idr`` reads from the context are not affected.
- **Intrinsic renaming**: ``tryIntrinsic`` gets the context and leaves the
  name of a constructor whose table has an ``FPrim`` field (it keeps its
  ``ConInfo``, so the Scheme and JavaScript back ends, which emit pairs and
  lists from ``CONS``, generate the same code).  This changes the ``CExp`` of
  every back end in one way: ``Compiler.Opts.Identity`` no longer finds that
  a conversion between such a type and a list or pair is the identity.  That
  is only correct when the representations agree, which they no longer do in
  RefC, and the ``CExp`` is shared by the back ends (it is in the TTC file).

Correctness on the existing paths
---------------------------------

- **Polymorphic code** never looks inside a cell without matching on its
  constructor, and a match names the constructor: generic code (``map`` over
  a ``List Particle``) moves cells as ``Idris2_Value *``, which they still
  are.  Closures, ``idris2_dispatch`` and partial applications hold cells as
  values; a raw field is never a closure argument.
- **Thread sharing**: the shared flag is set by the walk over the pointer
  fields; raw fields hold no reference, so nothing more is shared.  Counts of
  shared cells are atomic as before.
- **Erased fields**, **newtypes** and **enumerations** never have a cell
  field (they are dropped or compiled away before ``CCon``).  A record with
  one field is a newtype unless ``noNewtype``; then it is a cell with one raw
  field.
- **``believe_me``** between two data types is only correct when their
  constructors have the same tables (today: the same arities).  Matching a
  ``MkA`` cell (raw ``Double``) as a ``MkB`` (boxed field) reads a double as
  a pointer.  The libraries must be checked for such coercions before stage
  A is enabled.  A first ``grep believe_me`` in ``libs`` found coercions
  between instances of the same type family (other indices, as in
  ``Data.Primitives.Views``), of numbers and pointers, and of proofs: the
  tables agree in all of them.  The ``Identity``
  optimisation is the compiler's own ``believe_me`` and is handled above.
- **FFI and ``%export``**: a C function that receives a constructor (through
  ``AnyPtr`` or a ``CFUser`` type) and reads ``args[i]``, or builds one with
  ``idris2_newConstructor``, breaks for types with raw fields.  The runtime
  itself builds only constructors of boxed fields (lists of strings, pairs of
  strings, ``Just``).  The generated header gives the structs of the
  constructors with raw fields, and the RefC FFI documentation must say to
  use them.  ``%foreign`` with ``Struct`` (``CFStruct``) is unaffected.
- **Reflection and ``prim__``**: constructors made at compile time (by the
  evaluator of elaborator scripts, or the Scheme evaluator) are terms, not
  RefC cells; the table does not apply to them.  No primitive of the RefC
  runtime makes or reads a user constructor.
- **Other back ends** (Chez, Racket, Gambit, JavaScript, the interpreter and
  the Scheme evaluator used at compile time) ignore the table.  The only
  change in their ``CExp`` is the one of the intrinsic renaming above.
- **32 bit platforms**: the struct layout is left to the C compiler; the
  allocator's 8 byte alignment covers ``double`` and ``int64_t``.

Expected gain
-------------

On W1, 1.6x over unboxed ``Double`` locals alone (SA against AD), and 2.7x
over the code of today.  Memory: one 48 byte cell per particle instead of 112 bytes.  On
records of integers that fit in 32 bits (W2) almost nothing.  Every program
with ``Double`` fields in its records gains, whatever its data structures
(trees of records, lists of points), since the gain is in building and
reading the records.


Stages B and C: flat arrays and flat values
===========================================

These two go together (see the evidence above).

Where the element type comes from: the options
-----------------------------------------------

The array primitives (``prim__newArray``, ``prim__arrayGet``,
``prim__arraySet``) are polymorphic in an erased type, and the library
functions above them (``Data.IOArray``, ``Data.Linear.Array``'s methods,
which take the element type as an erased implicit) are compiled once for
every element type.  The element type is gone in ``CExp``.  An array is
created in one function and read in others, so whatever decides that it is
flat must decide it the same way at both ends, or the array must say how it
is laid out.

1. **Static: the erased type at the primitive, after specialisation.**
   ``%spec elem`` on the library functions (the partial evaluator already
   specialises by erased type arguments: the example of ``%spec`` in the
   reference is ``%spec a`` on ``identity : List a -> List a``) makes copies
   in which the type of the primitive is closed; ``Compiler.CompileExpr``
   would record it in the primitive call.  Per access, the C is that of phase
   0 (a bounds check, then loads at fixed offsets).  But a copy is made only
   where every function between the user's call and the primitive is
   specialised: ``newLinArray``'s continuation, the methods of the ``MArray``
   implementation (I did not check whether ``%spec`` can be given to a
   method of an implementation; if not, they would become ``%inline``
   wrappers of specialised functions), and any generic code of the user.  Where one is not, the creation is generic while
   an access may be specialised, or the reverse: the two disagree about the
   layout, which is memory corruption.  Rejected as the source of truth; kept
   as the way to make accesses fast.
2. **A layout descriptor in the array, passed at run time.**  The array
   records, at creation, the layout of its slots (a pointer to a static
   descriptor and its 64 bit id).  Generic code reads and writes through the
   descriptor (boxing a slot into cells on read, unboxing on write); code that
   knows the layout statically tests the id (one load and a compare, always
   true in practice) and accesses the slot directly.  The creation must know
   the layout of the element type: it gets a value ``Layout elem``, an
   ``auto`` implicit argument of the functions that create arrays, resolved
   by the elaborator where the type is known.
3. **A new primitive array type** (``FlatArray``) whose element type must be
   closed at every use, checked by the compiler.  The C is that of phase 0,
   with no test.  But generic code over it is impossible without a
   descriptor, it is a second array API, and the phase 0 programs (written
   against ``Data.Linear.Array``) gain nothing.  Rejected.

The decision is 2, with 1's specialisation to make the descriptor constant at
the accesses.  The C per element access:

- **Descriptor known** at the access (a constant after inlining or
  ``%spec``):

  .. code-block:: c

      if (a->layoutId == UINT64_C(0x8f3e...) /* Maybe Main.Particle */) {
        char *slot = a->slots + i * 48;  /* after the bounds check */
        tag = slot[0]; px = *(double *)(slot + 8); /* ... */
      } else {
        v = idris2_flatGetGeneric(a, i); /* as below */
      }

  This is phase 0's access plus one load and a compare that is always true
  in practice.
- **Descriptor not known** (generic code): ``idris2_flatGetGeneric(a, i)``,
  a call that boxes the slot into a ``Just`` cell and a record cell (two
  allocations per read; a write unboxes and frees the cells it is given if
  they are unique).
- **Array created by generic code, read by specialised code**: the test
  fails and the generic path is taken: the cost of today plus the test.

What the user writes: nothing, for arrays of primitive types, of single
constructor records whose fields are all ``FPrim``, and of ``Maybe`` of
those, created at a known type.  Generic code that creates arrays gets boxed
arrays unless it adds ``{auto l : Layout elem}`` to its own type.

The layout descriptor
---------------------

- ``Layout : Type -> Type`` is an opaque type of ``Data.IOArray.Prims`` (no
  exported constructor) whose values describe a slot: ``LBoxed``,
  ``LPrim PrimType``, ``LRecord name [PrimType]``, ``LMaybe Layout``.
- Its hints: ``%defaulthint boxedLayout : Layout a`` (taken when nothing
  else applies, in particular for a type variable); hand written hints in
  ``base`` for the primitive types and for ``Maybe`` of a flat layout;
  and a hint that the compiler generates in ``ProcessData`` for each single
  constructor record whose fields are all ``FPrim`` (from the table, so the
  descriptor cannot disagree with the cells of stage A).  Must be checked:
  that a ``%defaulthint`` is not taken for a ``Layout ?t`` whose ``?t`` is
  solved later in the same elaboration.
- ``prim__newArray`` gets the descriptor (a new primitive,
  ``prim__newArrayL : Layout a -> Int -> a -> PrimIO (ArrayData a)``; the
  old one stays, boxed), and so do ``prim__arrayGet``/``prim__arraySet``
  (the layout that the caller expects; the array's own one decides).  The
  Scheme and JavaScript back ends ignore the descriptor.
- In RefC an array is one block: header, size, layout id, descriptor
  pointer, then the slots.  A slot of ``Maybe Particle`` is a tag byte
  (padded to 8) and the record's fields (48 bytes, against 8 + 16 + 48 +
  4 × 16 today).  ``LBoxed`` arrays are the arrays of today.
- ``prim__arrayCopy`` copies bytes between arrays of the same layout id, and
  goes through the descriptor otherwise.
- The release of an array walks its slots only for the pointer fields of its
  layout (none for a flat record).  The shared flag of a flat array is set
  on the block alone.

Flat values in locals, parameters and results (stage C)
-------------------------------------------------------

The values read from a flat array must stay flat, or the array gains nothing
(see above).

- A local of a flat record type (bound by matching the result of a flat
  read, or by constructing the record) is a C struct; a field use is a
  member.  It is boxed (a stage A cell) only where it escapes: stored in a
  boxed field, passed to an unknown function or a closure, returned from a
  function whose result is a value.
- Workers (``idris2_raw_*``) take and return flat records as C structs, as
  they take C integers now.  Phase 0 showed that a flat value is a "copyable
  value": a record read from an array and kept there is copied, not shared,
  and needs no ownership (it is not linear).
- ``Res``, ``LPair`` and ``#`` of a linear operation are returned as C
  structs (F0 of phase 0); this needs nothing more than that their result is
  matched at once, which the ``Res`` of the array operations always is.
- **``musttail``**: a struct of more than 16 bytes is passed in memory by the
  SysV ABI, and GCC refuses the jump ("callee required more stack slots than
  the caller").  The proposal: a jump that passes a flat value larger than
  two registers writes it into a buffer of the worker (like the arguments of
  ``idris2_pendingTailCall``) and passes its address; the callee copies it
  out before anything else.  This keeps the jump without an allocation, and
  is correct because nothing runs between the copy in and the copy out.
  Phase 0 instead used plain calls (safe there only because the depth was
  bounded) or boxed the value (one allocation per element).

Expected gain
-------------

Phase 0's FD over SA: 5x on W1 (13.5x over today), and 4.4x on W2 (F
over A).  The gap with plain C (3.6x on W1, 6x on W2) is in what stays:
boxed indices of library functions without workers, the tag test of each
read, ``Res`` structs copied through memory, calls instead of jumps.


Alternatives rejected
=====================

- **The table in ``ConInfo``** (the information that a ``CCon`` carries at
  each use): it would be repeated at every use, and ``ConInfo`` is shared by
  the constructors of different types that are renamed to the same intrinsic.
- **A side table in the context** (a map from names to tables, saved in the
  TTC file): it would need its own TTC section and merging on import, while
  the flags and the compiled definition already are saved per name.
- **Computing the table in ``toCDef``** (when the constructor is compiled):
  the type of the constructor is there, but its uses in the same module may
  be compiled before it (stage A needs the table at each use, for the
  intrinsic renaming), and a constructor recompiled in another module would
  get its table from types that may reduce differently there.
- **Including ``Integer`` and ``String`` as raw**: they are pointers to cells
  anyway; nothing would be gained.
- **Inferring field types from uses** (as ``Unbox.idr`` must not do for
  parameters): the type of a field may depend on another field.
- **Layouts derived per type in the code generator** without a descriptor in
  the array: see option 1 above; the creation and the accesses of an array
  may be compiled with different knowledge of its type.
- **Ownership (linear records) as the condition of flatness**: the array of
  records programs read an element and keep it in the array, which a linear
  record forbids; flat records must be copyable values.


Open questions
==============

1. **The API change of ``MkCon`` and friends**: back ends outside this
   repository that match on ``MkNmCon`` (positionally) have one more
   argument.  Alternative: keep the four constructors as they were and
   expose the table through a function of ``CompileData``.  The table being
   in the definition is what makes it survive every pass, so the change was
   made.
2. **Enumerations as ``FPrim Bits8``**: correct for every back end (the
   enumeration optimisation is in the shared ``CExp``), but it ties the table
   to that optimisation.  If it is ever made back end specific, the table
   needs an ``FEnum k`` instead.
3. **Newtypes see-through only for monomorphic newtypes**: ``Identity Double``
   could be ``Double`` by substituting the type arguments into the newtype's
   field type.  Not done: the table would depend on the arguments of a type,
   which no use site has.
4. **Raw ``Char`` and small integers**: they are immediates today, so raw
   storage saves little; storing them raw makes every match bind C values,
   which is what ``Unbox.idr`` wants anyway.  Decide with stage A's
   measurements (the self-build of the compiler has many records of
   ``Int``\ s and ``Bool``\ s).
5. **``believe_me`` audit** before stage A is on by default (see above).
6. **``%defaulthint`` behaviour** for ``Layout`` (stage B), and whether the
   generated ``Layout`` hints slow down the search for other hints.
7. **Sums**: arrays of ``Either Int Double``, or records with an enumeration
   and a payload, are not flat in this design.  ``LMaybe`` is the only sum.
