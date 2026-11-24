||| Accumulating timers and counters for profiling the compiler itself, enabled
||| by `--timing-summary`.
|||
||| A timer measures the processor time of the process (in nanoseconds) taken
||| by the actions run under a key. Timers nest: the time of a timer counts in
||| the inclusive time of every timer that runs around it, and in the self
||| time of the innermost one only, so the self times of all the keys add up
||| to the time spent under some timer. A timer that is entered again while
||| it runs (by recursion, say) is not entered a second time.
|||
||| The profiler is kept in the context (`Context.profiler`, Nothing when
||| profiling is off), as a set of mutable references: the state of the
||| context is saved and restored when the elaborator backtracks, but what was
||| measured must not be lost then.
module Core.Profile

import Data.IORef
import Data.List
import Data.Maybe
import Data.String

import Libraries.Data.StringMap

%default covering

%foreign "C:idris2i_1_processCPUTimeNs, libidris2i_1_support, idris_system.h"
prim__processCPUTimeNs : PrimIO Int

%foreign "C:idris2i_1_peakRSSKiB, libidris2i_1_support, idris_system.h"
prim__peakRSSKiB : PrimIO Int

||| The processor time used by the process so far, in nanoseconds
export
processCPUTimeNs : IO Int
processCPUTimeNs = primIO prim__processCPUTimeNs

||| The peak resident set size of the process so far, in KiB (0 when it is
||| not known)
export
peakRSSKiB : IO Int
peakRSSKiB = primIO prim__peakRSSKiB

public export
record Timer where
  constructor MkTimer
  tcalls : Int -- times entered (not counting re-entries)
  tincl : Int  -- inclusive time, ns
  tself : Int  -- exclusive time, ns

record Frame where
  constructor MkFrame
  fkey : String
  fstart : Int
  finner : Int -- the time spent in the timers run inside, ns

-- A declaration and what it spent its time on (self times by key, and the
-- counters it moved)
record DeclCost where
  constructor MkDeclCost
  cost : Int
  dlabel : String
  dselfs : List (String, Int)
  dcounts : List (String, Int)

export
record Profiler where
  constructor MkProfiler
  ptimers : IORef (StringMap Timer)
  pcounters : IORef (StringMap Int)
  pstack : IORef (List Frame)
  -- the most expensive declarations of the module being processed
  ptopDecls : IORef (List DeclCost)

export
newProfiler : IO Profiler
newProfiler
    = pure $ MkProfiler !(newIORef empty) !(newIORef empty)
                        !(newIORef []) !(newIORef [])

||| Start timing `key`. Returns False, and does nothing, when the key is
||| already being timed.
export
profEnter : Profiler -> String -> IO Bool
profEnter p fkey
    = do st <- readIORef p.pstack
         if any (\f => f.fkey == fkey) st
            then pure False
            else do now <- processCPUTimeNs
                    writeIORef p.pstack (MkFrame fkey now 0 :: st)
                    pure True

||| Stop the innermost timer
export
profLeave : Profiler -> IO ()
profLeave p
    = do now <- processCPUTimeNs
         (MkFrame fkey fstart finner :: st) <- readIORef p.pstack
           | [] => pure ()
         let el = now - fstart
         writeIORef p.pstack $ case st of
              (MkFrame k s i :: rest) => MkFrame k s (i + el) :: rest
              [] => []
         modifyIORef p.ptimers $ \ ts =>
              let MkTimer c i s = fromMaybe (MkTimer 0 0 0) (lookup fkey ts) in
                  insert fkey (MkTimer (c + 1) (i + el) (s + el - finner)) ts

||| Add to a counter
export
profCount : Profiler -> String -> Int -> IO ()
profCount p fkey n
    = modifyIORef p.pcounters $ \ cs =>
          insert fkey (n + fromMaybe 0 (lookup fkey cs)) cs

||| Whether a timer runs (anywhere in the stack)
export
profTiming : Profiler -> String -> IO Bool
profTiming p fkey = any (\f => f.fkey == fkey) <$> readIORef p.pstack

||| The key of the innermost running timer ("none" when none runs)
export
profInnermost : Profiler -> IO String
profInnermost p
    = do (f :: _) <- readIORef p.pstack
           | [] => pure "none"
         pure f.fkey

||| Run an action that only serves the profiler: its time is taken out of
||| every running timer
export
profUntimed : Profiler -> IO a -> IO a
profUntimed p act
    = do t0 <- processCPUTimeNs
         res <- act
         t1 <- processCPUTimeNs
         let d = t1 - t0
         modifyIORef p.pstack (map (\ (MkFrame k s i) => MkFrame k (s + d) i))
         pure res

