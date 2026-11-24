# Threads, channels, crashes, descriptors, sockets

Every example is a complete program: its imports are in the first block, and
`main = exThreads` (or another example) runs it. Threads, channels, `catchCrash`
and descriptor waits are in `base`; sockets need `-p network` (`depends =
network`).

```idris
import Data.Buffer
import Data.IORef
import Data.List
import Network.Socket.Async
import System
import System.Clock
import System.Concurrency
import System.Crash
import System.IO.Fd
```

## The runtime, by backend

- **RefC** (the default of this fork): `fork` starts a *green thread*. The runtime
  runs them on one worker per processor (`IDRIS2I_1_WORKERS=N` sets the number,
  `IDRIS2I_1_WORKERS=1` runs all of them on one OS thread). Scheduling is mostly
  cooperative, with preemption at safepoints (loop iterations, recursive calls)
  after 10 ms; `IDRIS2I_1_PREEMPT=0` turns that off. `sleep`/`usleep` and every wait
  below park the green thread, not the worker. A blocking C call (reading
  standard input, say) blocks its worker only. Each thread has an 8 MB stack
  of address space (`IDRIS2I_1_THREAD_STACK_SIZE`), used only as it grows.
- **POSIX only.** Green threads work on Linux, macOS, the BSDs. On Windows (and
  WebAssembly) the program builds, but `fork` reports an error, descriptor waits
  return at once and the non-blocking sockets fail with `ENOSYS`. The JavaScript
  backends have none of `network`, `http`, `tls`.
- **Chez and Racket**: `fork` is an OS thread; the same programs work, each wait
  blocking its thread.
- The program ends when `main` returns: threads still running are abandoned.
  `threadWait` (from the Prelude) waits for one. If every thread is blocked
  forever, RefC reports a deadlock and exits.
- Values are reference counted and **there is no cycle collector on RefC**: a
  long-running program leaks every cycle of references it builds (closures that
  refer to each other through an `IORef`, say).

## Threads, channels, mutexes, atomic `IORef`s

`fork : IO () -> IO ThreadID` and `threadWait : ThreadID -> IO ()` are in the
Prelude. `System.Concurrency` has `makeChannel` (holds **one** value: a second
`channelPut` waits), `makeBufferedChannel n`, `makeUnboundedChannel`,
`channelPut`, `channelGet`, `channelGetWithTimeout ch milliseconds` (`partial`); `makeMutex`,
`mutexAcquire`, `mutexRelease` (recursive); `makeCondition`, `conditionWait
cond mutex`, `conditionSignal`, `conditionBroadcast`; `makeSemaphore`,
`makeBarrier`. `Data.IORef.atomicModifyIORef ref f` with `f : a -> (a, b)` is
safe under contention: `f` may run more than once, so keep it pure.

```idris
exThreads : IO ()
exThreads = do
  results <- makeUnboundedChannel
  counter <- newIORef (the Int 0)
  lock <- makeMutex
  log <- newIORef (the (List String) [])
  tids <- for [1 .. 8] $ \i => fork $ do
    pure ()
    channelPut results (i * i)
    atomicModifyIORef_ counter (+ 1)
    mutexAcquire lock
    modifyIORef log (("thread " ++ show i) ::)
    mutexRelease lock
  for_ tids $ \t => threadWait t           -- threadWait is linear: not point-free
  squares <- for [1 .. 8] $ \_ => channelGet results
  printLn (sort squares)                     -- [1, 4, 9, ..., 64]
  printLn !(readIORef counter)               -- 8
  printLn (length !(readIORef log))          -- 8
```

## TRAP: the work must start inside the forked action

Idris2i-1 is strict: an argument is computed before the call. A `let` before the
action, or a value computed to build the action, is computed **in the parent**,
and the threads then do nothing in parallel:

```idris
work : Integer -> Integer
work n = go n 0
  where
    go : Integer -> Integer -> Integer
    go 0 acc = acc
    go k acc = go (k - 1) (acc + k `mod` 7)

msSince : Clock Monotonic -> IO Integer
msSince t0 = do
  t1 <- clockTime Monotonic
  pure (toNano (timeDifference t1 t0) `div` 1000000)

exStrict : IO ()
exStrict = do
  n <- map (\args => cast (length args) * 20000000) getArgs   -- not a constant
  ch <- makeChannel
  t0 <- clockTime Monotonic
  _ <- fork (let r = work n in channelPut ch r)               -- WRONG: parent computes
  putStrLn "let: fork returned after \{show !(msSince t0)} ms"
  ignore (channelGet ch)
  t0 <- clockTime Monotonic
  _ <- fork (do pure (); channelPut ch (work n))              -- RIGHT: child computes
  putStrLn "pure (): fork returned after \{show !(msSince t0)} ms"
  ignore (channelGet ch)
```

The first `fork` returns after the whole computation (about 90 ms here), the
second at once. A `do let r = work n` at the top of the block is the same
mistake. Today `fork (channelPut ch (work n))` happens to do the work in the
child, because the optimiser moves the argument into the action, but nothing
in the language promises it: start the block with `pure ();` (or bind the work,
`r <- pure (work n)`), which puts everything after it inside a function that
only the new thread calls. Measure a parallel program with `IDRIS2I_1_WORKERS=1`
and with the default: if the times are the same, the work ran in one thread.
A definition without arguments (`n = 20000000` at the top level) is a
constant, computed once on first use; it hides the problem in tests.

## Crash boundaries: `System.Crash.catchCrash` (this fork)

