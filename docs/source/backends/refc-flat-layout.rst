******************************************
RefC: design of a flat layout (unfinished)
******************************************

This is the design of three changes to the representation of data in the RefC
back end, and the record of the measurements that decided it.  Implemented
so far: the field representation table, the ``NoIntrinsic`` flag, and the
runtime side of stage A (the alignment of large values, a test of the
runtime with stage A cells); the rest is the plan,
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

- **Intrinsic constructors**: see the next section.
- **Sums of flat values** and the element types of arrays: the table is per
  constructor, while the layout of an array slot (stage B) depends on the
  element *type* (``Maybe Particle``).


Intrinsic constructors and the identity optimisation
----------------------------------------------------

``Compiler.Opts.Constructor.tryIntrinsic`` renames the constructors of every
*list shaped* type (two constructors, of 0 and 2 unerased arguments, *or a
single constructor of two*: every record of two fields, every pair) to
``_builtin.NIL``/``_builtin.CONS``, and of every *option shaped* type to
``_builtin.NOTHING``/``_builtin.JUST``, at their uses.  The renamed
constructor stands for the constructors of every type of its shape, with
boxed fields.  Two optimisations then treat constructors of different types
as the same: ``Compiler.Opts.Identity`` finds that a conversion between two
such types is the identity (with ``data DL = DNil | DCons Double DL``, the
conversion ``toD : List Double -> DL`` was compiled away, and a function on
``DL`` applied to the list itself), and CSE may share two equal applications
of constructors of different types.  Both are wrong once one of the types
stores a field raw.

**Implemented** (ahead of stage A, since it is in the shared ``CExp``): when
a data type is declared, if its constructors are list or option shaped and
one of them has a ``rawField`` (``Double``, ``Int``, ``Int64``,
``Bits64``), all of them get the flag ``NoIntrinsic``
(``Core.FieldRep.setNoIntrinsic``, logged by
``--log declare.data.nointrinsic:1``), and ``tryIntrinsic`` leaves the
constructors so flagged, and the cases on them, as they are.  They keep
their ``ConInfo`` (``CONS``, ``JUST``, ...), which is what the Scheme and
JavaScript back ends use to emit pairs and lists, and RefC to represent
``NIL`` and ``NOTHING`` by ``NULL``.  All the constructors of a type are
flagged, so that a type's constructors are all intrinsic or none.  The test
``codegen/intrinsic001`` shows it: the conversions to ``DL``, ``V2``,
``MI`` (a ``Maybe``-like of an ``Int``) and ``BL`` (a list of ``Bits64``)
are now functions, those to a list of ``Char`` and to a polymorphic
``Maybe``-like are still compiled away.

How often it hits, and what it costs:

- the libraries: 6 types (``Data.IOArray.IOArray``, a record of an ``Int``
  and the content; ``System.File.Meta.Timestamp``; ``System.ExitCode``;
  ``Network.Socket.Data.UDPAddrInfo``; ``Prettyprinter.Doc.PageWidth``;
  ``Data.String.Position.ValidPosition``);
- the compiler: 7 types (``Compiler.ANF.AVar``, ``Core.TT.Primitive
  .Precision``, ``Compiler.ES.Stack.St``, ``Compiler.ES.TailRec.TcGroup``,
  ``Core.Metadata.TTMFile``, ``Levenshtein.Target``, ``PageWidth``), all
  because of ``Int`` fields; ``FilePos`` is a pair of ``Int``, polymorphic,
  and stays intrinsic;
- the test programs of the Chez and Node pools: three use such a type
  (``chez/arrayperf001``, ``node/arrayperf001``, ``node/trmc_browser_stack``);
  their generated Scheme and JavaScript are identical to those of the base
  compiler but for the version line.  The other programs of those pools
  declare no such type, so their ``CExp`` is unchanged;
- the compiler compiled by itself: no function is compiled away or kept that
  was not before (two small lambdas of ``callsOf`` and ``Compiler.ES.Stack
  .push`` are now functions of their own, the rest of the 3 338 changed
  lines are the names and tags in comments and cells, and renumbered CSE
  constants); type checking ``libs/prelude`` takes 0.0001% more
  instructions (25 170 526 835 against 25 170 496 429, median of 3).  The
  stage 3 compiler's C is identical to stage 2's.

Including ``Int`` costs the identity optimisation nothing measurable, so it
stays in ``rawField``.

Stage A: raw fields in constructor cells
========================================

Implemented (``Compiler.RefC.RefC``, ``RawLayout``; ``Compiler.RefC.Unbox``,
``rawFields``), on by default.  What the implementation settled, where it
differs from the plan below:

