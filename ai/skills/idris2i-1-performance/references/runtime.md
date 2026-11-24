# How compiled Idris2i-1 runs, and what each construct costs

The default back end, RefC, compiles Idris2i-1 to C and the C to a native executable. Read
this file before changing a hot loop: most GHC habits (laziness, strictness
annotations, fusion, `-O2`) do not apply, and the costs that do apply are listed here
with their mechanism.

Every ratio below marked *measured* was measured for this skill with `perf stat -e
instructions:u` and user time, 3 runs each, on small programs (x86-64, GCC 16);
the instruction counts did not vary between runs. Others are quoted from the
documentation of the compiler, and say so.

Contents: [Model](#the-model-to-hold) · [Numbers](#numbers) · [Strings](#strings) ·
[Collections](#lists-arrays-and-buffers) · [Records](#records-and-constructors) ·
[Recursion and stack](#recursion-and-the-stack) ·
[`where` constants, W0007](#where-constants-are-recomputed-w0007) ·
[Inlining and specialisation](#inline-noinline-spec-and---spec-interfaces) ·
[`IORef` and `IO` loops](#ioref-and-io-loops) · [Concurrency](#concurrency-fork) ·
[C compiler knobs](#c-compiler-knobs)

<!-- idris
import Data.IORef
import Data.IOArray
import Data.Buffer
import Data.Vect
import Data.Array
import System.Concurrency
-->

## The model to hold

- **Strict evaluation.** Arguments are evaluated before the call, a `let` before its
  body. There are no thunks to leak and no strictness annotations to add: `foldl` with
  an accumulator does not build a chain of thunks.
- **`Lazy` is call-by-name, not memoised.** A `Lazy` argument (and `Inf`, and the
  delayed branch of `if`/`&&`) is recomputed every time it is forced. *Measured:* a
  `Lazy Int` forced twice did the work twice (2× the instructions of a strict
  argument). Force it once and bind the result.
- **Reference counting, freed at once, no tracing GC.** A value is freed when its last
  reference goes. Allocation of short-lived values and the count updates are the main
  costs of a RefC program; there are no GC pauses and memory use is low. The RefC
  documentation puts RefC at 0.8 to 2.5 times the run time of the Chez back end on the
  programs of its `benchmark` directory.
- **No cycle collector.** A cycle of references (only possible through an `IORef`, an
  array, or a closure stored in one) is never freed. `IDRIS2I_1_REFC_LEAKCHECK=1` finds
  them (see `SKILL.md`).
- **A cell whose count is one is reused in place** for a new value of the same
  constructor, so `map f xs` on a list nobody else holds rewrites the cells instead of
  allocating new ones. Keeping an extra reference to the old list (using it after the
  `map`) turns that off.
- **Definitions without arguments are constants**, evaluated once on first use and
  kept until the program exits, with everything they refer to (a big table at top
  level is never freed). This is *not* true of a `where`/`let` definition that uses the
  enclosing function's arguments: see W0007 below.
- **Erasure is by quantity.** An argument of quantity 0 (`{0 n : Nat}`, and every
  implicit the compiler binds by itself) does not exist at run time. An implicit you
  write without a quantity (`{n : Nat}`) is passed at every call. `--dumpcases`
  shows it:

```idris
headA : {n : Nat} -> Vect (S n) Int -> Int
headA (x :: _) = x

headB : Vect (S n) Int -> Int
headB (x :: _) = x
```

```text
Main.headB = [{arg:1}]: (%case !{arg:1} [(%concase [cons] _builtin.CONS ...
Main.headA = [{arg:0}, {arg:1}]: (%case !{arg:1} [(%concase [cons] _builtin.CONS ...
main ... (Main.headA [2, (%con [cons] _builtin.CONS Just 1 [1, ...
```

  `headA` takes the length (an `Integer`, computed by the caller); `headB` does not.
  Also visible: a `Vect` is compiled to the same cons cells as a `List`.

## Numbers

- `Int`, `Int8`..`Int64`, `Bits8`..`Bits64` and `Double` are machine numbers. In
  function bodies and across calls between Idris2i-1 functions they are C integers and
  doubles (the "workers" of the RefC documentation); they become heap values only when
  stored in a constructor, a closure or an `IORef`, and then only the integers that
  do not fit in 32 bits allocate.
- `Integer` is arbitrary precision. A value that fits in 32 bits is held unboxed and
  its arithmetic is a test and a C operation; a bigger one is a GMP number on the heap,
  allocated for every result (`__gmpz_add`, `malloc`, `idris2i_1_add_IntegerSlow` in a
  profile). *Measured*, tail-recursive loops of 50 million steps: with values that
  stay below 2^31, `Integer` took about 4.5× the instructions (4× the time) of `Int`;
  summing the numbers 1 to 50 million, whose total passes 2^31 early, about 54× the
  instructions and over 100× the time.
- **`Nat` is compiled to `Integer`**, and so is every Nat-shaped type (a type with a
  zero constructor and a successor constructor: in `--dumpcases`, a match on
  `Succ k` of your own `data N = Zero | Succ N` is `-Integer [x, 1]`). The same loop
  over `Nat` cost about the same as over `Integer` (4× `Int` with small values). So
  `Nat` is not unary at run time, but it is never as cheap as `Int` either. Use `Nat`
  where a proof needs it, and `Int`/`Bits64` for counters, indices and sizes in hot
  code; `cast` at the boundary.
- **The `Data.Nat` and `Data.Fin` library functions run on `Integer`** at run time
  (`%transform` rules to `Integer` versions; the definitions still reduce as before
  in types): `lte`/`gte`/`lt`/`gt`, `minimum`/`maximum`, `power`, `div'`/`mod'` and
  so `divNatNZ`, `modNatNZ`, `gcd`, `lcm`, `Integral Nat`; `isLTE`, `natToFin`,
  `decEq` on `Nat`; `Fin` `+`/`*`, `strengthen`, `finS`; `Fin.tabulate`,
  `Fin.range` and `allFins` are O(n) instead of O(n²). The CHANGELOG measures 36× to
  300× fewer instructions for them. Your own functions that recurse on `S k` once per
  unit are still one call per unit: write them on `Integer`/`Int`, or call these.
- At *type-checking* time `Nat` is unary: see `typecheck-speed.md`.

## Strings

A `String` is a NUL-terminated UTF-8 byte array that stores its byte length, and
caches its number of characters the first time it is counted (RefC documentation).
Consequences, all *measured*:

- **`strIndex s i`, `substr` and `length`** are constant time on a string known to be
  ASCII (the first count finds that every character is one byte) and **linear on any
  other string**, which has to be walked from the start. A loop of `strIndex` over a
  40,000-character string with a single `λ` in it took about 2,500× the instructions
  of the same loop over an ASCII string, and grew with the square of the length. The
  RefC documentation says "linear" without the ASCII exception.
- **To walk a string, `unpack` it** (the compiler rewrites `unpack` to `fastUnpack` at
  run time; the walk over the non-ASCII string above then cost about as much as the
  ASCII indexing loop), or use `Data.String.Iterator` from `contrib`.
- **`acc ++ s` in a loop is quadratic**: `++` copies both strings. Building an
  80,000-byte string from 40,000 pieces with `++` took about 27× the instructions of
  collecting the pieces in a list and calling `fastConcat` once, and the gap doubles
  when the length doubles. String interpolation `"\{a}, \{b}"` is compiled to one
  `fastConcat` (seen in `--dumpcases`), and so are `concat` and `concatMap` on a list
  of strings (`%transform` rules in the Prelude); `pack` is rewritten to `fastPack`.

```idris
-- quadratic: each step copies the whole accumulator
slowJoin : List String -> String
slowJoin = foldl (\acc, s => acc ++ s ++ ",") ""

-- linear: one copy at the end
fastJoin : List String -> String
fastJoin xs = fastConcat (concatMap (\s => [s, ","]) xs)
```

## Lists, arrays and buffers

A list cell holds two pointers and a header: a list of 10 million `Int`s took about
240 MB (*measured*, peak RSS). For numeric data, *measured* on 1 million `Double`s,
filled once and summed 20 times:

| Container | Time | Peak memory | Notes |
|---|---|---|---|
| `List Double` | ~0.5× | ~0.8× | no indexing |
| `IOArray Double` (`newArray`, `readArray`) | 1× | 1× (53 MB) | every slot a boxed `Double` in a `Just` |
| `IOArray Double` made by `newFlatArray`, `readFlatArray` | ~0.9× | ~0.4× | (this fork) elements stored inline |
| `Buffer` (`setDouble`/`getDouble` at `i * 8`) | ~0.3× | ~0.25× | raw bytes, reads are inline C |

- `Data.Buffer` is the fastest store for fixed-width numbers: its reads and writes
  are inline C calls with no value made for the index or the element (RefC
  documentation, "workers").
- **Flat arrays** (this fork): `newFlatArray`, `readFlatArray`, `writeFlatArray` from
  `Data.IOArray` (with `Data.IOArray.Flat`) store primitive numbers, `Char`, and
  records of one constructor whose fields are all `Double`/`Int`/`Int64`/`Bits64`,
  inline in the array. They cut memory, as measured above; in that measurement the
  reads still went through a runtime call that builds a `Just` (look for
  `idris2i_1_slotGet` in the generated C), so the time gain was small. The array
  remembers its layout, so code that reads it with plain `readArray` is still correct,
  only slower.
- **`Data.Array`** (in `base`): `Array n a`, immutable, `index : Fin n -> Array n a
  -> a` in constant time. Built once by `tabulate`, `replicate`, `fromVect` or
  `fromList` (which returns the length in a dependent pair); `map`, `zipWith`,
  `replaceAt`, `updateAt` make new arrays, and `replaceAt` copies the whole array, so
  it is for read-mostly data. **Indexing a `List` (`getAt`, `index`) or a `Vect`
  (`index`) walks from the head**, so a loop that indexes every position is
  quadratic. *Measured*, summing 3,000 elements by index: `getAt` on a `List` and
  `index` on a `Vect` both about 115× the instructions of `index` on an `Array`
  (4× more at 6,000 elements; the CHANGELOG gives 58× for its own `Vect` benchmark).
  A compiler without these changes reports `Module Data.Array not found` for
  `:module Data.Array` at the REPL.

```idris
sumArray : {n : Nat} -> Array n Int -> Int
sumArray a = foldl (\acc, i => acc + Data.Array.index i a) 0 (Data.Vect.allFins n)

squares : Array 100 Int
squares = Data.Array.tabulate (\i => let k = cast (finToNat i) in k * k)
```

- `readArray` returns `Maybe`: the `Nothing` branch costs nothing when the index is in
  bounds, but a `Just` is built for each read of a plain `IOArray`.

```idris
sumFlat : IOArray Double -> Int -> Int -> Double -> IO Double
sumFlat arr n i acc =
  if i >= n then pure acc else do
    Just v <- readFlatArray arr i
      | Nothing => pure acc
    sumFlat arr n (i + 1) (acc + v)

sumBuffer : Buffer -> Int -> Int -> Double -> IO Double
sumBuffer buf n i acc =
  if i >= n then pure acc else do
    v <- getDouble buf (i * 8)
    sumBuffer buf n (i + 1) (acc + v)
```

## Records and constructors

- **Raw fields** (this fork): a field of type `Double`, `Int`, `Int64` or `Bits64` (or
  a newtype of one) is stored as a C number in its constructor's cell, so a record of
  four `Double`s is one allocation instead of five (RefC documentation, `refc-no-raw-fields`).
  Prefer these types for numeric fields over `Integer`, `Nat` or `Int32`.
- **Keeping the value you matched stops its cell from being reused.** A function that
  takes a constructor apart and builds the same constructor again (`Node (insert x l) y
  r`) rewrites the cell in place when nothing else holds it (the model above). That is
  lost when the clause keeps the whole value as well. An as-pattern `insert x t@(Node l
  y r)` is compiled as `let t = Node l y r` at the top of the clause, a new cell on
  every visit (seen in `--dumpcases`). Matching with `case t of` and returning `t` in
  one branch costs the same: `t` is still referenced during the recursive call, so
  every level allocates and counts references. *Measured* on a binary-tree insert of
  300,000 `Int`s into a tree with one owner: both forms took 5.6× the instructions and
  2.3× the time of the function below, which never names the whole node and rebuilds
  it in the branch that changes nothing:

```idris
data Tree a = Leaf | Node (Tree a) a (Tree a)

insertInt : Int -> Tree Int -> Tree Int
insertInt x Leaf = Node Leaf x Leaf
insertInt x (Node l y r) = case compare x y of
  LT => Node (insertInt x l) y r
  GT => Node l y (insertInt x r)
  EQ => Node l y r
```

## Recursion and the stack

- A call in tail position is a jump (GCC 15 or later) or goes through a trampoline;
  either way it uses no stack. Accumulator loops like `sumInt` are as fast as C loops
  (*measured*: 8 instructions per iteration for `acc + n`, `n - 1`, test).
- **Tail recursion modulo cons**: a function that builds a constructor around a call
  to itself (`map f (x :: xs) = f x :: map f xs`) is compiled as a loop that fills
  the cell's hole, so it needs no stack either (RefC documentation, `refc-no-trmc`).
  *Measured*: `map` over 10 million elements used no more memory than the list.
- **Other non-tail recursion uses the C stack**, about 32 bytes per frame in
  `x + sumNT xs` (*measured*: 10 million deep took 310 MB of stack and about 2× the time
  of the tail-recursive version). The main expression runs on a stack of its own of
  4 GB (on 64-bit systems; only what is touched is used), so deep recursion usually
  just works. `IDRIS2I_1_MAIN_STACK_SIZE` (bytes) changes it.
- **A forked thread has an 8 MB stack** (`IDRIS2I_1_THREAD_STACK_SIZE` changes it). The
  same recursion 1 million deep inside `fork` died of `SIGSEGV` (exit status 139) with
  no message; run with `IDRIS2I_1_REFC_BACKTRACE=1` to get
  `RefC: stack overflow (SIGSEGV)` and the frames.
- Many library functions are not tail recursive (`foldr` on lists, `++`, `sort`), so
  they use stack proportional to the list.

## `where` constants are recomputed (W0007)

A `where` (or `let` block) definition without arguments of its own that mentions a
variable of the enclosing function is lifted to a function of that variable, and
**re-evaluated at every use**. It looks like a shared value; inside a loop it is
quadratic. *Measured*: `big` below made `countBig` on 10,000 elements take about
3,500× the instructions of `countBigLet`, and 4× more for every doubling.

```idris
countBig : List Int -> Int
countBig xs = go xs 0
  where
    big : Int
    big = foldl (+) 0 xs `div` 2      -- runs again for every element
    go : List Int -> Int -> Int
    go [] acc = acc
    go (y :: ys) acc = go ys (if y * 1000 > big then acc + 1 else acc)

countBigLet : List Int -> Int
countBigLet xs = let big = foldl (+) 0 xs `div` 2 in go big xs 0
  where
    go : Int -> List Int -> Int -> Int
    go b [] acc = acc
    go b (y :: ys) acc = go b ys (if y * 1000 > b then acc + 1 else acc)
```

The fix: compute the value with `let` (which is evaluated once, strictly) and pass it
to the helpers as an argument. The warning is **off by default**; turn it on with
`-Wwhere-recompute` (or `--warn-where-recompute`). It is only printed when the module
is elaborated, so remove the build directory (or touch the file) first:

```text
Warning: big is a local definition without arguments that uses xs from countBig,
so it is recomputed at each use. If it is expensive, bind it with let and pass it on. [W0007]
```

A `where` constant that uses none of the enclosing variables is not warned about
(measured: one that sums `[1 .. 1000]`, used in a loop over 10,000 elements, cost no
more than a top-level constant). If in doubt, move it to the top level, where a
definition without arguments is evaluated once.

## `%inline`, `%noinline`, `%spec` and `--spec-interfaces`

- The compiler inlines small definitions by itself, and the decision is stored in the
  module's TTC. `%inline` forces it, `%noinline` prevents it; the pragma reference
  advises leaving the choice to the compiler. `%noinline` is useful to keep a function
  visible in a profile or a backtrace.
- **Interface methods in generic code are closure calls.** A function `Ord a => ...`
  receives the implementation as a record of closures and applies one for every
  `compare`. *Measured*: a generic `insert : Ord a => a -> Tree a -> Tree a` used at
  `Int` took about 3× the instructions (1.5× the time) of the same code with a known
  type.
- **`%spec`** makes a copy of the function for each known value of the named
  arguments. An `Ord a =>` constraint has no name, so name it as an `auto` implicit.
  *Measured*: the `%spec` copy below ran as fast as the hand-written `Int` version.

```idris
%spec ord
insertS : {auto ord : Ord a} -> a -> Tree a -> Tree a
insertS x t = case t of
  Leaf => Node Leaf x Leaf
  Node l y r => case compare x y of
    LT => Node (insertS x l) y r
    GT => Node l y (insertS x r)
    EQ => t
```

```idris
failing "is not the name of an argument of"
  %spec f
  twice : (a -> a) -> a -> a
  twice g x = g (g x)
```

  The function type `(a -> a)` must be written `(f : a -> a)` to be specialised by.
  `--log specialise:3` shows where a copy was not made (the evaluation is bounded).
- **`--spec-interfaces`** (this fork; experimental) does this automatically for small
  or recursive functions that take implementations, in the modules it is given for.
  *Measured*: the generic `insert` above, built with it, matched the `Int` version.
  The RefC documentation gives its cost: about 1.1× the compile time on the compiler
  itself (some modules 3×), 1.07× on the libraries.

## `IORef` and `IO` loops

- **Reading or writing an `IORef` is a call into the runtime** (the ROADMAP: about 20
  to 30 instructions each), and the value stored is a heap value. *Measured* on 20
  million iterations: `readIORef`/`writeIORef` of an `Int` took about 7× the
  instructions of the same loop with the counter as an argument; `modifyIORef r (+ 1)`
  about 19×, because it also applies a closure.
- So keep loop state in the arguments of a tail-recursive `IO` function and write an
  `IORef` once at the end:

```idris
countLoop : Int -> Int -> IO Int
countLoop acc 0 = pure acc
countLoop acc n = countLoop (acc + n) (n - 1)
```

- A function in `IO` is compiled to take the world as an argument when it can; the
  ROADMAP lists the cases where it instead returns an allocated closure (a branch
  that is a bare call, a non-trivial `let` before the first action, a statement
  followed by `if`/`case`), at an estimated 5 to 15% of the instructions of mostly-`IO`
  code. The loops of this file (`if` with a `do` branch, clauses by pattern, an action
  first) all measured the same. The `let` case matters for `fork`, below.

## Concurrency: `fork`

`fork act` runs `act` on a green thread; the threads run in parallel on one OS thread
per processor (`IDRIS2I_1_WORKERS` sets the number). The work must be inside the action:

- An action written in place, `fork (channelPut ch (work i))`, is compiled to a
  function of the world, so `work i` runs in the child. *Measured*: four such threads
  ran in parallel (wall time a quarter of the CPU time).
- **A `let` before the first action of an `IO` function is evaluated when the action is
  built, in the thread that builds it.** `fork (doLet ch i)` with `doLet` below
  computed `work i` in the parent, one thread after the other: *measured* 4× the wall
  time of `doBind`.

```idris
work : Int -> Int
work seed = go seed 1000
  where
    go : Int -> Int -> Int
    go acc 0 = acc
    go acc k = go ((acc * 31 + k) `mod` 1000003) (k - 1)

-- work runs in the parent when this action is made
doLet : Channel Int -> Int -> IO ()
doLet ch i = do
  let v = work i
  channelPut ch v

-- work runs in the thread that runs the action
doBind : Channel Int -> Int -> IO ()
doBind ch i = do
  v <- pure (work i)
  channelPut ch v

spawnAll : Channel Int -> IO ()
spawnAll ch = for_ (the (List Int) [1, 2, 3, 4]) $ \i => ignore (fork (doBind ch i))
```

  `do pure (); let v = work i; ...` works too. When a parallel program shows no
  speed-up, compare wall and user time (`/usr/bin/time`), then look for this.
- The ROADMAP lists the costs of synchronisation: a contended `Mutex` is 2 to 3 times
  slower than Go's, an uncontended one about 5 times; values shared between workers
  have their counts updated atomically.

## C compiler knobs

- `IDRIS2I_1_CC` (or `CC`) picks the C compiler, default `cc`.
- `IDRIS2I_1_CFLAGS` (or `CFLAGS`) is **added after `-O2`**: the compiler always passes
  `-O2` first, so `IDRIS2I_1_CFLAGS=-g` keeps the optimisation and a later `-O` wins.
  *Measured* on the tree insert: `-O0` 2.5× the instructions, `-O3` 2% fewer than the
  default. There is no `-O` flag of the Idris2i-1 compiler for RefC; `--profile` only
  affects the Chez and Racket back ends (the generated C is identical).
- `-DIDRIS2I_1_REFC_SMALL_CODE` in `IDRIS2I_1_CFLAGS`: about 10% smaller code that compiles as
  much faster and runs a few percent slower (RefC documentation).
- A program of more than 4 MB of C is compiled in parallel units (`IDRIS2I_1_CC_JOBS`),
  which only rebuild when their text changes; add `-flto` (or `-flto=auto`) to
  `IDRIS2I_1_CFLAGS` to keep inlining across units (RefC documentation).
- `--directive refc-no-...` turns off one optimisation at a time (borrowing, workers,
  unboxed `Double`, reuse, raw fields, TRMC...), for finding which one a measurement or
  a bug depends on; the list is in the RefC documentation, "Optimisations".
