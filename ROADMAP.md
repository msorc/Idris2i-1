# Roadmap

This file lists what is known to be missing, unfinished or untested in this
tree. Each entry says what the gap is and, where it is known, what it costs or
what a fix would need. Numbers are user-space instructions from `perf stat`
unless they say otherwise.

## Issues

### Platforms

* Everything network-related has only been run on Linux. The kqueue back end
  of the reactor (`support/refc/reactor.c`, for macOS and the BSDs) has never
  been built or run; the `poll` fallback (`-DIDRIS2_REACTOR_POLL`) has.
* macOS and BSD paths that are written but untested: `SO_NOSIGPIPE` and the
  `fcntl` fallback of the non-blocking sockets, the `dlsym` lookup of the
  runtime hooks in `support/c/idris_net_async.c`, `getentropy` for WebSocket
  masking keys (declared in another header there), the `tls` library.
* Windows has no green threads: a wait for a descriptor returns at once, and
  the non-blocking socket functions are stubs that return `ENOSYS`.
* Racket: the support code for atomic `IORef`s, buffered channels, crash
  boundaries and the TLS library has never been run (Racket is not installed
  on the machine all of this was developed on). Gambit has no atomic `IORef`
  operations and no crash boundary.
* Node: `Int` has 32 bits there, so `FromJSON Int` wraps above 2^31, and some
  tests of `contrib` and `http` fail on Node for that reason and for the way
  it prints `Double`s. The `network`, `http` and `tls` libraries do not
  support JavaScript.

### RefC runtime

* A program built with `-DIDRIS2_SINGLE_WORKER` has no safepoints and no
  monitor thread: a thread that computes starves all the others, a server
  included. Use `IDRIS2_WORKERS=1` instead.
* A cycle made only of closure calls that are not tail calls (recursion
  through interface methods, for example) is not preempted. A safepoint in
  `idris2_call_closure` would cover it and cost about 1% on the compiler.
* A descriptor that becomes ready can wait about 1 ms before its thread
  runs, and up to about 11 ms when all the workers have just become busy.
* Crash boundaries (`System.Crash.catchCrash`) do not catch signals (stack
  overflow included), crashes in finalisers, or crashes in threads forked
  inside the boundary. A caught crash leaks what the abandoned code held
  (about 50 bytes to 1 KB each in the tests), and a `Mutex` it held stays
  held.
* There is no cycle collector: a long-running program leaks every cycle of
  references it makes.
* A contended `Mutex` is 2 to 3 times slower than Go's and its time varies
  from run to run (0.14 to 0.38 s for 8 threads and 200,000 acquisitions
  each); an uncontended one is about 5 times slower.
* One HTTP/2 connection is no faster with four workers than with one, and
  each request then costs 40% more instructions (about 122,000 against
  87,000 over cleartext HTTP/2): idle workers steal the stream threads of a
  connection, everything those threads capture is then counted atomically,
  and they all take the lock of the connection. A `fork` that keeps the new
  thread on the worker of its parent unless it blocks or runs long would be
  needed.
* Reading and writing an `IORef` are calls into the runtime, about 20 to 30
  instructions each: a WebSocket round trip makes about 30 of them, which
  is most of what it costs over Go's gorilla/websocket (7,800 against 5,800
  instructions for a 64-byte message).
* An idle connection keeps about 13 kB resident, most of it the pages
  touched on the stack of its green thread.

### Chez back end

* Network I/O through the blocking fallback burns kernel time: the
  100-connection echo costs 27 times the CPU of RefC, with 1.6 `futex`
  calls per round trip. The suspected cause, not verified, is the lock taken
  around each blocking foreign call.
* Closing a descriptor does not wake a thread that waits for it.
* `blodwen-semaphore-wait` does not loop on a spurious wake-up, and
  `blodwen-barrier-wait` can only be used once.

### Code generation

* An `IO` function is compiled into a function that returns a closure,
  which is allocated and then applied to the world, when its body chooses
  between actions and a branch is a bare call, when a `let` that is not
  trivial comes before its first action, or when a statement is followed by
  an `if` or a `case`. The `http` library works around it by hand
  (`() <- pure ()`); eta-expanding `IO` functions in the compiler and
  pushing the world into the branches would remove it everywhere, an
  estimated 5 to 15% of the instructions of code that is mostly `IO`.

### Building and compile speed

* A module is not rebuilt when its direct imports keep their interface
  hashes, even if a module it reaches only indirectly changed the body of a
  `public export` definition (A imported by B imported by C, B not
  re-exporting A). This was so before the build driver learnt the same
  check.
* `-p pkg` on the command line does not load the packages that `pkg` depends
  on (`-p http` needs `-p contrib` too), unlike `depends` in an `.ipkg`.
* A `..` component in `IDRIS2_PREFIX` or a package directory makes every
  module lookup slower (+38% on checking an empty module).
* A long `do` block is checked in time that grows faster than its length
  (200 statements take about 1.9 s), mostly in nested delayed case blocks;
  untyped numeric literals make it much worse.
* Type-level evaluation of a long computation is slow and deep
  (`tests/idris2/perf/perf013`: 135 G instructions and 1.6 GB).
