# Traps

Each entry: the cause, what you see, what to do. All of them are in the
compiler repository and have happened in practice.

## Contents

- Testing and building
- Benchmarking and measuring
- Compiler internals that surprise
- Shared machines and trees

## Testing and building

### `make test` tests the old compiler

- **Cause**: `make test` does not rebuild (it says so in its first lines);
  it uses whatever is in `build/exec` and `libs/*/build`.
- **Symptom**: your fix "does not work", or a test passes that should fail.
- **Do**: `make idris2-exec` (and `make libs` if libraries are involved)
  before testing; compare `build/exec/idris2 --version` with `git log -1`.

### Stale library TTCs

- **Cause**: a TTC is rebuilt when its source, its imports or the compiler
  *version* change. The version is the commit of `HEAD` when the compiler
  was built, so with uncommitted changes to the compiler the libraries keep
  their old TTCs. A TTC holds choices of the compiler that wrote it:
  inlining flags (set by `compileAndInlineAll` while a module is built),
  specialised copies (`%spec`), elaborated definitions.
- **Symptom**: a change to the inliner, the optimiser, elaboration or the
  TTC contents seems to have no effect on programs that use the libraries,
  or a benchmark looks like a regression (operations on `Int` from the
  Prelude not inlined, and so on).
- **Do**: after such a change, rebuild the libraries from scratch with the
  new compiler: `make clean-libs && make libs` (in your own tree). Copy the
  new `libs/*/build/ttc` into any other prefix you benchmark with.

### The fresh compiler loads the installed libraries

- **Cause**: the compiler's prefix is baked in from `PREFIX` at build
  time; the launcher does not set `IDRIS2_PREFIX`.
- **Symptom**: `build/exec/idris2 Foo.idr` uses `~/.idris2` libraries:
  your library change is not seen, or `TTC data is in an older format`
  after a TTC version bump.
- **Do**: `IDRIS2_PREFIX=$PWD/build/env build/exec/idris2 ...` after
  `make testenv`.

### `--install` from a scratch compiler writes into `~/.idris2`

- **Cause**: as above, `idris2 --install` writes under the baked-in prefix
  unless `IDRIS2_PREFIX` is set, even when `make install PREFIX=...` put the
  compiler elsewhere.
- **Symptom**: packages appear in `~/.idris2/idris2-0.8.0/`, and other
  builds that use `~/.idris2` as their boot compiler change behaviour.
- **Do**: export `IDRIS2_PREFIX=<scratch prefix>` before any `--install`
  that is not meant for the real installation. If it happened, say so.

### Interactive test runs

- **Cause**: `INTERACTIVE` defaults to `--interactive`.
- **Symptom**: `make test` waits on `[y/N]`, or overwrites `expected`
  when something answers `y`.
- **Do**: always `INTERACTIVE='' ... < /dev/null`.

### Accepting `expected` files unread

- **Cause**: a failing test only says "FAILURE"; the reason is in the diff.
- **Symptom**: a regression committed as a new `expected`.
- **Do**: `diff -u expected output` for each one; copy only what you can
  explain. Commit pure wording changes separately.

### Skipped pools look like success

- **Cause**: a pool whose tool (Chez, Node, Racket, cc, OpenSSL) is missing
  is skipped, not failed.
- **Symptom**: `N/N tests successful` while your Chez change was never
  tested.
- **Do**: read the pool banners (`✗ chez not found`); say in your report
  which pools did not run.

### `tests/failures` is overwritten by every run

- **Cause**: the runner always rewrites it.
- **Symptom**: `make retest` after a scoped run reruns nothing or the
  wrong set.
- **Do**: copy `tests/failures` after the full suite if you will run other
  tests before `retest`.

### Running the runner by hand

- **Cause**: `NAME_VERSION` and the test prefix are set by the top-level
  `Makefile`.
- **Symptom**: every test fails with `Module Prelude not found`, or
  `clean_version` leaves version strings in.
- **Do**: go through `make test only=...`. With another compiler and
  prefix: `make -C tests testbin IDRIS2=<idris2> IDRIS2_PREFIX=<prefix>`
  then `NAME_VERSION=idris2-0.8.0 make -C tests test IDRIS2=<idris2>
  IDRIS2_PREFIX=<prefix> INTERACTIVE='' < /dev/null`. Do not pass
  `TARGET=` to `make test`: it leaks into the support Makefiles.
  `idris2/pkg/pkg006` and `pkg015` only pass with the prefix at
  `build/env` of the tree they run in.

### A warning that only CI sees

- **Cause**: CI builds with `IDRIS2_BOOT="idris2 -Werror"`.
- **Symptom**: CI fails on a warning (shadowing, unused, deprecated) that
  a local `make` printed and carried on.
- **Do**: build with `IDRIS2_BOOT="$HOME/.idris2/bin/idris2 -Werror"`
  before finishing.

### Lint misses new files

- **Cause**: `lint/lint.py` checks the `.idr` files that git tracks.
- **Symptom**: CI lint fails on a file that passed locally.
- **Do**: `git add` new files before linting, and run `git diff --check`
  for the other kinds of file.

### A broken `build/exec` after a failed build

- **Cause**: the compiler is built in steps (Idris to C, C to a binary,
  the binary moved to `idris2_app/`, the launcher installed); a failure in
  the middle, in particular of the C compilation, can leave `build/exec`
  with an old binary or none.
- **Symptom**: `build/exec/idris2` fails to start, reports an older commit,
  or `build/exec/idris2_app/idris2` is a small shell script.