- **Layout.** Every ``rawField`` type is 8 bytes, so the raw fields are in
  field order, 8 bytes each, from ``IDRIS2_RAW_OFFSET(np)`` (the end of the
  pointer fields rounded up to 8): ``idris2_rawField(c, np, j, T)`` and
  ``idris2_newRawConstructor(np, nr, tag)`` in ``memoryManagement.h``.  No
  struct per constructor is declared.  The constructors told apart by their
  names (tag -1) keep boxed fields.
- **Reading.** The raw fields that a branch uses are read first, before the
  cell may be freed or taken over.  Each one is a C number when the
  unboxing keeps it one (it does unless it has two uses as a value: a raw
  field costs nothing to unbox), otherwise a new value, which the branch
  owns.  ``valueType`` now sees through a ``case`` on constructors, so the
  projection of a raw field (``p.x``, a ``case`` in a ``let``) is a C number.
- **Building.** A raw field is stored from a C number, from the value of a
  variable that is not one (``idris2_vp_to_Double``), which is released when
  only raw fields took it.  The unboxing counts a raw field of a
  constructor as a use as a C number, so parameters and ``let``\ s stored
  there stay unboxed.
- **Reuse.** By name as before; with ``refc-size-reuse``, the key holds the
  layout, so a cell is taken over by a constructor whose fields are in the
  same slots only.  A raw field given the number read from the same slot of
  the cell taken over is not stored again; the copy made when the cell is
  shared copies the raw fields with ``idris2_copyRawFields``.
- **Static values.** A constant with raw fields whose raw fields are
  literals is static data (see the follow-up below).
- **Tail recursion modulo cons.** The hole is the pointer slot of the
  field; a field of the call that is raw (impossible in a well typed
  program) makes the call an ordinary one.
- **Closures, partial applications, polymorphic code** need nothing: a
  constructor is always applied in full in ANF (the compiler eta-expands
  it into a lambda), and generic code moves cells as values.

Measured (instructions:u, median of 3, the full inputs; ``noraw`` is the
same compiler with ``--directive refc-no-raw-fields``, which runs the same
instructions as the branch base on each of these programs, to a few hundred):

============  ===============  ===============  =========
program       raw              noraw            noraw/raw
============  ===============  ===============  =========
particles     16 093 789 298   33 682 282 048   2.09
events        44 472 072 689   47 986 144 155   1.08
nbody          1 192 707 306    3 740 710 989   3.14
mandel         1 685 877 585    8 425 541 218   5.00
mergeA        17 264 667 154   17 264 667 134   1.00
mergeB        16 426 253 315   17 562 686 120   1.07
treeA         10 454 310 190   10 454 310 217   1.00
treeB          9 754 299 741   10 464 760 846   1.07
============  ===============  ===============  =========

(``benchmark/flat-layout/stagea/run.sh``.)  The five programs of
``benchmark/benchmarks`` run the same instructions (their records have no
such fields).  The compiler compiled by itself type checks ``libs/prelude``
in 24 671 203 155 instructions against 25 071 997 235 with the directive
(1.6% fewer; its types with ``Int`` fields, ``Compiler.ANF.AVar`` among
them, are now raw), and its C compiles in 757 s of CPU against 780 s
(no unit slower by more than 0.5 s).

On particles, stage A on the branch base (which unboxes Doubles since) runs
2.78 times fewer instructions than phase 0's A (44 667 557 254), more than
the hand edit SA (2.69): the unboxed Double locals of the branch base reach
more code than the edit did (``checksum``'s accumulator, the arithmetic of
``fill``), and nothing in the edit was left out.  ``mergeA``/``treeA`` use
``List Int`` and a polymorphic tree, whose fields are type variables, and
gain nothing; ``mergeB``/``treeB`` declare their own types of ``Int``.


The rule
--------

A field is stored raw in the cell of its constructor when its table entry is
``FPrim t`` with ``t`` one of ``Double``, ``Int``, ``Int64`` and ``Bits64``
(``Core.CompileExpr.rawField``): the values that are a box on the heap
(``Double`` always, the others beyond 32 bits) or need a test to be read
from a pointer slot.  The smaller integers, ``Char``, ``Bool`` and the other
enumerations stay immediate values in pointer slots, as now: storing them
raw would save only the immediate tests of the count operations (decided by
the coordinator; to be revisited with the self-build numbers of stage A).
``Int32`` and ``Bits32`` are boxed on 32 bit platforms only, and stay in
pointer slots too.  A directive ``refc-no-raw-fields`` turns it off (every
field boxed, as now), and ``refc-no-raw-double-fields`` only for
``Double``, in case unboxed ``Double`` locals are switched off.

