# IO: programs, files, state

Every example is a complete program: its imports are in the first block, and
`main = exArgs` (or the name of another example) runs it. All of it is in `base`,
so no `-p` flag is needed, except where a section says so.

```idris
import Control.App
import Control.App.Console
import Control.Monad.Either
import Control.Monad.Reader
import Control.Monad.State
import Data.IORef
import Data.Maybe
import Data.String
import System
import System.Clock
import System.Directory
import System.File
```

## Contents

- Arguments, exit codes, environment
- Standard input and output
- Files
- Directories
- `IORef`
- Clock and time
- `StateT`, `ReaderT`, `EitherT`
- `Control.App` with exceptions

## Arguments, exit codes, environment

`getArgs` includes the program name as its first element, like C's `argv`.
`exitWith` takes an `ExitCode`; `ExitFailure` carries a proof that the code is not
zero, which a literal discharges by itself.

```idris
exArgs : IO ()
exArgs = do
  args <- getArgs
  case args of
    [_, name] => putStrLn "hello \{name}"
    (prog :: _) => do
      putStrLn "usage: \{prog} NAME"
      exitWith (ExitFailure 2)
    [] => exitFailure
  home <- getEnv "HOME"                 -- Maybe String
  putStrLn (fromMaybe "no HOME" home)
  ok <- setEnv "GREETING" "hi" True     -- True: overwrite
  Just g <- getEnv "GREETING"
    | Nothing => die "setEnv failed"    -- die prints to stderr and exits 1
  putStrLn g
  exitSuccess
```

`System` also has `system : String -> IO Int` (runs a shell command, returns its
exit status) and `run : String -> IO (String, Int)` (its standard output too);
the `Escaped.system`/`Escaped.run` variants take a `List String` and quote each
argument. `getPID`, `sleep : Int -> IO ()` (seconds) and `usleep` (microseconds,
the argument must be a non-negative literal or come with a proof) are there too.

## Standard input and output

`putStr` does not flush. Before reading an answer to a prompt, or when standard
output is a pipe that someone watches, `fflush stdout`. `getLine` returns `""` at
end of input; to tell an empty line from the end, use `fEOF stdin`.

```idris
covering
exStdin : IO ()
exStdin = do
  putStr "name? "
  fflush stdout
  name <- getLine
  ignore $ fPutStrLn stderr "read \{show (length name)} characters"
  loop 0
  where
    loop : Int -> IO ()
    loop n = do
      False <- fEOF stdin
        | True => putStrLn "lines: \{show n}"
      Right l <- fGetLine stdin          -- keeps the "\n"
        | Left e => putStrLn (show e)
      if l == "" then putStrLn "lines: \{show n}" else loop (n + 1)
```

## Files

Every file operation returns `Either FileError a`; nothing throws. `show` of a
`FileError` is a readable message ("File Not Found"). The functions are in
`System.File` (re-exporting `System.File.ReadWrite`, `.Handle`, `.Meta`, ...).

```idris
covering
exFiles : IO ()
exFiles = do
  let path = "/tmp/idris-io-example.txt"
  Right () <- writeFile path "one\ntwo\n"
    | Left e => die "write: \{show e}"
  Right () <- appendFile path "three\n"
    | Left e => die "append: \{show e}"
  Right s <- readFile path               -- the whole file as a String
    | Left e => die "read: \{show e}"
  printLn (lines s)                      -- ["one", "two", "three"]
  -- A handle, line by line
  Right h <- openFile path Read          -- Read, WriteTruncate, Append, ReadWrite...
    | Left e => die "open: \{show e}"
  Right first <- fGetLine h
    | Left e => die (show e)
  closeFile h
  putStrLn "first line: \{trim first}"
  b <- exists path
  Left err <- readFile "/nonexistent/file"
    | Right _ => pure ()
  putStrLn "expected failure: \{show err}"
  ignore (removeFile path)
```

`withFile path mode onError action` opens, runs `action : File -> io (Either a b)`
and closes. `copyFile src dst` returns `Either (FileError, Int) ()`. For bytes
rather than text, see `System.File.ByteString` in `collections.md` and
`System.File.Buffer` (`readBufferData`, `writeBufferData`).

## Directories

```idris
covering
exDirs : IO ()
exDirs = do
  let dir = "/tmp/idris-io-dir"
  Right () <- createDir dir              -- fails with FileExists if it is there
    | Left e => putStrLn "createDir: \{show e}"
  ignore $ writeFile (dir ++ "/a.txt") "a"
  Right names <- listDir dir             -- includes "." and ".."
    | Left e => die (show e)
  printLn (filter (\n => n /= "." && n /= "..") names)
  Just cwd <- currentDir
    | Nothing => die "no current directory"
  ok <- changeDir dir                    -- Bool
  ignore (removeFile (dir ++ "/a.txt"))
  ignore (changeDir cwd)
  removeDir dir                          -- returns (), fails silently
```

