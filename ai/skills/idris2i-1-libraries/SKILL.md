---
name: idris2i-1-libraries
description: "Use when Idris2i-1 code needs libraries beyond the Prelude: HTTP servers/clients, routing, WebSocket, TLS/HTTPS, JSON encode/decode/derive, ByteString, HashMap/SortedMap, immutable arrays (`Data.Array`), files/directories/sockets/async IO, threads and channels, mutexes, atomic IORef, `catchCrash`, StateT/ReaderT/Control.App, string and number parsing, parser combinators, pretty printing, command-line parsing (GetOpt), deriving Eq/Ord/DecEq/Show/Functor (`Deriving.Eq`, `Deriving.Ord`, `Deriving.Show`). Gives the exact module, package and `-p` flags (they are not transitive), complete runnable examples, and how to discover an installed library's API with `:browse`/`:doc`/`:search`."
---

# Idris2i-1 libraries

This compiler (a fork of Idris 2 far ahead of upstream 0.8) ships libraries that
upstream does not have: `http` (HTTP/1.1, HTTP/2, router, WebSocket), `tls`,
`http-tls`, the non-blocking sockets of `network`, typed JSON with deriving,
`ByteString`, `HashMap`, crash boundaries, green threads on RefC. What you
remember of upstream `base`/`contrib` is partly wrong here, and names you
expect from Haskell often do not exist. Look names up (below) before using them.

The language itself, the check loop and `.ipkg` basics are in the `idris2i-1`
skill.

## Which module, which package, which flags

`-p` on the command line is **not transitive**: name every package the program
needs and every package those need. Leaving one out fails with
`Module Network.Socket.Async not found` (or `Data.ByteString`, `Network.TLS`).
An `.ipkg` `depends` line does load dependencies (`depends = http` is enough
there), but listing them all keeps the command line and the package in step.
The sets below are the minimal ones, found by building each example.

| need | modules | `-p` flags | `depends =` | read |
|---|---|---|---|---|
| args, exit codes, env, stdin/stdout, files, directories, clock | `System`, `System.File`, `System.Directory`, `System.Clock` | none (`base`) | `base` | `references/io.md` |
| mutable refs, `StateT`/`ReaderT`/`EitherT`, `Control.App` | `Data.IORef`, `Control.Monad.State`, `Control.Monad.Reader`, `Control.Monad.Either`, `Control.App` | none | `base` | `references/io.md` |
| `SortedMap`, `SortedSet`, `IOArray`, `Buffer`, `Vect`, `Fin`, `List1` | `Data.SortedMap`, `Data.SortedSet`, `Data.IOArray`, `Data.Buffer`, `Data.Vect`, `Data.List1` | none | `base` | `references/collections.md` |
| immutable array, O(1) `index : Fin n -> Array n a -> a` | `Data.Array` | none | `base` | `references/collections.md` |
| `HashMap`, `HashSet`, `Hashable` | `Data.HashMap`, `Data.HashSet` | `-p contrib` | `contrib` | `references/collections.md` |
| bytes: `ByteString`, `Builder`, byte files | `Data.ByteString`, `Data.ByteString.Builder`, `System.File.ByteString` | `-p contrib` | `contrib` | `references/collections.md` |
| split/trim/words, parse numbers | `Data.String` | none | `base` | `references/text.md` |
| parser combinators, lexer + grammar, pretty printer, command-line options | `Data.String.Parser`, `Text.Lexer`, `Text.Parser`, `Text.PrettyPrint.Prettyprinter`, `System.Console.GetOpt` | `-p contrib` | `contrib` | `references/text.md` |
| JSON: parse, encode, derive codecs | `Language.JSON`, `Language.JSON.Derive` | `-p contrib` | `contrib` | `references/json.md` |
| derive `Eq`, `Ord`, `DecEq`, `Show`, `Functor`, `Foldable`, `Traversable` | `Deriving.Eq`, `Deriving.Ord`, `Deriving.DecEq`, `Deriving.Show`, ... | none | `base` | `references/json.md` |
| threads, channels, mutex, condition, atomic `IORef`, `catchCrash`, waiting on fds | `System.Concurrency`, `Data.IORef`, `System.Crash`, `System.IO.Wait`, `System.IO.Fd` | none | `base` | `references/concurrency.md` |
| TCP/UDP sockets | `Network.Socket.Async` (non-blocking), `Network.Socket` (blocking) | `-p network` | `network` | `references/concurrency.md` |
| linear sockets | `Control.Linear.Network` | `-p linear -p network` | `linear, network` | `:browse` |
| HTTP server, router, client, WebSocket | `Network.HTTP.Router`, `Network.HTTP.Client`, `Network.WebSocket` | `-p contrib -p network -p http` | `contrib, network, http` | `references/http.md` |
| TLS sockets | `Network.TLS` | `-p network -p tls` | `network, tls` | `references/tls.md` |
| HTTPS server/client, `wss://` | `Network.HTTP.TLS` + the above | `-p contrib -p network -p http -p tls -p http-tls` | `contrib, network, http, tls, http-tls` | `references/tls.md` |
| futures, random numbers, paths | `System.Future`, `System.Random`, `System.Path` | `-p contrib` | `contrib` | `:browse` |
| signals (SIGINT) | `System.Signal` | none | `base` | `references/http.md` |
| golden tests | `Test.Golden` | `-p contrib -p test` | `contrib, test` | `:browse` |

