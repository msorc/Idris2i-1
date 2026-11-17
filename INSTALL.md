# Installation

- [Installing with a package manager](#installing-with-a-package-manager)
- [Installing from source](#installing-from-source)
- [Installing Chez Scheme on Apple Silicon](#installing-chez-scheme-on-apple-silicon)

## Installing with a package manager

You can install Idris 2 with any one of a number of package managers.

### Installing with [Pack](https://github.com/stefan-hoeck/idris2-pack)

Pack comes with an installation of Idris 2 and allows to update your idris2
version easily. It also enables the use of packages in the
[pack-collection](https://github.com/stefan-hoeck/idris2-pack-db)
and easy installation of programs such as
[`idris2-lsp`](https://github.com/idris-community/idris2-lsp).

It is the recommended way to get started. See
[the installation instructions](https://github.com/stefan-hoeck/idris2-pack/blob/main/INSTALL.md)
on GitHub.

### Installing with [Homebrew](https://brew.sh/)

```sh
brew install idris2
```

### Installing with [Nix](https://nixos.org/features.html)

```sh
nix-env -i idris2
```

### Installing with [Nix Flakes](https://nixos.wiki/wiki/Flakes)

```sh
nix profile install github:idris-lang/Idris2
```

## Installing from source

The easiest way to install from source is to bootstrap from the C code of
the compiler that is in the repository (`make bootstrap-c`, see
[below](#2-installing-without-an-existing-idris-2)). The requirements are:

- `bash`, `GNU make`, `gcc` or `clang`, `xz` and `GMP`.  On Linux, you probably
  already have these.  On macOS and major BSD flavours, you can install them
  using a package manager: for instance, on macOS, you can install with the
  `brew install coreutils gmp xz` and on OpenBSD, with the `pkg_add coreutils
  bash gmake gmp xz` command. You specifically need the dev GMP library, which
  means on some systems the package you need to install will be named
  something more like `libgmp3-dev`. macOS ships with `clang` whereas `gcc` is
  more common for other \*nix distributions.
- Optionally, a Scheme compiler: Chez Scheme or Racket. You can bootstrap
  from the generated Scheme code instead of the C code, build the compiler
  with a Scheme backend, and compile your programs with it.

On Windows, [MSYS2](https://www.msys2.org/) is required. On Windows older
than Windows 8, you may need to set an environment variable `OLD_WIN=1` or
modify it in `config.mk`.

On Raspberry Pi, you can bootstrap from the C code, or via Racket.

By default, code generation is via the RefC backend, which needs a C compiler.
You can use Chez Scheme or Racket instead, by setting the environment variable
`IDRIS2_CG=chez` or `IDRIS2_CG=racket` before running `make`.
If you install Chez Scheme from source files, building it locally,
make sure you run `./configure --threads` to build multithreading support in.

**NOTE**: On FreeBSD, OpenBSD and NetBSD you need to use the `gmake` command
instead of `make` in the following steps.

**NOTE**: If you're running macOS on Apple Silicon (arm64) you will need to use
Chez scheme version `10.0.0` or greater. Homebrew has been updated to ship Chez
Scheme 10+ as of this writing. If you cannot install Chez Scheme 10+, install
the Racket fork of chez scheme as described
[below](#installing-chez-scheme-on-apple-silicon). If you install gmp via
homebrew, you will also need to `export CPATH=/opt/homebrew/include`.

### 1: Set installation target directory

- Change the `PREFIX` in `config.mk` to the absolute path of your chosen
installation destination. The default is to install in `$HOME/.idris2`

If you have an existing Idris 2, go to Step 3. Otherwise, read on...

Make sure that:

- `$PREFIX/bin` is in your `PATH`

Further, on Apple silicon Macs (M1/M2), you need to set the following environment
variables:

``` sh
export IDRIS2_LIBS=/opt/homebrew/lib
export CPATH=/opt/homebrew/include:/opt/homebrew/lib
```

### 2: Installing without an existing Idris 2

The simplest way needs only a C compiler: see
[Bootstrapping with only a C compiler](#bootstrapping-with-only-a-c-compiler)
below.

You can also build from pre-built Chez Scheme source, as long as you have Chez
Scheme installed (or, alternatively, Racket). To do this, enter one of the
following:

- `make bootstrap SCHEME=chez`
- `make bootstrap-racket`

`chez` is the executable name of the Chez Scheme compiler. You may need to
replace this with the executable for Chez Scheme on your system. This could be
`scheme`, `chezscheme` or `chezscheme9.5` or something else, depending on your
system and the Chez Scheme version.

On Windows, if bootstrapping from Chez Scheme gives an error about not being
able to find `Program.boot`, either move Chez Scheme to a path with no spaces
or use Racket instead. This is
[a known issue with Chez Scheme on Windows](https://github.com/cisco/ChezScheme/issues/1078).

This builds an Idris 2 compiler from Scheme code output from a working Idris 2
compiler (which isn't necessarily up to date, but is up to date enough to
build the current repository). It then rebuilds the compiler and the
libraries using the result. `make bootstrap-test` runs the tests with the
bootstrapped compiler.

If all is well, to install, type:

- `IDRIS2_CG=chez make install` after `make bootstrap SCHEME=chez`
- `IDRIS2_CG=racket make install` after `make bootstrap-racket`

The `IDRIS2_CG` setting matters: a plain `make install` assumes a compiler
built with RefC, the default, and installs the libraries without the compiled
Scheme code of their modules, which incremental builds with Chez use.

The compiler built this way still compiles programs with the RefC backend by
default: pass `--cg chez` (or `--cg racket`), or set `IDRIS2_CG`, to use the
Scheme backend.

#### Bootstrapping with only a C compiler

If neither Chez Scheme nor Racket is available, you can bootstrap from the C
code that the RefC backend generated for the compiler
(`bootstrap/idris2_app/idris2.c.xz`). This needs only a C compiler, `make`,
`xz` and GMP:

- `make bootstrap-c`

The compiler built this way uses the RefC backend, which is the default code
generator. It is slower than a compiler built with Chez Scheme. Like every
program compiled with RefC, it runs its main expression on a large stack of
its own (see `IDRIS2_MAIN_STACK_SIZE` in the RefC documentation), so the
stack limit of the shell (`ulimit -s`) does not limit it; the launcher script
`idris2` that runs it raises that limit anyway, as a fallback for when that
stack cannot be allocated and the program runs on the stack of the process.
The generated C is compiled in parts by C compilers running in parallel, one per processor;
set `BOOT_JOBS` to run fewer of them (each needs a few hundred MB of memory),
and `BOOT_CFLAGS` to change the flags of this first compiler (`-O1`, without
link time optimisation: it is quick to build, and it only builds the
libraries and the compiler that is installed). That compiler is built with
`-O2` and link time optimisation (`-flto=auto`, when the C compiler supports
it), which makes it about 4% faster but takes about twice as long to build:
`make bootstrap-c LTO=0` builds it with `-O1` and without link time
optimisation instead. The same variable applies to a plain `make` that builds
the compiler with RefC, with `LTO=0` as the default there (`make LTO=1` for
the optimised build). When the RefC backend
compiles the compiler (or any big program) it does the same, with
`IDRIS2_CC_JOBS` in place of `BOOT_JOBS`. The modules of the compiler and of
the libraries are checked by up to `IDRIS2_JOBS` processes in parallel (with
every way of building Idris 2: `make IDRIS2_JOBS=1` checks them one after the
other). With the RefC backend, the libraries that do not depend on each other
(for instance `contrib` and `linear`) are also built at the same time, each
of them using half of `IDRIS2_JOBS`; `make LIBS_PARALLEL=1` builds them one
after the other, as the Scheme backends always do. Once Chez Scheme is
available, you can
rebuild Idris 2 with it as described in [step 5](#5-optional-self-hosting-step).

When built with RefC, the compiler has no Chez Scheme evaluator, so the REPL
evaluation mode `:set eval scheme` is not available.

### 3: Installing with an existing Idris 2

If you have an Idris 2 built from this repository installed:

- `make all`
- `make install`

If you have the latest *released* version of Idris 2 (0.8.0 at the time of
writing) installed, build with its Chez Scheme backend, which is the way this
is tested: the RefC backend of 0.8.0 is not known to compile this compiler.

- `IDRIS2_CG=chez make all`
- `IDRIS2_CG=chez make install`

You can then rebuild with RefC, as described in
[step 5](#5-optional-self-hosting-step).

### 4: (Optional) Installing Idris 2 library documentation

After `make install`, type `make install-libdocs` to install Idris 2 library documentation.  After
that, the index file can be found here: ``"${BROWSER:-echo}" "$(idris2 --libdir)"/docs/index.html``

### 5: (Optional) Self-hosting step

As a final step, you can rebuild from the newly installed Idris 2 to verify
that everything has worked correctly. Assuming that `idris2` is in your
`PATH`.

- `make clean` -- to make sure you're building everything with the new version
- `make all && make install` -- to build with RefC, the default, OR
`IDRIS2_CG=chez make all && IDRIS2_CG=chez make install`
if using Chez Scheme, OR
`IDRIS2_CG=racket make all && IDRIS2_CG=racket make install`
if using Racket.

### 6: Running tests

After `make all`, type `make test` to check everything works. This uses the
executable in `./build/exec`.

### 7: (Optional) Enabling incremental compilation

If you are working on Idris, incremental compilation means that rebuilds are
much faster, at the cost of runtime performance being slower. To enable
incremental compilation for the Chez backend, build with Chez
(`IDRIS2_CG=chez`) and set the environment variable `IDRIS2_INC_CGS=chez`, or
set the `--inc chez` flag in `idris2.ipkg`: for instance,
`IDRIS2_CG=chez IDRIS2_INC_CGS=chez make all`. (The RefC backend has no
incremental mode, but it reuses the object files of the parts of a big
program that did not change, see the RefC documentation.)

### 8: (Optional) Installing the Idris 2 API

You'll only need this if you're developing support tools, such as an external
code generator. To do so, once everything is successfully installed, type:

- `make install-api`

The API will only work if you've completed the self-hosting step (step 5), since
the intermediate code versions need to be consistent throughout. Otherwise, you
will get an `Error in TTC: TTC data is in an older format` error.

### 9: (Optional) Shell Auto-completion

Idris2 supports tab auto-completion for Bash-like shells.

#### For Bash Users

From within bash, run the following command:

```sh
eval "$(idris2 --bash-completion-script idris2)"
```

You can also add it to your `.bashrc` file.

#### For ZSH Users

From within ZSH, run the following commands:

```sh
eval "$(idris2 --zsh-completion-script idris2)"
```

ZSH auto-completion is implemented via `bashcompinit`.

You can also add them to your `.zshrc` file.

### Troubleshooting

If you get the message `variable make-thread-parameter is not bound` while
bootstrapping via Chez Scheme, or while running the tests when bootstrapping via
Racket, then your copy of Chez Scheme was built without thread support. Pass
`--threads` to `./configure` while building Chez Scheme to correct the issue.

## Running in text editor

### Run on emacs using nix flakes

If you are a [nix flakes](https://nixos.wiki/wiki/Flakes) user you can run
Idris 2 in emacs by running the following command:

```sh
nix run github:idris-lang/Idris2#emacs-with-idris idrisCode.idr
```

## Installing Chez Scheme on Apple Silicon

Chez scheme only supports Apple Silicon for versions `10.0.0` or newer.

Homebrew bundles Chez Scheme 10+ so if that's your manager of choice, you don't
need to read on.

If you cannot install that new of a version of Chez Scheme, you will need to
build and install the Racket fork of chez scheme.

```sh
git clone git@github.com:racket/ChezScheme.git
cd ChezScheme
./configure --threads
make
sudo make install
```
