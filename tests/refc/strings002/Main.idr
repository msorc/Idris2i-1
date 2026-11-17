module Main

import Data.Buffer
import Data.List
import Data.String

-- length, strIndex and substr on strings made in all sorts of ways: the RefC
-- runtime keeps the number of characters of a string, and indexes ASCII
-- strings directly; the results must not depend on that.

-- All the characters of a string, by index
byIndex : String -> List Int
byIndex s = map (\i => ord (assert_total (strIndex s (cast i)))) (take (length s) [0 ..])

-- Some substrings, at the start, in the middle and past the end
subs : String -> List String
subs s = [substr 0 1 s, substr 1 3 s, substr 2 100 s, substr 33 5 s, substr 40 2 s, substr 100 1 s, substr 0 1000 s]

report : String -> String -> IO ()
report name s = do
  putStrLn "\{name}: \{show (length s)} \{show (length s)}"
  printLn (byIndex s)
  -- (indexes in range: out of range is undefined with Chez)
  printLn (map (\i => ord (assert_total (strIndex s i)))
               (filter (\i => i >= 0 && i < cast (length s)) [-1, 0, 1, 31, 32, 33, 40, 1000]))
  printLn (subs s)
  printLn (map length (subs s))
  printLn (length (reverse s), reverse s == pack (reverse (unpack s)))

-- A string of the bytes bs (which need not be UTF-8)
bytes : List Bits8 -> IO String
bytes bs = do
  Just buf <- newBuffer (cast (length bs)) | Nothing => pure ""
  for_ (zip [0 .. length bs] bs) $ \(i, b) => setBits8 buf (cast i) b
  getString buf 0 (cast (length bs))

long : String
long = "The quick brown fox jumps over the lazy dog, again and again."

partial
main : IO ()
main = do
  report "empty" ""
  report "ascii constant" long
  report "unicode constant" "aλ→∀\x1F600z and some more characters after them: ü, é, ∀"
  report "append" (long ++ "λ" ++ long)
  report "append ascii" (long ++ long)
  report "cons" (strCons 'λ' long)
  report "cons ascii" (strCons 'x' long)
  report "substr" (substr 3 40 (long ++ "λ→" ++ long))
  report "pack" (pack (unpack long ++ ['λ', 'x']))
  report "concat" (fastConcat [long, "→", "", long])
  report "show" (show (the Integer 12345678901234567890123456789012345678901234567890))
  report "show double" (show 1.5e300 ++ show (-0.1))
  report "cast char" (cast 'λ' ++ cast 'a')
  report "singleton" (singleton '\x1F600')
  report "reverse" (reverse (long ++ "λ"))
  report "tail" (strTail ("λ" ++ long))
  line <- getLine
  report "getLine" line
  report "getLine twice" (line ++ line)
  report "getLine substr" (substr 2 50 (line ++ long))
  -- Not UTF-8: each invalid byte is a character (U+FFFD).  (The Scheme
  -- backends decode the bytes when they make the string, so from here on
  -- their results differ; the RefC results are those of RefC before it kept
  -- the lengths of strings.)
  e2 <- bytes [0xE2, 0x82]
  ac <- bytes [0xAC]
  bad <- bytes [0x41, 0xC0, 0x80, 0xED, 0xA0, 0x80, 0xF5, 0x42, 0xE2, 0x82]
  report "invalid" bad
  report "invalid prefix" (substr 1 4 bad)
  -- Two invalid strings that make a valid one: the lengths of the parts are
  -- known before the concatenation
  printLn (length e2, length ac)
  report "joined" (e2 ++ ac)
  report "joined concat" (fastConcat [e2, ac, e2])
  report "joined cons" (strCons 'x' ac)
  r <- bytes [0xAC, 0x82, 0xE2]
  printLn (length r)
  report "reversed" (reverse r)