The same predicate decides which types keep their constructor names (see
`Intrinsic constructors and the identity optimisation`_): the two must
agree, since a cell is laid out by the table of the constructor that its
``CCon`` names.

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
- **Intrinsic renaming**: done ahead of stage A (``NoIntrinsic``, see
  `Intrinsic constructors and the identity optimisation`_).

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
  a pointer.  See `Coercions: the audit`_.  The ``Identity`` optimisation
  and CSE are the compiler's own coercions and are handled by
  ``NoIntrinsic``.
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

Coercions: the audit
--------------------

Every ``believe_me``, ``prim__believe_me``, ``unsafeCoerce``,
``really_believe_me`` and ``assert_linear`` in ``libs/`` and ``src/``
(``git grep``, 67 lines, November 2026) was checked for a coercion between
two data types whose stage A layouts differ.  There is none:

- between instances of one type family, which have the same constructors:
  ``Data.Primitives.Views`` (``DivBy``, ``IntegerPred``, ``IntPred`` at
  other indices), ``Data.String.strM`` (``StrM``), ``Data.Fin`` (the
  ``IsJust`` and ``So`` proofs), ``Tree.toRelative`` (``Tree`` at another
  root, in contrib and in ``src/Libraries``), ``Cast (Doc Void) (Doc ann)``,
  the papers' ``thin``/``closed`` (terms at other scopes), the compiler's
  ``CExp`` and ``Term`` at other scopes (``Compiler.Inline.anyScope``,
  ``Compiler.Opts.EtaIO``, ``Core.TT.Term.compatTerm``,
  ``Core.Name.Scoped.embed``), and ``IsVar``/``Var`` proofs of other indices
  (``Core.TTC.mkPrf``, ``Compiler.CaseOpts.renameVar``,
  ``Libraries.Data.VarSet.unsafeToList``, where ``Var`` is a newtype of
  ``Nat`` and ``VarSet`` a synonym of ``NatSet``);
- of proofs and of erased values: ``Decidable.Equality`` (``Refl``,
  ``Void``), ``Data.Int.Order``, ``System`` (``Oh``), ``Deriving.Show``
  (functions on erased views), ``Data.Linear.Interface.consume``,
  ``assert_linear``;
- of numbers and pointers: ``Prelude.Types`` (``Integer`` to ``Nat``, both
  ``Integer`` at run time), ``PrimIO.prim__castPtr``/``prim__forgetPtr``,
  ``System.exitWith`` (an ``IO`` action of another result type);
- of a value back to the type it was cached at
  (``Core.Context.fromCached``).

``assert_total`` and ``assert_smaller`` do not change a type.

User code: a ``believe_me`` between two data types whose tables differ
(``FPrim`` in one where the other has ``FBoxed``, at a field that stage A
stores raw) is undefined behaviour, as it already is between types that the
enumeration and newtype optimisations represent differently (a ``Bool`` and
a two constructor type of another number of constructors, a newtype and its
field's type).  This goes in the ``believe_me`` documentation and in
refc.rst.  The cheap debug check: under a directive
``refc-check-layout``, a match on a constructor with raw fields tests that
the cell's ``total`` is the constructor's number of pointer fields and
crashes with the constructor's name otherwise (one compare per match; a
coercion from a cell of another type of the same number of pointer fields
is not caught, but most are).  It is part of stage A's code generation.

The runtime: review
-------------------

The paths of the runtime that look inside a constructor cell, checked for
the assumption that a cell is ``header + total * sizeof(void *)`` bytes:

- ``releaseOne`` (``idris2_releaseValue``, ``releaseDeep``):
  ``args[0 .. total-1]``, then ``idris2_freeValue``, which takes the size
  from the class in the header (``cls`` 0: a large value, ``free``).
- ``idris2_markShared``, the leak walk (``leakCheck``) and the debug printer
  (``describeValue``): ``args[0 .. total-1]``.  The printer says "(1
  field)" for a cell with one pointer field and raw fields: it counts the
  pointer fields only.
- ``idris2_constructorName`` reads ``args[total]``: a named constructor
  (tag -1) keeps its name right after its pointer fields, before the raw
  fields.
- ``idris2_removeReuseConstructor`` and the reuse in the generated code:
  a count and ``idris2_freeValue``.  With ``refc-size-reuse`` the key of a
  reusable cell must be its size in bytes (``RefC.idr``, stage A).
- ``idris2_newConstructor`` and ``idris2_newNamedConstructor`` compute the
  size from ``total``: stage A adds ``idris2_newConstructorSized``; the
  runtime's own uses (lists and pairs of strings, ``Just``, futures) have
  boxed fields only.
- The statistics (``IDRIS2_REFC_STATS``) count allocations by class, not by
  field.