`catchCrash act : io (Either CrashInfo a)` runs `act` so that a crash of it ends
the action instead of the program: `idris_crash`, a missing case of a `partial`
function, an access out of a `Buffer`, a division by zero. `CrashInfo` has
`kind` (`CrashCall`, `MissingCase`, `FailedCheck`), `message`, `backtrace` (with
`IDRIS2I_1_REFC_BACKTRACE=1`). `crashesCaught` counts them. The HTTP server runs
every handler in one.

It is for isolation, not error handling. A caught crash **leaks** what the
abandoned code still held (about 50 bytes to 1 KB each), a `Mutex` it held
**stays held**, and its writes to `IORef`s and files stay done. It does not
catch a stack overflow or other signals, a crash in a finaliser, a crash of a
thread forked inside it, `exit`, or out of memory. On RefC, Chez, Racket and
JavaScript (`crashBoundaries` says whether this backend has them).

```idris
partial
firstOf : List a -> a
firstOf (x :: _) = x

partial
exCrash : IO ()
exCrash = do
  r1 <- catchCrash (pure (firstOf (the (List Int) [])))
  case r1 of
    Left info => putStrLn "caught: \{info.message}"
    Right v => printLn v
  Just buf <- newBuffer 4
    | Nothing => pure ()
  r2 <- catchCrash (getBits8 buf 100)
  putStrLn (either (\i => "caught: \{i.message}") show r2)
  r3 <- catchCrash (pure (the Int 7 `div` 0))
  putStrLn (either (\i => "caught: \{i.message}") show r3)
  printLn !crashesCaught                      -- 3
```

## Waiting for a file descriptor: `System.IO.Wait`, `System.IO.Fd`

`waitReadable fd deadline` / `waitWritable` park the green thread until the
descriptor is ready (`Ready`, `TimedOut`, `WaitError errno`). Deadlines are
`Maybe Int` in nanoseconds on the clock of `now`; `deadlineIn ns` makes one.
Readiness is edge-triggered: wait only after a read or write said `EAGAIN`
(`wouldBlock`) on a descriptor made non-blocking with `setNonBlocking`;
`readFdWait` and `writeFdWait` do that loop. Close such a descriptor with
`closeFd` (it wakes the waiters); call `forgetFd` before handing it to code that
closes it itself.

```idris
exPipe : IO ()
exPipe = do
  Right (r, w) <- pipe
    | Left e => putStrLn "pipe: \{show e}"
  ignore (setNonBlocking r)
  Just buf <- newBuffer 64
    | Nothing => pure ()
  _ <- fork $ do
    usleep 50000
    Just out <- newBuffer 5
      | Nothing => pure ()
    setString out 0 "hello"
    ignore (writeFd w out 0 5)
  n <- readFdWait r buf 0 64          -- parks until the writer writes
  putStrLn "read \{show n}: \{!(getString buf 0 n)}"
  ignore (closeFd r)
  ignore (closeFd w)
```

## Sockets: `Network.Socket.Async` (network, this fork)

Non-blocking sockets for one green thread per connection. Each operation waits
for the socket and returns `Either NetError a` (`Timeout`, `Closed`,
`SysError errno message`, `ResolveError`); the last argument is an optional
deadline. Addresses are numeric (`Inet "127.0.0.1" 8080`, `Inet6`, `UnixPath`, in
`Network.Socket.Address`, re-exported); `connectHost host port deadline`
resolves a name. Data moves between the socket and a `Buffer` at an offset:
`recv s buf off len dl` (returns 0 at end of stream), `sendAll s buf off len dl`,
`recvExactly`. `listenOn addr backlog` binds with `SO_REUSEADDR` and listens;
`localAddress` gives the port picked for port 0. Close with `close`.

A TCP echo server and a client in one program:

```idris
covering
echo : AsyncSocket -> IO ()
echo s = do
  Just buf <- newBuffer 4096
    | Nothing => ignore (close s)
  loop buf
  where
    loop : Buffer -> IO ()
    loop buf = do
      Right n <- recv s buf 0 4096 Nothing
        | Left _ => ignore (close s)
      if n == 0
         then ignore (close s)            -- the peer closed
         else do Right () <- sendAll s buf 0 n Nothing
                   | Left _ => ignore (close s)
                 loop buf

covering
acceptLoop : AsyncSocket -> IO ()
acceptLoop l = do
  Right s <- accept l Nothing
    | Left e => putStrLn "accept: \{show e}"   -- Closed once l is closed
  _ <- fork (echo s)
  acceptLoop l

covering
exEcho : IO ()
exEcho = do
  Right l <- listenOn (Inet "127.0.0.1" 0) 128
    | Left e => putStrLn "listen: \{show e}"
  Right addr <- localAddress l
    | Left e => putStrLn (show e)
  putStrLn "listening on port \{show (addrPort addr)}"
  _ <- fork (acceptLoop l)
  d <- deadlineIn 5000000000                         -- 5 s from now
  Right c <- connect addr (Just d)
    | Left e => putStrLn "connect: \{show e}"
  Just buf <- newBuffer 64
    | Nothing => pure ()
  setString buf 0 "ping"
  Right () <- sendAll c buf 0 4 (Just d)
    | Left e => putStrLn (show e)
  Right n <- recvExactly c buf 0 4 (Just d)
    | Left e => putStrLn (show e)
  putStrLn "echoed: \{!(getString buf 0 n)}"
  ignore (close c)
  ignore (close l)
```

`Network.Socket` is the older blocking API of upstream (`socket`, `bind`,
`listen`, `accept`, `send`/`recv` of `String`s); each call blocks its worker. Use
it only for simple clients. The `tls` library wraps these sockets (see `tls.md`),
and the `http` library is built on them (see `http.md`).