-- What the timers and counters were at some point
export
record Snapshot where
  constructor MkSnapshot
  stimers : StringMap Timer
  scounters : StringMap Int

export
profSnapshot : Profiler -> IO Snapshot
profSnapshot p = pure $ MkSnapshot !(readIORef p.ptimers) !(readIORef p.pcounters)

-- self times and counters that changed since a snapshot, the largest first
since : Snapshot -> Snapshot -> (List (String, Int), List (String, Int))
since old new
    = (sortBy (\ x, y => compare (snd y) (snd x)) $
         filter (\ x => snd x > 0) $
           map (\ (k, t) => (k, t.tself - maybe 0 tself (lookup k old.stimers)))
               (toList new.stimers),
       filter (\ x => snd x /= 0) $
           map (\ (k, c) => (k, c - fromMaybe 0 (lookup k old.scounters)))
               (toList new.scounters))

us : Int -> String
us ns = show (ns `div` 1000)

showSelfs : List (String, Int) -> String
showSelfs = unwords . map (\ (k, t) => k ++ "=" ++ us t)

showCounts : List (String, Int) -> String
showCounts = unwords . map (\ (k, c) => "#" ++ k ++ "=" ++ show c)

||| How many of the most expensive declarations of a module are reported
export
topDeclCount : Nat
topDeclCount = 10

-- How a timer changed since a snapshot
timerSince : String -> Snapshot -> Snapshot -> Timer
timerSince fkey old new
    = let MkTimer c i s = get new
          MkTimer c' i' s' = get old in
          MkTimer (c - c') (i - i') (s - s')
  where
    get : Snapshot -> Timer
    get sn = fromMaybe (MkTimer 0 0 0) (lookup fkey sn.stimers)

||| Record the declaration just timed under "decl", with what changed since
||| the snapshot taken before it, if it is among the most expensive ones of
||| the module
export
profNoteDecl : Profiler -> Lazy String -> Snapshot -> IO ()
profNoteDecl p dlabel before
    = do ds <- readIORef p.ptopDecls
         now <- profSnapshot p
         let cost = tincl (timerSince "decl" before now)
         let small = length ds >= topDeclCount
                     && all (\ d => d.cost >= cost) ds
         if small then pure () else
           do let (ss, cs) = since before now
              let d = MkDeclCost cost dlabel ss cs
              writeIORef p.ptopDecls
                 (take topDeclCount $
                    sortBy (\ x, y => compare y.cost x.cost) (d :: ds))

||| The report on the module just timed under "module", if it was built (it
||| was parsed): one line for the module (its time, then the self times by
||| key and the counters, since the snapshot), and one for each of its most
||| expensive declarations
export
profModuleLines : Profiler -> (file : String) -> Snapshot -> IO (List String)
profModuleLines p file before
    = do now <- profSnapshot p
         let cost = tincl (timerSince "module" before now)
         let (ss, cs) = since before now
         ds <- readIORef p.ptopDecls
         writeIORef p.ptopDecls []
         if tcalls (timerSince "parse" before now) == 0 then pure [] else
          pure $ unwords ["PROFILE module", file, "cpu=" ++ us cost,
                         showSelfs ss, showCounts cs]
                :: map (\ d => unwords ["PROFILE decl", file, show d.dlabel,
                                        "cpu=" ++ us d.cost,
                                        showSelfs d.dselfs, showCounts d.dcounts])
                       ds

||| The summary of the whole process
export
profSummaryLines : Profiler -> IO (List String)
profSummaryLines p
    = do ts <- readIORef p.ptimers
         cs <- readIORef p.pcounters
         cpu <- processCPUTimeNs
         rss <- peakRSSKiB
         let timed = sum (map (\ t => t.tself) (values ts))
         pure $
           [ "PROFILE note times in microseconds of processor time; incl counts the timers run inside, self does not; the self times add up to the timed total"
           , unwords [ "PROFILE process", "cpu=" ++ us cpu, "timed=" ++ us timed
                     , "untimed=" ++ us (cpu - timed), "peak_rss_kib=" ++ show rss ]
           ] ++
           map (\ (k, t) => unwords [ "PROFILE timer", k, "calls=" ++ show t.tcalls
                                    , "incl=" ++ us t.tincl, "self=" ++ us t.tself ])
               (toList ts) ++
           map (\ (k, c) => unwords [ "PROFILE counter", k, show c ]) (toList cs)
