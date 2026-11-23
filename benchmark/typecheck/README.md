# Type checking benchmarks

`tc-perf.sh` measures what the compiler costs when it type checks: for a
compiler binary and a corpus of sources, it runs the build in a few
scenarios and appends to a CSV the instructions and cycles (user space, from
`perf stat`, the processes started by `--jobs` included), the peak RSS and the
wall time of each run.

The machine this runs on is usually busy: compare instructions and peak RSS.
Wall time is recorded, but swings by 50% or more when anything else runs. The
instructions of two runs of a clean build of `base` differed by less than
0.0001%; processor time (what the profile below measures) moves by 10-20%
on a busy machine, so read the profile as shares of a run.

    benchmark/typecheck/tc-perf.sh -c build/exec/idris2 -l mybranch -o tc.csv base
    benchmark/typecheck/tc-perf.sh -h      # all the options

## Corpora

- `compiler`: the compiler itself, `idris2 --typecheck idris2.ipkg` (the
  modules of the executable; `idris2api.ipkg` lists the modules of the API
  library, which are a few more and do not include `Idris.Main`). The source
  tree must have `src/IdrisPaths.idr`, which `make` writes.
- `base`, `contrib`: `libs/base` and `libs/contrib`.
- `perf`: each of the tests of `tests/idris2/perf` that is one source file,
  checked alone with `--check` (only a clean build).

Each corpus is copied into the work directory (`-d`, by default
`./tc-perf-work`) and built there, so neither the TTC files of the source
tree nor those of an earlier run matter. The libraries it needs (`prelude`,
`base`, `linear`, `network`, `contrib`) are built first with the compiler
being measured, in `WORK/LABEL/prefix-*`, and kept for the next runs of the
same compiler version (that build is not measured).

## Scenarios

| scenario   | what is built                                                            |
|------------|--------------------------------------------------------------------------|
| `clean-j1` | everything, one process                                                  |
| `noop`     | nothing changed since the last build                                     |
| `leaf`     | a module that no module imports was touched                              |
| `comment`  | a comment was added to a module that most modules import                 |
| `iface`    | an exported definition was added to that module: its interface changed  |
| `clean-jN` | everything, with `-j` processes (6 by default)                           |

The leaf and root modules of each corpus are in `leafOf` and `rootOf` in the
script. The column `modules_built` counts the `Building` lines of the output.

## Profiles

`idris2 --timing-summary` prints, as it exits, the processor time spent under
a set of timers (inclusive and self times: see "Performance" in
`docs/source/reference/debugging.rst`) and a few counters, and for each
module that it built a line with its time and the ten most expensive
declarations. With `-X --timing-summary` the script passes the option on;
the output of every run is kept in `WORK/LABEL/logs`, and

    benchmark/typecheck/sum-profile.sh WORK/LABEL/logs/base-clean-j1-1.log

adds up the profiles of a log (a build with `--jobs` has one per process) and
prints them as tables: the timers by self time, the counters, the most
expensive modules and the most expensive declarations of the two most
expensive modules.

With the timers on, a build runs 3% more instructions (`base`, the compiler;
0.4% for `contrib`): the clock is read with a system call at each timer, and
each decoded definition has its compiled code decoded a second time to count
its bytes (that time is taken out of the timers, so it shows as untimed).
With them off (compiled in, the flag not given) a clean build of `base`, the
compiler or `contrib` runs 0.15%, 0.12% and 0.28% more instructions than
without them.

## Baseline

`baseline.csv` has the numbers of the compiler of the commit that added it,
built with `make` (RefC, the default C flags), on a busy 32-core machine.