- Static values (``IDRIS2_STATIC_CONSTRUCTOR``, the predefined nullary
  constructors) are never walked (immortal, and ``idris2_markShared`` skips
  ``IDRIS2_STATIC_FLAG``).

Nothing else in ``support/refc`` reads ``total`` or ``args`` of a
constructor (``git grep``).  One fix was needed:
``idris2_allocLarge`` (values of more than 256 bytes, and every value under
Valgrind or with ``IDRIS2_REFC_NO_POOLS``) aligned to ``sizeof(void *)``,
4 bytes on 32 bit platforms; it now aligns to 8 (``IDRIS2_LARGE_ALIGN``),
like the pools.  ``tests/refc/rawcells001`` builds cells of stage A by hand
against the runtime's sources (no code generator), with raw bytes that look
like pointers to live values, and checks release, shared-flag marking, the
leak walk (a constant whose raw field points to a leaked string: the string
is reported as leaked, not as held), static cells, reuse of a freed cell of
the same class by another layout, the alignment of large cells and of raw
``double`` fields, and the statistics build; with a 32 bit C compiler and
GMP it runs as a 32 bit program too (it does on this machine).  On 32 bit
x86 a ``double`` member is 4 byte aligned by the ABI, so the struct of a
constructor may put one at offset 12, which is correct there; the 8 byte
case (ARM EABI) was not tested.

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

Stage B as implemented
----------------------

Implemented as an opt-in plumbing, **off by default**
(``--directive refc-flat-arrays``; stage C made it automatic, see below),
because of two findings:

- **The existing API cannot take a ``Flat`` without an elaborator change.**
  With ``Flat elem =>`` added to ``newArray``, ``readArray``,
  ``writeArray`` and the methods of ``Data.Linear.Array``, and the default
  ``%defaulthint boxedFlat : Flat a``, the programs whose element type is
  solved after the call (``x <- newArray 20`` followed by ``writeArray x 10
  "Hello"``, ``chez/chez012``, ``node/node012``) fail with "Can't find an
  implementation for Flat String": the search that runs once the element
  type is known runs without the default hints, which only fill in a
  type that is still unknown.  A catch-all ``%hint boxedFlat : Flat a`` is
  ambiguous with the other implementations ("Multiple solutions found").
  So a ``Flat`` on the existing functions needs the auto search to fall back
  to the default hints for a known type that no other hint matches (a small
  change in ``Core.AutoSearch``, but one of the type checker, which the
  brief says to stop at).  Until that is decided, the existing functions
  are unchanged in their types (``readArray`` and the rest read and write
  any array, by its layout), and three new functions of ``Data.IOArray``
  make and access flat arrays: ``newFlatArray``, ``readFlatArray`` and
  ``writeFlatArray``, which take the ``Flat`` of the elements.
  ``Data.Linear.Array`` is unchanged.
- **Flat arrays are slower until stage C.**  An element read from a flat
  array is a new value (a ``Just`` and a record cell), where the array of
  values shares the one it holds.  With ``Data.Linear.Array``'s
  ``mread``/``write`` made to take a ``Flat`` (the first attempt above), on
  the fast inputs particles ran 3.95 G instructions with the layouts
  against 3.16 G without, events 9.11 G against 8.10 G.

What is in place:

- **The library.** ``Data.IOArray.Flat`` (base) has ``Layout a``, a newtype
  of a ``Bits64`` code whose constructor is private, and
  ``interface Flat a where flatLayout : Layout a``, with the
  ``%defaulthint`` ``boxedFlat`` (the layout of values, 0), and
  implementations for the primitive numbers and ``Char``.  ``Data.IOArray``
  re-exports it.  The slots of an ``IOArray`` are made, read and written by
  three new primitives of ``Data.IOArray.Flat``, ``prim__newSlots``,
  ``prim__slotGet`` and ``prim__slotSet``, which take the layout of the
  elements; ``Data.IOArray`` uses them with the layout of values, but for
  the three new functions.  The Scheme and JavaScript back ends compile
  them as ``prim__newArray``, ``prim__arrayGet`` and ``prim__arraySet``,
  ignoring the layout (``allbackends/flatarray001`` prints the same on Chez,
  Node and RefC).  ``Data.IOMatrix``, which uses the old primitives, is
  unchanged.
- **The hints.** ``TTImp.ProcessData`` (``Core.FieldRep.addFlatHint``) makes
  the implementation of ``Flat`` of a record of one constructor without
  parameters whose fields are all ``rawField``, from the table, when
  ``Data.IOArray.Flat`` is loaded in the module that declares it (it is
  when the module imports ``Data.IOArray`` or ``Data.Linear.Array``,
  directly or by public imports): a definition whose value is the layout
  code (``2 + 256 * fields + 2^24 * tag``) and a hint.  A record declared in
  a module that does not load it gets the default.