- **Do**: after every build check `build/exec/idris2 --version` and `file
  build/exec/idris2_app/idris2` (an executable of tens of MB). Keep a copy
  of a good `build/exec` (`cp -a`) before risky builds.

### Building with an older compiler over newer TTCs

- **Cause**: a compiler that predates the version check in TTC files (an
  upstream release, an old bootstrap) reuses whatever `build/ttc` holds,
  including TTCs written by a newer compiler that call specialised
  copies (`PE_...`) it never emits.
- **Symptom**: C errors such as `implicit declaration of function
  '_PE_...'` in a module that did not change.
- **Do**: build with such a compiler in a clean tree, or remove
  `build/ttc` first.

### TTC version bumps

- **Cause**: `ttcVersion` in `src/Core/Binary.idr` changed (by you or by a
  merge).
- **Symptom**: installed libraries no longer load with the new compiler;
  everything rebuilds; two branches that each bumped it conflict.
- **Do**: bump it when the format changes (date rule in the source), tell
  the others who build from your tree, and expect a full rebuild of the
  libraries. Merging two bumps needs a new one.

## Benchmarking and measuring

### Concurrent builds make benchmarks slower

- **Cause**: RefC programs are often memory-bound; a C compile of the
  compiler or a library build on the same machine takes the memory
  bandwidth.
- **Symptom**: a 50% or larger slowdown that looks like a regression.
- **Do**: check `uptime` and `ps` for `cc1`, `idris2`, `chez` before
  trusting a number; count instructions (`perf stat -e instructions:u`)
  instead of time where you can; rerun on a quiet machine before bisecting.

### Micro-benchmarks move with harmless C changes

- **Cause**: GCC's inlining and code layout change when the generated C
  text changes.
- **Symptom**: 2 to 4% differences in instructions between builds that
  should be equal.
- **Do**: for a code generator change, measure a large workload: the
  compiler built by itself, then `IDRIS2_BUILD_JOBS=1 perf stat -e
  instructions:u idris2 --typecheck prelude.ipkg` in a copy of
  `libs/prelude`.

### Benchmark against libraries of the same compiler

See "Stale library TTCs": benchmark only with libraries rebuilt by the
compiler you measure.

## Compiler internals that surprise

### Argument-free `where` definitions are recomputed

- **Cause**: a `where` definition without arguments that uses the
  enclosing function's arguments is lifted to a function of those
  arguments, and runs again at every use. It looks like a shared constant.
- **Symptom**: a pass that is quadratic in a loop. In RefC's code
  generator this made generating the compiler's C 2.7 times slower.
- **Do**: compute such a value once with `let` and pass it to the helpers.
  After a change to a compiler pass, compare `--timing 2` of a big build
  (or the build time of the compiler) with the previous compiler.

### `%spec` copies and private imports

- **Cause**: a specialised copy is elaborated in the module that calls the
  function, where only what that module (transitively, publicly) imports
  is loaded.
- **Symptom**: the specialisation silently does not happen: the copy fails
  with `Undefined name` and the generic code is used.
- **Do**: after adding `%spec`, build a client module with `--log
  specialise:1` and look for failures. Keep the body of a specialised
  function to names that its callers can see.

### GCC `musttail` compile time

- **Cause**: GCC (15 and later) checks every `musttail` jump by walking
  back from each plain `return` along all paths without a memory access;
  on long chains of branches that only compute this is exponential. RefC
  guards plain returns in functions with jumps with `IDRIS2_PLAIN_RETURN`
  (`support/refc/runtime.h`, `plainReturn` in
  `src/Compiler/RefC/RefC.idr`).
- **Symptom**: one C part of the compiler takes minutes instead of seconds
  after a change to code generation that removed calls or loads from
  branches.
- **Do**: time a self-build after RefC code generation changes. If you kill
  a stuck `cc` (for instance with `timeout`), its `cc1` may keep running:
  stop it by its PID.

## Shared machines and trees

### Two agents in one tree

- **Cause**: one `build/exec`, one `libs/*/build`, one `build/env` and one
  `output` per test per checkout. `make clean-libs`, a bootstrap or a
  `make all` empties or replaces what the other agent is testing.
- **Symptom**: tests fail with missing modules or show another change's
  behaviour; `build/env` points at empty directories.
- **Do**: one git worktree per agent, made from `devel`
  (`build.md`, "Building in a separate tree").

### Worktrees based on `main`

- **Cause**: `main` tracks upstream; this fork's work is on `devel`.
  Automatic worktrees may start from `main`.
- **Symptom**: a RefC build fails with errors such as `FFI not found`,
  which look like a broken checkout.
- **Do**: check `git merge-base HEAD devel`; base your branch on `devel`.
  When moving commits between branches, cherry-pick them one by one;
  never a range `devel..branch`, which may include upstream commits.

### Killing other agents' processes

- **Cause**: `pkill -f idris2` or `pkill -x cc1` matches every agent's
  processes, and `pgrep -f`/`pkill -f` also match the shell that runs
  them.
- **Symptom**: another agent's build or test run dies.
- **Do**: remember the PIDs you start and signal only those.

### Too many jobs

- **Cause**: `IDRIS2_JOBS`, `IDRIS2_CC_JOBS` and `threads` each default to
  every processor; the C compilation of the compiler needs about 0.9 GB per C
  compiler process (`INSTALL.md`).
- **Symptom**: the machine swaps, builds of other agents slow down or are
  killed.
- **Do**: on a shared machine pass `IDRIS2_JOBS=4 IDRIS2_CC_JOBS=4
  threads=4` or whatever your share is.
