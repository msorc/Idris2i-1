||| Crash boundaries: run an `IO` action so that a crash inside it ends only
||| that action.
|||
||| A crash is what stops a program that has no way to go on: `idris_crash`,
||| a case that compiled code has no clause for (a `partial` function given
||| an input it does not cover, an `assert_total` that was wrong, a hole), a
||| check of the runtime that failed (an access out of a `Buffer`, an invalid
||| length, an `Integer` division by zero).  Without a boundary it prints its
||| message and exits the whole program, with every thread.  Inside
||| `catchCrash`, it ends the action instead, and `catchCrash` returns what
||| happened.
|||
||| This is for isolation at the boundary of a service: one bad request of a
||| server costs that request, not the server (the HTTP server of the `http`
||| library puts one around each handler).  It is not for control flow:
||| use `Maybe`, `Either` or `Control.App` for errors that the program
||| expects.
|||
||| # WARNING: what a caught crash leaves behind
|||
|||  * Memory: on the RefC back end, the values that the abandoned code still
|||    held are never freed (a handler's request, say).  Every caught crash
|||    leaks them for good: from about 50 bytes to whatever the code held
|||    (hundreds of bytes for the request of an HTTP handler).
|||    `crashesCaught` counts the crashes, so that a long-running program can
|||    be restarted before the leak matters.
|||  * Locks: a `Mutex` that the code held when it crashed stays held (by the
|||    thread that ran `catchCrash`, which may release it); other threads
|||    waiting for it keep waiting.  Do not crash while holding a lock that
|||    others need, or release it after `catchCrash` returns.
|||  * Partial effects: what the action did before the crash stays done: the
|||    `IORef`s, arrays and buffers it wrote, the bytes it sent, the files it
|||    opened (and did not close).  Data structures that it was in the middle
|||    of changing through such references may be half changed.
|||  * Foreign code: a crash in an Idris callback called from C abandons the
|||    C frames too; a C library that holds a lock or state across the
|||    callback is left as it was.
|||
||| # What is not caught
|||
||| These stay fatal, inside a boundary too: `exit` and `exitWith` (they
||| exit, as asked); a stack overflow and the signals of the operating system
||| (a segmentation fault from foreign code, say); a crash inside a
||| finaliser (`onCollect`), which may run anywhere; failures of the runtime
||| itself (out of memory, a broken invariant, a deadlock, a `Mutex`
||| released by a thread that does not hold it).
|||
||| # Back ends
|||
||| RefC and Chez Scheme catch crashes (Chez catches the errors that Scheme
||| raises too, as failed checks: `vector-ref` out of range, say); the
||| JavaScript back ends do as well.  On a back end without boundaries
||| (Gambit), `catchCrash` runs the action without one: a crash exits as
||| before, and `crashBoundaries` is `False`.
module System.Crash

%default total

||| What crashed.
public export
data CrashKind : Type where
  ||| A call of `idris_crash`.
  CrashCall : CrashKind
  ||| Compiled code with no clause for a value (a missing case of a
  ||| `partial` or `assert_total` function), or a hole.
  MissingCase : CrashKind
  ||| A check of the runtime that failed: an access out of a `Buffer`, an
  ||| invalid length, an `Integer` division by zero (on Chez and JavaScript,
  ||| any error that the runtime raises).
  FailedCheck : CrashKind

export
Show CrashKind where
  show CrashCall = "crash call"
  show MissingCase = "missing case"
  show FailedCheck = "failed check"

export
Eq CrashKind where
  CrashCall == CrashCall = True
  MissingCase == MissingCase = True
  FailedCheck == FailedCheck = True
  _ == _ = False

||| What a boundary reports about a crash.
public export
record CrashInfo where
  constructor MkCrashInfo
  kind : CrashKind
  ||| The message of the crash (without the "ERROR: " that it is printed
  ||| with when it exits the program).
  message : String
  ||| The backtrace of the crash, innermost call first, down to the
  ||| boundary, when backtraces are on (on RefC: `IDRIS2I_1_REFC_BACKTRACE=1`,
  ||| or a program compiled with `--directive refc-backtrace`).
  backtrace : Maybe String

export
Show CrashInfo where
  show c = show c.kind ++ ": " ++ c.message

-- Run an action in a boundary: its result, or, if it crashed, a value that
-- must not be looked at (NULL on RefC), and then `prim__crashCaught` is 1
-- and the functions below tell what happened, until `prim__crashClear`.
%foreign "RefC:idris2i_1_crashCatch"
         "scheme:blodwen-crash-catch"
         "javascript:lambda:(ty, act, w) => __prim_crash_catch(act)"
prim__crashCatch : {0 a : Type} -> PrimIO a -> PrimIO a

%foreign "RefC:idris2i_1_crashCaught"
         "scheme:blodwen-crash-caught"
         "javascript:lambda:(w) => __prim_crash_last === null ? 0 : 1"
prim__crashCaught : PrimIO Int

%foreign "RefC:idris2i_1_crashKind"
         "scheme:(lambda () (vector-ref (blodwen-crash-last) 0))"
         "javascript:lambda:(w) => __prim_crash_last.kind"
prim__crashKind : PrimIO Int

%foreign "RefC:idris2i_1_crashMessage"
         "scheme:(lambda () (vector-ref (blodwen-crash-last) 1))"
         "javascript:lambda:(w) => __prim_crash_last.message"
prim__crashMessage : PrimIO String

%foreign "RefC:idris2i_1_crashHasBacktrace"
         "scheme:(lambda () (if (vector-ref (blodwen-crash-last) 2) 1 0))"
         "javascript:lambda:(w) => __prim_crash_last.backtrace === null ? 0 : 1"
prim__crashHasBacktrace : PrimIO Int

%foreign "RefC:idris2i_1_crashBacktrace"
         "scheme:(lambda () (or (vector-ref (blodwen-crash-last) 2) \"\"))"
         "javascript:lambda:(w) => __prim_crash_last.backtrace === null ? '' : __prim_crash_last.backtrace"
prim__crashBacktrace : PrimIO String

%foreign "RefC:idris2i_1_crashClear"
         "scheme:(lambda () (blodwen-crash-last #f))"
         "javascript:lambda:(w) => { __prim_crash_last = null }"
prim__crashClear : PrimIO ()

%foreign "RefC:idris2i_1_crashesCaught"
         "scheme:blodwen-crashes-caught"
         "javascript:lambda:(w) => __prim_crashes_caught()"
prim__crashesCaught : PrimIO Int

%foreign "RefC:idris2i_1_crashBoundaries"
         "scheme:blodwen-crash-boundaries"
         "javascript:lambda:() => 1"
prim__crashBoundaries : Int

kindOf : Int -> CrashKind
kindOf 0 = CrashCall
kindOf 1 = MissingCase
kindOf _ = FailedCheck

-- What the last boundary of the thread caught (and forget it).
caughtCrash : IO CrashInfo
caughtCrash = do
  k <- primIO prim__crashKind
  msg <- primIO prim__crashMessage
  hasBt <- primIO prim__crashHasBacktrace
  bt <- if hasBt == 0 then pure Nothing else Just <$> primIO prim__crashBacktrace
  primIO prim__crashClear
  pure (MkCrashInfo (kindOf k) msg bt)

||| Run an action in a crash boundary: `Right` its result, or `Left` what
||| happened if it crashed (see the warnings of this module: memory leaked,
||| locks held, effects left half done).  Boundaries nest: a crash ends the
||| innermost one of its thread.  A crash in another thread (one that the
||| action forked, say) is not caught by this boundary.
|||
||| The argument is lazy, so that the expression of the action (`handler
||| req`, which may crash before it gives an action) is evaluated inside the
||| boundary.
-- (inline, so that at the call sites the action is not made into a thunk
-- and a closure first, and IO is not reached through `HasIO`; the
-- expression of the action is evaluated in the closure that the boundary
-- runs, which takes the world, so inside the boundary)
%inline
export
catchCrash : HasIO io => Lazy (IO a) -> io (Either CrashInfo a)
catchCrash act = liftIO $ do
  r <- primIO (prim__crashCatch (\w => toPrim (Force act) w))
  0 <- primIO prim__crashCaught
    | _ => Left <$> caughtCrash
  pure (Right r)

||| The number of crashes that boundaries caught since the program started
||| (in every thread).
export
crashesCaught : HasIO io => io Int
crashesCaught = primIO prim__crashesCaught

||| Does this back end have crash boundaries?  Where it does not,
||| `catchCrash` runs its action without one.
export
crashBoundaries : Bool
crashBoundaries = prim__crashBoundaries /= 0