- **The arrays.** In RefC an ``Idris2_Array`` has a ``layout``.  With 0 it
  is the array of values of before.  Otherwise each slot is a word (1 when
  it holds an element) and the element inline: 8 bytes for a primitive, the
  raw fields of the record (its cell's raw area, 8 bytes each).  Release,
  the marking of shared values and the leak check do not look into such
  slots (they hold no value).  A shared array's slots are copied under its
  lock.  ``idris2_arrayCopy`` copies bytes between arrays of the same
  layout, and element by element through values otherwise.
- **Why creation and access cannot disagree.** The layout is a field of the
  array, set when it is made, and never changes.  Every access takes the
  layout that its caller expects and compares it with the array's
  (``idris2_slotGet`` in prim.h): the inline access is taken only when they
  are the same and not 0; otherwise the access goes by the array's own
  layout (``idris2_slotGetGeneric``), whatever the caller expected.  So an
  array made by generic code (layout 0) and read by code that knows its
  elements, or the reverse, is read right; the tests make and read arrays
  both ways, copy between them in both directions, and overlap a copy.  The
  test costs the two instructions measured in phase B's experiments.
- **The constant layouts.** The decision was to specialise the functions by
  their ``Flat`` arguments in the elaborator (the ``Flat`` part of
  ``--spec-interfaces``, always on).  It does not work for the arrays of
  Data.Linear.Array: a copy is elaborated in the module that calls the
  function, which has only its public imports loaded, and the methods of
  ``Data.Linear.Array`` call ``Data.IOArray``, a private import.  With
  ``--spec-interfaces`` on particles:
  ``Partial evaluation of Data.Linear.Array.mread failed: ... Undefined name
  Data.IOArray.readArray`` (and the same for ``write``, ``read`` and
  ``newLinArray``; this is also why ``write`` was not specialised in the
  experiment of question 6).  Making the imports public would put
  ``Data.IOArray.newArray`` in scope with ``Data.Linear.Array.newArray``.
  So the copies are made by the RefC back end instead
  (``Compiler.RefC.FlatClones``), which sees every definition and type
  checks nothing: a function whose parameter reaches the layout argument of
  a slot primitive (directly, or through such a parameter of a function that
  it calls) gets a copy for each constant layout that it is called with (a
  literal, or a definition that is one: an implementation of ``Flat``),
  with the parameter bound to the literal; the copy's calls are copied in
  turn.  The elaborator is not changed, and type checking costs nothing
  more.  Only layouts other than 0 are copied for.  With the directive off,
  no copy is made and every layout is 0.
- **Not yet.** The element read is a value (a ``Just`` and a record cell
  for a record); a write takes the ``Just`` that the library makes.  Both
  are stage C's (below).

Stage C as implemented
----------------------

Opt-in in the API, and automatic in the back end:

- **When.** The flat arrays (the layouts, the copies of FlatClones, FlatOpt,
  and the unboxing ``Into`` below) are on in a program exactly when it uses
  a slot primitive (``prim__newSlots``, ``prim__slotGet``,
  ``prim__slotSet``), which only the flat functions do (``newFlatArray``,
  ``readFlatArray``, ``writeFlatArray`` of ``Data.IOArray``,
  ``Data.Linear.Array.Flat``): a scan of the ANF (``flatMode``).  The
  functions of ``Data.IOArray`` and ``Data.Linear.Array`` use the array
  primitives of before (``prim__arrayGet`` and the rest), so a program that
  does not use flat arrays is compiled exactly as without them: the C of
  the particles and events programs on arrays of values, of the five
  benchmarks and of ``arrayperf001``/``002`` and ``rawfields001``/``002`` is
  the same to the byte as devel's.  (The flat primitives are in
  ``Data.IOArray.Flat``, and its additions at the end of ``Data.IOArray``,
  for that: in ``Data.IOArray.Prims`` they changed the order of the
  definitions, and above the old functions their source locations.)  In a
  program that uses them, ``prim__arrayGet`` and ``prim__arraySet`` go by
  the array's layout (``idris2_arrayGetAny``, ``idris2_arraySetAny``), as a
  flat array can be given to them.  ``--directive refc-no-flat-arrays``
  turns the flat arrays off (the slot primitives make and access arrays of
  values); ``--directive refc-flat-arrays`` is accepted and changes nothing,
  as a program without slot primitives has no array with a layout (forcing
  the rest on for it cost 1.7% on the arrays of values and gained nothing).