* Ideas measured but not built: skipping the retry of a search whose goal
  has not changed (up to 40% of the time spent in search), worker processes
  of `--jobs` that build more than one module (4 to 8%), a mutable cursor
  for reading and writing TTC files (writing `.ttm` files is 2.5% of a build
  of `base`), registering the names of imports lazily (16 times more names
  are registered than are ever decoded), and not compiling definitions under
  `--typecheck` (4 to 5%).
* The parser builds its grammar rules again at every call, and parses the
  left-hand side of every clause twice (once as an implementation
  declaration); the lexer works on a `List Char`.

### Error messages

* IDE mode sends errors and warnings alike as `:warning`, with no severity
  and no error code: the protocol has no version negotiation to add them
  compatibly.
* A failed search for an implementation does not say which call needed it
  (the origin of the hole is not recorded), nor whether an implementation
  exists in a module that is not imported.
* 45 of the 78 error codes have a title but no explanation for `--explain`.
* About 80 messages are still built from `show` of an internal name or term
  (`GenericMsg`): most in `TTImp.ProcessBuiltin` and `Idris.Desugar`.
* An overload candidate that is not a name, a macro or a coercion is still
  listed as "Possible error".
* `Show JSON` (contrib) prints text that is not JSON for infinities,
  subnormal numbers and characters above U+FFFF; `Language.JSON.Encode` is
  correct.

### Libraries

* `http`, HTTP/1.1: `bodyTimeout` bounds each read, not the whole body;
  `stopServer` can cut off a request that arrives in the instant it shuts
  an idle connection down; the client has no cookies, proxies or
  compression and does not wait for `100 Continue`.
* `http`, HTTP/2: no response trailers, no server push, no WebSocket over
  HTTP/2 (RFC 8441); `PRIORITY` is ignored; TLS handshakes in progress do
  not count towards `maxConnections`.
* `http`, WebSocket: no `permessage-deflate`; only one thread at a time may
  receive; the idle timeout counts received messages only; `stopServer`
  ends sessions by closing them, not with a 1001 close frame; `wss://` is
  not covered by a test.
* `http`, cost per request: a server written by hand for one route does the
  HTTP/1.1 hello in about 3,100 instructions and the JSON echo in about
  13,200, where this library takes about 13,200 and 45,000 (Go's `net/http`:
  36,800 and 77,500). About 33 allocations per request remain, six of them
  for each header field of the request.
* `http`: the test `http/h2_validation` once gave a 200 where it expects a
  stream reset (a body shorter than its `content-length`, with four
  workers), and passed when run again: a race that has not been found.
* `tls`: session resumption and the paths where a read has to write (key
  update) are not covered by a test; there are no verification callbacks in
  Idris.
* JSON (contrib): numbers are `Double`s, so integers above 2^53 lose
  precision. A derived decoder is fast only when the members come in the
  order of the fields, once each and with nothing else; any other document
  is decoded through a `JSON` value.
* `network`: the linear API (`Control.Linear.Network`) has no non-blocking
  counterpart; `Network.Socket.DNS.resolve` takes a numeric port only.
* The comparison with Rust in the `bench-vs` branch uses servers written by
  hand, because no asynchronous HTTP framework was available to build
  offline; there is no Rust row for HTTPS, HTTP/2 or WebSocket.

### Language

* `Nat`, `Fin`, `Vect` at run time: the functions of `Data.Nat`, `Data.Fin`
  and `Data.Vect` that recursed once per unit run on `Integer` through
  `%transform` rules (see `benchmark/benchmarks/natOps` and `vectFin`), but
  only where a caller names them: code that copies their clauses, or a
  function defined before its rule in the same module, still runs the unary
  definition. Not covered: `hyper`, `cmp`, `maybeLTE`/`maybeLT`, `shift`,
  `weakenN`, `Vect.index`, `replaceAt`, `take`/`drop` (O(index), inherent
  to a list), and the `Subset` versions of `tabulate` and `range` (still
  O(n²)).
* `weakenLTE : Fin n -> LTE n m -> Fin m` takes its proof at quantity ω, so
  callers build a proof at run time. At quantity 0 its clauses are rejected
  (the match on the proof refines the bound); a definition without that
  match would reduce differently at type-checking time.
* The `believe_me` run-time versions (`isLTE`, `decEq` on `Nat`,
  `strengthen`, the `Num` of `Fin`, `complement`) rely on `Nat`-shaped
  types being `Integer`s on every backend (`calcNaty`). A backend that
  represents them otherwise would need the rules switched off.
* A proof search on a large `Nat` literal is unary: `gcd big 1234567890`
  with its auto `NotBothZero` hangs the type checker (it is not a run-time
  cost; give the proof, `{ok = LeftIsNotZero}`).
* `Data.Array` stores boxed elements. A `Flat a =>` variant over the flat
  slots of `Data.IOArray.Flat` (unboxed `Double`, `Int`, raw records on
  RefC) is not written: those slots are `Maybe`-typed at the primitive
  level, so it needs its own primitives or a `Maybe`-free slot interface.
  `zipWith` on an `Array` costs 17% more than on a `Vect` on RefC.
