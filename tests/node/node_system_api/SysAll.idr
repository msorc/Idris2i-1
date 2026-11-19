module SysAll

-- Each function of System, System.Directory and System.File (and a few
-- neighbours) on Node: the output is that of the Chez backend.

import Data.Buffer
import Data.List
import Data.String
import System
import System.Clock
import System.Directory
import System.Errno
import System.File
import System.Info
import System.Term

say : String -> String -> IO ()
say tag s = putStrLn (tag ++ ": " ++ s)

showE : Show a => Either FileError a -> String
showE (Left e) = "Left " ++ show e
showE (Right x) = "Right " ++ show x

part0 : IO ()
part0 = do
  Just start <- currentDir | Nothing => say "currentDir" "Nothing"
  say "currentDir" (show (isSuffixOf "/node_system_api" start))
  pure ()

part1 : IO ()
part1 = do
  -- Directories
  say "createDir" (showE !(createDir "wd"))
  say "createDir again" (showE !(createDir "wd"))
  say "changeDir" (show !(changeDir "wd"))
  say "changeDir missing" (show !(changeDir "nonexistent"))
  Just d <- currentDir | Nothing => say "currentDir" "Nothing"
  say "currentDir after" (show (isSuffixOf "/node_system_api/wd" d))
  say "writeFile" (showE !(writeFile "a.txt" "one\ntwo\n\nlast"))
  say "appendFile" (showE !(appendFile "a.txt" "!"))
  say "readFile" (showE !(readFile "a.txt"))
  say "readFile missing" (showE !(readFile "missing.txt"))
  say "readFilePage" (showE !(readFilePage 1 (limit 2) "a.txt"))
  say "exists" (show (!(exists "a.txt"), !(exists "missing.txt")))
  say "firstExists" (show !(firstExists ["missing.txt", "a.txt"]))
  _ <- createDir "sub"
  say "listDir" (show (map sort !(listDir ".")))
  say "listDir missing" (showE !(listDir "nope"))
  Right dir <- openDir "sub" | Left e => say "openDir" (show e)
  say "nextDirEntry" (showE !(nextDirEntry dir))
  closeDir dir
  say "openDir missing" (either show (const "Right") !(openDir "nope"))
  removeDir "sub"
  say "removeDir" (show !(exists "sub"))
  pure ()

part2 : IO ()
part2 = do
  -- Files
  Right f <- openFile "a.txt" Read | Left e => say "openFile" (show e)
  say "fileSize" (showE !(fileSize f))
  say "isTTY" (show !(isTTY f))
  say "fPoll" (show !(fPoll f))
  say "fGetLine" (showE !(fGetLine f))
  say "fGetChar" (showE !(fGetChar f))
  say "fGetChars" (showE !(fGetChars f 2))
  say "fSeekLine" (showE !(fSeekLine f))
  say "fEOF" (show !(fEOF f))
  say "fGetLine" (showE !(fGetLine f))
  say "fGetLine last" (showE !(fGetLine f))
  say "fEOF" (show !(fEOF f))
  say "fGetLine at end" (showE !(fGetLine f))
  Right mt <- fileModifiedTime f | Left e => say "fileModifiedTime" (show e)
  say "fileModifiedTime" (show (mt > 0))
  Right ft <- fileTime f | Left e => say "fileTime" (show e)
  say "fileTime" (show (ft.mtime == ft.mtime))
  closeFile f
  Right f <- openFile "a.txt" Read | Left e => say "openFile" (show e)
  say "fRead" (showE !(fRead f))
  closeFile f
  say "openFile missing" (either show (const "Right") !(openFile "missing.txt" Read))
  Right f <- openFile "b.txt" WriteTruncate | Left e => say "openFile" (show e)
  say "fPutStr" (showE !(fPutStr f "x"))
  say "fPutStrLn" (showE !(fPutStrLn f "y"))
  fflush f
  closeFile f
  say "readFile b" (showE !(readFile "b.txt"))
  say "copyFile" (either (show . fst) (const "Right") !(copyFile "b.txt" "c.txt"))
  say "readFile c" (showE !(readFile "c.txt"))
  say "chmodRaw" (showE !(chmodRaw "c.txt" 0o600))
  say "chmodRaw missing" (showE !(chmodRaw "missing.txt" 0o600))
  Right buf <- createBufferFromFile "c.txt" | Left e => say "createBufferFromFile" (show e)
  say "buffer size" (show !(rawSize buf))
  say "writeBufferToFile" (either (show . fst) (const "Right") !(writeBufferToFile "d.txt" buf 3))
  say "readFile d" (showE !(readFile "d.txt"))
  say "removeFile" (showE !(removeFile "d.txt"))
  say "removeFile missing" (showE !(removeFile "d.txt"))
  pure ()

part3 : IO ()
part3 = do
  -- Processes
  say "system" (show !(System.system "exit 3"))
  say "run" (show !(System.run "echo hi"))
  Right p <- System.File.Process.popen "echo popen" Read | Left e => say "popen" (show e)
  say "popen fGetLine" (showE !(fGetLine p))
  say "pclose" (show !(pclose p))
  pure ()

part4 : IO ()
part4 = do
  -- Environment
  say "setEnv" (show !(setEnv "SYSALL_X" "1" True))
  say "getEnv" (show !(getEnv "SYSALL_X"))
  say "getEnvironment" (show (lookup "SYSALL_X" !getEnvironment))
  say "unsetEnv" (show !(unsetEnv "SYSALL_X"))
  say "getEnv after" (show !(getEnv "SYSALL_X"))
  say "getArgs" (show (length !getArgs))
  say "getPID" (show (!getPID > 0))
  say "time" (show (!time > 1000000000))
  t0 <- clockTime Monotonic
  usleep 20000
  sleep 1
  t1 <- clockTime Monotonic
  say "sleep" (show (toNano (timeDifference t1 t0) >= 1000000000))
  say "os" os
  say "isWindows" (show isWindows)
  say "getNProcessors" (show (map (> 0) !getNProcessors))
  say "termCols" (show (!getTermCols + 1 >= 1))
  say "getErrno" (show (!getErrno >= 0))
  say "enableRawMode" (either (const "Left") (const "Right") !enableRawMode)
  resetRawMode
  pure ()

part5 : IO ()
part5 = do
  -- cleanup
  _ <- removeFile "a.txt"; _ <- removeFile "b.txt"; _ <- removeFile "c.txt"
  _ <- changeDir ".."
  removeDir "wd"
  say "end" (show !(exists "wd"))

  pure ()

main : IO ()
main = do
  part0
  part1
  part2
  part3
  part4
  part5