- **Flat linear arrays.** ``Data.Linear.Array.Flat`` (contrib) has
  ``FlatArray`` and ``FlatIArray``, with the functions of
  ``Data.Linear.Array`` under the same names, taking the ``Flat`` of the
  elements: ``mread``, ``write``, ``msize``, ``mcopy``, ``toIArray``,
  ``read``, ``size``, and ``newFlatArray`` and ``thawFlat`` to make one.
  ``Data.Linear.Array``, its interfaces and their users are unchanged.  A
  program opts in by importing the module, writing ``FlatArray`` and
  ``FlatIArray`` for ``LinArray`` and ``IArray``, and calling
  ``newFlatArray`` for ``newArray`` (``Flat.newFlatArray`` where
  ``Data.IOArray`` is imported too); nothing else changes
  (``benchmark/flat-layout/stagebc``: ``particles_flat.idr`` and
  ``events_flat.idr`` differ from the originals in those lines only).  The
  functions run the flat accesses of ``Data.IOArray`` at ``IO``
  (``newFlatIO``, ``readFlatIO``, ``writeFlatIO``): through ``HasIO``,
  ``mread`` was a closure.
- **The accesses** (``Compiler.RefC.FlatOpt``, after
  ``Compiler.RefC.FlatClones``, on the ANF).  The functions that access flat
  arrays get the small functions that touch their elements inlined (the
  copies of the array functions by layout, the functions on the records;
  path-guarded, four deep, up to 800 nodes, in three rounds, as a function
  rewritten can be one to inline in the next), then: the ``let`` of a
  ``let`` is floated out; a ``case`` on a constructor that a ``let`` made is
  its branch (the ``Res`` of an access); a closure made and applied to its
  last argument is a call; an element read (``prim__slotGet``, in the
  branch of a bounds test) is its components, the presence and the fields,
  each a copy of the read's pure ``case`` with ``slotPresent`` or
  ``slotField`` at the leaf (the projections of the ``IOArray``, of
  variables bound outside, are made once: before them where they cannot
  fail, made unconditionally or of a variable known to be made by their
  constructor; otherwise, the array projected in the branch of the bounds
  test, a component of its own, that the others share, NULL in the other
  branches); a ``case`` on it tests the presence (a default is taken for
  the constructor without a branch), and its ``Just`` branch has the record
  made of the fields, which is dropped when it is not used as a value (the
  element used as a value is made of its components too, when they are
  used); a record made by a ``case`` whose branches all give one (an update
  in a branch) is its fields, the same way (the snapshot of an element read
  in a branch is a component that the others share; a value that reads an
  element otherwise is not split); a write of a ``Just`` of a record known by its
  fields is ``slotStore`` of the fields, of another record ``slotStoreElem``
  of its cell (no ``Just``); the pure ``let`` s not used are dropped.  A
  function that has no access by fields in the end is kept as it was (its
  rewritten body is only what is inlined): with them, the compiler's own C
  grew by 13% (by 40% when the functions on records were kept rewritten
  too); with the directive on, it is now the same but for the layouts
  passed, and is generated in 2% more time.  The
  primitives are RefC's own (namespace ``_refc_flat``, prim.h): inline when
  the array has the layout expected and is not shared, through values
  otherwise (in prim.c), so they are right for an array of any layout
  (``refc/flatopt001`` reads and writes an array of values with them, and a
  shared one from two threads).
- **Reads of whole elements.** An element read by its fields starts with
  its snapshot, one more component (``slotSnap``, the read's ``case`` with
  ``slotSnap`` at the leaf and NULL elsewhere): when the array is read
  inline it is a tag (``IDRIS2_SLOT_INLINE``, an unboxed pointer, never
  counted), and the other components read the slot; otherwise it is the
  slot's value, the ``Maybe``, taken once (under the lock of a shared
  array), and they read it, and it is released after the last.  So the
  fields read are those of one write: ``refc/flatopt002`` has a thread
  write elements whose four fields are equal while another reads them by
  their fields, and counts none whose fields differ (reading each field
  under the lock, as before, it counted about 1640 of 192 000).  The tag
  also replaces the test of the layout and of the sharing at each field:
  W1 runs 4.47 G instead of 5.10 G.
- **Unboxing.** A variable that a branch gives as the value of a ``let``
  is a C number when the ``let`` 's variable is one (the use ``Into`` of
  Compiler.RefC.Unbox).  The components above are such ``case`` s; without
  it the particles on flat arrays run 2.60 G instructions instead of 1.03 G
  (fast input).  It applies in the programs that use flat arrays only (on
  the others it changed one worker of the compiler, and nothing measured).

Measured: see the final table below (``The final numbers``).

Remaining work
~~~~~~~~~~~~~~

Measured per update (W1: 100 000 records, 250 passes) and per step (W2:
4 000 000 steps) on the final branch:

