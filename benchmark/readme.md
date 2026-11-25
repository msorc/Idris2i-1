# UNIX Benchmark suite for Idris2i-1

Dependencies:
- A working Idris2i-1 installation
- GNU time command (at usr/bin/time)

## Motivation

We were aiming to optimise the reference counting backend for Idris2i-1, but it quickly became apparent that this would be difficult without a consistent performance metric. This is the product of that issue, a simple benchmarking shell script. We aim for this to be usable across all of the code generators, though so far it has only been tested on the chez and refc (still in development) backends.

## Structure

The tests provided should serve as an example of the structure - here's the general idea.

Each test should be contained within a root folder TEST inside the `benchmarks` directory. A benchmark consists of a `TEST.idr` file, along with a `TEST.in` *and* a `TEST_fast.in`.
The tests are structured such that a value for the limiting factor on the duration is read from stdin from the idris code. Suitable values should be given in the `TEST.in` and `TEST_fast.in` files, which cause the test to take roughly 5 seconds and 1 second respectively (on the chez backend). This might be paths to input files of differing size/complexity, or it may simply be a number of repeats. There's a timeout currently set at 15 seconds which will end the test with signal 2. The aim is that after optimisation each backend should be able to complete each test within that period.

Two benchmarks, `vectFin` and `natOps`, are collections of small cases: each line of their input
is `CASE SIZE [REPEATS]`, and each case (`vmap`, `fplus`, `nlte`, ...) stands beside its `List`,
`Int` or `Integer` equivalent (`lmap`, `iplus`, `zlte`, ...), with a checksum printed per case.
Feed a single line to the executable to measure a single case, e.g.
`echo "vtabulate 3000 1" | perf stat -e instructions:u ./vectFin`.

Four more, `dropsEither`, `dropsMaybe`, `dropsRecord` and `dropsReuse`, are collections of
cases in the same form (`CASE STEPS`) that make hot the code RefC writes for paths that are
usually cold: the error branch of an inlined bind of `Either` or `Maybe`, which releases the
values that the rest of the computation captured (2 to 16 of them, of every kind), in tail
position and not; a value of 4 to 16 fields taken apart using none, one or two of them,
unique or shared; and updates of a list or a record that the loop keeps, so that the cell
is never unique and every reuse site copies it.  They are there to check that a change to
that code (taking it out of line, say) costs nothing even when it runs all the time.

If you've got any Idris2i-1 code that you think could be adapted to make a good benchmark, please do contribute!

## Using the script

Usage: bench.sh [OPTION]...
   -b   build each test first
   -c   specify the backend to use during compilation (requires -b flag)
        must be one of chez, refc, gambit
        (default is chez)
   -f   perform a faster version of the benchmark
   -o   specify name of output csv file
        (default is `bench-results_$BACKEND[_fast]`)
   -h   shows this message

e.g. `./bench.sh -fbc refc -o myrefcoutput`

Note that the default backend of the script is still chez, while `idris2i-1`
itself compiles with refc by default: pass `-c` to choose the backend
explicitly.