`idris2i-1 --list-packages` shows what is installed. `tls` and `http-tls` exist
only where the compiler was built with OpenSSL 3; if they are missing, HTTPS is
not available (plain HTTP still is).

Fork-only (not in upstream 0.8): `http`, `tls`, `http-tls`,
`Network.Socket.Async`, `Language.JSON.{Typed,Derive,Encode,Parse}`,
`Data.ByteString*`, `Data.HashMap`/`HashSet`/`Hashable`, `System.File.ByteString`,
`System.Crash`, `System.IO.Wait`/`Fd`, buffered and unbounded channels,
`atomicModifyIORef`, `Data.Array`, `Deriving.Eq`/`Ord`/`DecEq`.

The newest of these came late, and a user's compiler may be older than the
fork's tip. To tell, ask the REPL: if `:module Data.Array` or
`:module Deriving.Eq` says "Module ... not found", the compiler predates them
(use `Vect` or `IOArray`, and write `Eq`/`Ord` by hand); `idris2i-1 --version`
prints the commit.

## Finding the API of an installed library

Installed packages have no sources: ask the compiler. In the REPL, a module
must be imported before `:browse` shows anything (**`:browse` of a module that
is not loaded prints nothing**, no error):

```sh
printf ':module Data.HashMap\n:browse Data.HashMap\n' | idris2i-1 --no-banner -p contrib
printf ':module Network.HTTP.Router\n:doc route\n:doc jsonBody\n' \
  | idris2i-1 --no-banner -p contrib -p network -p http
printf ':module Data.HashMap\n:search HashMap k v -> List k\n' | idris2i-1 --no-banner -p contrib
```

The `-p` flags are those of the table, as for building. With a file that
already imports the module, `idris2i-1 -p contrib F.idr --client ':doc lookupDefault'`
answers one question. `:doc` takes a name, not a module. `idris2i-1 --dump-api
your.ipkg` prints the public API of *your own* package (it builds from sources,
so not of installed ones).

## Facts that hold everywhere

- **`HasIO io =>`.** Library IO functions have types like
  `readFile : HasIO io => String -> io (Either FileError String)`: they run in
  `IO` and in any stack over it (`StateT s IO`, ...) without `lift`.
- **Errors are values.** Files return `Either FileError a`, sockets
  `Either NetError a`, TLS `Either TLSError a`, HTTP `Either HttpError a`,
  JSON `Either DecodeError a`. Nothing throws. Handle with the pattern-matching
  bind (`readFile` is from `import System.File`):

  ```text
  Right s <- readFile path
    | Left e => putStrLn "cannot read \{path}: \{show e}"
  ```