- W1: 179 instructions per update against FD's 133 (and plain C's 37).
  Each component still tests the bounds result again (the C compiler merges
  some of these), the result of ``write`` is a boxed ``Bits8`` (static, but
  made), and ``next`` is a call.
- W2: 2 964 instructions per step against F's 2 710.  The event that
  ``pop`` takes out is a record cell passed to ``siftDown``, and ``pop``'s
  ``Res``, its ``Just`` and the record are made once a step.
- To do, in order of what they would remove:

  1. **Records across worker calls**: all-raw records passed to and
     returned from workers as scalars (or a struct), so the ``siftDown``
     parameter and the records given to ``put`` are not cells.
  2. **The case-of-case join point**: a ``let`` bound to a ``case`` whose
     branches give the same constructor but are not pure (``pop``'s branch
     calls ``siftDown``) is scalarised by a join point that takes the
     fields, instead of copying the branches; this removes ``pop``'s
     ``Res``, ``Just`` and record.
  3. **The uninlined ``Res``**: the ``Res``/``LPair``/``#`` of a call that
     is not inlined returned without a pair (as a struct, or the second
     component through a pointer), and with it the ``musttail`` rule for
     values of more than two registers (the per-worker buffer), which
     nothing needs yet as no flat value is passed in a jump.

The final numbers
~~~~~~~~~~~~~~~~~

Instructions, user space, median of 3, full inputs:

==============================================  ===============  ===============
\                                                W1 particles     W2 events
==============================================  ===============  ===============
linear arrays of values, devel (e9a3edee66)     16 093 788 034   44 472 071 010
the same, this branch (the same C)              16 093 688 644   44 472 232 112
flat linear arrays, this branch                  4 474 932 457   11 854 020 531
flat linear arrays, ``refc-no-flat-arrays``     18 241 783 497   49 055 362 615
phase 0, hand-written C (FD, F)                  3 313 193 027   10 840 000 000
==============================================  ===============  ===============

(W2's F is phase 0's 10.84 G, rounded.)  The arrays of values are as on
devel (the same C, and the runtime's tests of the layout are only where an
array is freed, marked shared or copied).  The flat arrays run 3.6 and 3.75
times fewer instructions, within 1.35 and 1.09 of phase 0's hand-written
flat C.  The flat source with the flat arrays turned off pays 13% and 10%
over the arrays of values, for the ``Flat`` dictionary and the slot
primitives with the layout 0.

Stage A, follow-up: static constants with raw fields
----------------------------------------------------

A constructor with raw fields whose pointer fields are static values and
whose raw fields are literals is static data (``staticRawConstructor``): a
struct with the header, the pointer fields, then the raw fields from an
offset aligned on 8 (``_Alignas(8)``, for 32 bit x86), named by its depth
first so that it is defined before the constructors that hold it.

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
   the layout of the element type: it gets a value ``Flat elem``, an
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
arrays unless it adds ``Flat elem =>`` to its own type.

The layout descriptor
---------------------

- ``Flat : Type -> Type`` is an *interface* of ``Data.IOArray.Prims``
  with one method, the descriptor of a slot (``LBoxed``, ``LPrim PrimType``,
  ``LRecord name [PrimType]``, ``LMaybe``), of an opaque type whose
  constructors are not exported.  It is an interface, not a plain data
  type, so that the specialisation by known implementations makes the
  descriptor a constant in the copies of the array functions (see the
  experiments below).
- Its hints: ``%defaulthint boxedFlat : Flat a`` (taken when nothing else
  applies, in particular for a type variable); implementations written by
  hand in ``base`` for the primitive types and for ``Maybe`` of a flat
  layout; and one that the compiler generates in ``ProcessData`` for each
  single constructor record whose fields are all ``rawField`` (from the
  table, so the descriptor cannot disagree with the cells of stage A).
- The constructors of the descriptor type must not be visible where a
  ``Flat`` is searched for: the search for an ``auto`` argument also tries
  the constructors of its type, and ``LBoxed : Layout a`` would match every
  type before the hints (the first experiment below got ``boxed``
  everywhere until they were hidden).
