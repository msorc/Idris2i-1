-- Strings that contain the NUL character.

import Data.Buffer
import Data.String

s : String
s = "ab\0cd\0"

kind : String -> String
kind "ab\0cd\0" = "with NULs"
kind "ab" = "prefix"
kind _ = "other"

partial
main : IO ()
main = do
  printLn (length s, stringByteLength s)
  printLn s
  printLn (unpack s)
  printLn (pack ['x', '\0', 'y'])
  printLn (s ++ "!", "\0" ++ s)
  printLn (strCons '\0' "z", strTail s, reverse s)
  printLn (substr 1 4 s, strIndex s 2, strIndex s 3)
  printLn (s == "ab", s == "ab\0cd\0", compare "a\0" "a", compare "a\0b" "a\0c")
  printLn (map kind [s, "ab", "ab\0"])
  printLn (fastConcat ["a\0", "\0b"], length (fastConcat ["a\0", "\0b"]))
  printLn (words "a\0 b", lines "x\0\ny")
  putStrLn s
  Just buf <- newBuffer 16
    | Nothing => putStrLn "no buffer"
  setString buf 0 s
  t' <- getString buf 0 6
  printLn (t' == s)