`System.Path` (in `contrib`, `-p contrib`) has `(</>)`, `parent`, `fileName`,
`extension`. `System.Directory.Tree` (contrib) walks a tree.

## `IORef`

`Data.IORef`: `newIORef`, `readIORef`, `writeIORef`, `modifyIORef`. With threads,
use `atomicModifyIORef ref (\x => (new, result))` (see `concurrency.md`).

```idris
exRef : IO ()
exRef = do
  r <- newIORef (the Int 0)
  for_ [1 .. 10] $ \i => modifyIORef r (+ i)
  n <- atomicModifyIORef r (\x => (x * 2, x))   -- new value first, result second
  v <- readIORef r
  putStrLn "\{show n} \{show v}"                -- 55 110
```

## Clock and time

`System.time : IO Integer` is seconds since the epoch. `System.Clock.clockTime`
takes the kind of clock; its result type depends on it (`Clock Monotonic`,
`Clock UTC`, ...). `timeDifference` gives a `Clock Duration`, `toNano` an `Integer`.

```idris
exClock : IO ()
exClock = do
  t0 <- clockTime Monotonic
  let s = sum [the Integer 1 .. 100000]
  t1 <- clockTime Monotonic
  let d = timeDifference t1 t0
  putStrLn "sum \{show s} in \{show (toNano d `div` 1000)} us"
  now <- clockTime UTC
  putStrLn "epoch seconds: \{show (seconds now)} = \{show !time}"
```

## `StateT`, `ReaderT`, `EitherT`

The transformers are those of `mtl`, with two differences a Haskell programmer
trips over: **the state comes first** in `runStateT s m`, `evalStateT s m`,
`runState s m`, `runReaderT r m`, and **`runStateT` returns `(state, result)`**,
not `(result, state)`. `lift` lifts, `liftIO` works under `HasIO`.

```idris
counter : StateT Int IO ()
counter = do
  modify (+ 1)
  n <- get
  lift (putStrLn "count \{show n}")
  put (n * 10)

lookupUser : String -> EitherT String IO Int
lookupUser "ann" = pure 1
lookupUser u = throwE "no user \{u}"     -- or `left`

greeting : ReaderT String IO ()
greeting = do
  who <- ask
  liftIO (putStrLn "hi \{who}")

exMonads : IO ()
exMonads = do
  (s, ()) <- runStateT 0 (counter >> counter)
  printLn s                                -- 110
  printLn (runState 5 (modify (* 2) >> gets (+ 1)))   -- (10, 11)
  r <- runEitherT (lookupUser "bob")
  printLn r                                -- Left "no user bob"
  runReaderT "ann" greeting
```

`Control.Monad.Writer`, `Control.Monad.RWS`, `Control.Monad.Maybe` (`MaybeT`) and
`Control.Monad.ST` exist too. `MonadState`, `MonadReader`, `MonadError`
(`throwError`, `catchError`) are the interfaces.

## `Control.App` with exceptions

`Control.App` is the effect library of `base`: `App es a` is a program that may
throw any error in the list `es`. `Has [Console, Exception E] es =>` asks for
capabilities; `handle act onOk onErr` removes one error type from the list;
`run` turns an `App Init a` into `IO a`. Its `putStrLn` is the `Console` method,
so a file that uses both `App` and plain `IO` printing must qualify one of them.

```idris
data BadInput = Negative Int

checked : Has [Console, Exception BadInput] es => Int -> App es Int
checked n = do
  when (n < 0) $ throw (Negative n)
  Console.putStrLn "ok: \{show n}"
  pure (n * 2)

tryBoth : App Init ()
tryBoth = handle (do x <- checked 5; y <- checked (-1); pure (x + y))
            (\v => Console.putStrLn "result \{show v}")
            (\(Negative n) => Console.putStrLn "negative: \{show n}")

exApp : IO ()
exApp = run tryBoth
```

`tryBoth` has the concrete list `Init`: with `Has [Console] es => App es ()`
instead, `handle` fails with "Can't find an implementation for Console
(BadInput :: es)", because `Console` comes from `PrimIO`, which is found in a
concrete list but not passed down from an abstract one.

`catch act handler` catches without removing the error from the list.
`Control.App.FileIO` has file operations that throw `IOError`. `new v act` adds a
`State tag t` (read with `get tag`, write with `put tag`).