- ``prim__newArray`` gets the descriptor (a new primitive,
  ``prim__newArrayL : Flat a => Int -> a -> PrimIO (ArrayData a)``; the
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

The experiments (open questions 5 and 6)
----------------------------------------

The scratch programs are in ``benchmark/flat-layout/stageb`` (``Hint.idr``
and ``Main.idr``; ``FlatArr.idr`` and ``Particles.idr``, a stand-in for
``Data.Linear.Array`` and W1's ``sweep``; ``Spec.idr``; ``access.c``).

- **``%defaulthint`` does not fire early.**  With an opaque descriptor type,
  a default hint for every type, and hints for ``Double`` and ``Maybe a``:
  ``mk 3 (\a => useDouble a)``, where the element type is only known from
  the continuation (elaborated after the auto implicit), gets the ``Double``
  descriptor; so do ``Maybe Double`` known later, an explicit ``{t =
  Double}``, a type known from a later expression of a ``do`` block, and a
  generic function that has the constraint and is called at ``Double``.  A
  generic function without the constraint gets the default.  That is the
  behaviour the design needs.
- **``%spec`` and ``%inline`` cannot be put on a method of an
  implementation** (both are parse errors in an implementation's body).
- **With a descriptor of a data type**, W1's ``sweep`` calls the method
  implementation of ``mread`` directly (no dictionary), with the hint as a
  constant argument (``FlatArr.mread [(Main.layoutParticle []), a, i]``),
  but the method is not inlined, so inside it the descriptor is a variable
  and the access is the generic one.  Making the methods ``%inline``
  wrappers of top level ``%inline`` functions (allowed) inlines those into
  the method, not the method into ``sweep``.
- **With the descriptor as an interface and ``--spec-interfaces``**, the
  calls of ``mread`` and ``newA`` in ``sweep`` and ``main`` become calls of
  specialised copies (``_PE.Main.PE_mread_MArr_LinA_...``) whose primitive
  gets the descriptor as a constant term.  The call of ``write`` was not
  specialised: its interface arguments are listed as ``[__con, {i_con:0}]``
  (the ``MArr`` dictionary as well as ``Flat``), and no copy is declared; I
  did not find why.  ``--spec-interfaces`` is not on by default.

So, for the phase 0 programs as they are written (no annotation, default
options), the descriptor is a constant at the call of the method but not at
the access inside it.  The design needs one of:

1. specialisation by ``Flat`` implementations always on (the part of
   ``--spec-interfaces`` that concerns ``Flat`` arguments, as if every
   function with a ``Flat`` argument were ``%spec`` on it), with the
   ``write`` case found and fixed.  This is the recommendation: the
   machinery exists, and it gives the constant at every access that is
   reached from monomorphic code;
2. or a specialisation by constant arguments in the RefC code generator (a
   copy of a function for a call whose descriptor argument is a known top
   level constant);
3. or relying on the C compiler: the descriptor is the address of a static
   constant, so where GCC inlines the method into its caller (phase 0
   observed that it inlines ``mread`` into ``sweep``) the dispatch folds.
   Not reliable: units of a split program are compiled apart.

The generic path stays correct in every case.

**The C of one access**, with the slot layout of ``Maybe Particle`` (a tag
byte padded to 8, then 40 bytes), compiled with ``-O2`` (``access.c`` and
``one.c``):

- ``write`` with a constant descriptor: 17 instructions out of line (the id
  compare, the bounds check, the slot address, the tag and three 16/8 byte
  moves);
- ``mread`` with a constant descriptor: 38 instructions out of line, of
  which about 20 are the copy of the 48 byte ``Maybe Particle`` result
  through memory and the stack protector; inlined, the result stays in
  registers;
- the guard on the descriptor is 2 of them (a 64 bit constant and a
  compare with the array's id).

A whole W1 update (two reads, ``move``, one write, the loop) is 95
instructions with the constant descriptor and 515 through the generic path
(each read makes a record cell and a ``Just``, each write is given a cell),
against 133 for phase 0's FD and 663 for SA.

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

Decided (by the coordinator, 2026-11-20): the table stays in ``MkCon`` and
friends (an API change for back ends outside this repository that match
``MkNmCon`` positionally); enumerations stay ``FPrim Bits8/16/32`` through
``enumPrimType``; stage A stores raw only ``rawField`` types (``Double``,
``Int``, ``Int64``, ``Bits64``); no sums other than ``Maybe`` in arrays;
stage A first, then B and C together.

Still open:

1. **Newtypes see-through only for monomorphic newtypes**: ``Identity Double``
   could be ``Double`` by substituting the type arguments into the newtype's
   field type.  Not done: the table would depend on the arguments of a type,
   which no use site has.
2. **Raw ``Char``, ``Bool`` and the small integers**: left as immediates;
   to revisit with the self-build numbers of stage A.
3. **Stage B's specialisation**: which of the three ways makes the
   descriptor a constant at the accesses (see the experiments; the
   recommendation is specialisation by ``Flat`` implementations always on),
   why ``write`` is not specialised by ``--spec-interfaces`` in the
   experiment, and whether the generated ``Flat`` implementations slow down
   the search for other hints.
4. **The debug check** ``refc-check-layout``: whether to make it part of
   ``refc-backtrace``'s debugging set or a directive of its own.