- **`cast` from `String` never fails**: `cast {to = Int} "12x"` is `0`. Use
  `parseInteger`, `parsePositive`, `parseDouble` (`Maybe`).
- **`String` is not `List Char`**: no `x :: xs` patterns on it; `unpack`,
  `strM`. `split` of `Data.String` takes a predicate and returns a `List1`.
- **Transformers take the state first**: `runStateT s m`, `evalStateT s m`,
  `runReaderT r m`, and `runStateT` returns `(state, result)`.
- **Annotate collections.** `empty`, `insert`, `lookup`, `fromList`, `toList`
  exist in many modules; with several imported, give the value a type
  (`let m : SortedMap String Int = ...`) or qualify (`SortedMap.lookup`).
  With `Data.ByteString` imported a string literal may also be a `ByteString`.
- **`covering`.** Much of `http` and `network` is `covering`, not `total`;
  put `%default covering` at the top of a file that uses them.
- **Derived instances are `%hint` values**: `%hint userTo : ToJSON User;
  userTo = %runElab deriveToJSON defaultOptions`, with `%language
  ElabReflection` in the file; `Eq`, `Ord`, `DecEq`, `Show` the same way with
  `%runElab derive`. No `deriving` clause. A derived `Foldable`'s
  `toList`/`foldr` comes out reversed (see `references/json.md`).
- **Backends.** RefC (C, the default) and Chez run everything; Racket should
  (less tested). `network`, `http`, `tls` do not support the JavaScript backends.
  Green threads, descriptor waits and non-blocking sockets are POSIX only
  (Linux tested; macOS/BSD written, untested); on Windows `fork` reports an
  error and the sockets fail with `ENOSYS`. `catchCrash` works on RefC, Chez,
  Racket, JavaScript, not Gambit.
- **RefC memory.** Reference counting, no cycle collector: a long-running
  server leaks every reference cycle it creates. `catchCrash` leaks what the
  crashed code held.
- **Threads are strict too.** Work written as an argument or a `let` before
  the forked action may run in the parent. Start the action with `pure ();`:
  `fork (do pure (); channelPut ch (work x))` (`references/concurrency.md`).
- **Thread settings (RefC):** `IDRIS2I_1_WORKERS=N` (default: one per processor),
  `IDRIS2I_1_PREEMPT=0` (no time-slice preemption), `IDRIS2I_1_THREAD_STACK_SIZE`,
  `IDRIS2I_1_REFC_BACKTRACE=1` (backtraces in crash messages).

## The references

Each reference file is literate Idris2i-1: its examples type-check, and each one
named `exSomething : IO ()` is a whole program (imports in the file's first
block, `main = exSomething`).

- `references/io.md`: `main`, args, exit codes, env, stdin, files, directories,
  `IORef`, clock, `StateT`/`ReaderT`/`EitherT`, `Control.App`.
- `references/collections.md`: `SortedMap`/`SortedSet`, `Data.Array`, `HashMap`/`HashSet`/
  `Hashable`, `ByteString`/`Builder`/byte files, `IOArray`, `Buffer`, `Vect`/
  `Fin`, `List1`.
- `references/text.md`: `Data.String`, number parsing, `Data.String.Parser`,
  `Text.Lexer`/`Text.Parser`, the pretty printer, `GetOpt`.
- `references/json.md`: JSON values, typed codecs, `deriveToJSON`/
  `deriveFromJSON`, hand-written instances, `Deriving.*`.
- `references/concurrency.md`: green threads, channels, mutexes, the strictness
  trap of `fork`, `catchCrash`, fd waits, a TCP echo server.
- `references/http.md`: a JSON service with the router, serving until Ctrl-C,
  the client, WebSocket.
- `references/tls.md`: TLS sockets, HTTPS server and client.
