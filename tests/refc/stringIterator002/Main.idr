module Main

import Data.List
import Data.String
import Data.String.Iterator

-- The characters of a string, through an iterator
chars : String -> List Char
chars s = toList (Data.String.Iterator.unpack s)

codes : String -> List Int
codes s = map ord (chars s)

-- What is left of a string after n characters, through withIteratorString
dropIt : Nat -> String -> String
dropIt n str = withString str (go n)
  where
    go : Nat -> (1 it : StringIterator str) -> String
    go (S k) it = case uncons str it of
      EOF => ""
      Character _ it' => go k it'
    go Z it = withIteratorString str it id

-- The rest of the string after each step of an iteration
steps : String -> List String
steps str = map (\n => dropIt n str) [0 .. length str + 1]

-- An iterator after EOF stays at EOF
twiceEOF : String -> Bool
twiceEOF str = withString str go
  where
    go : (1 it : StringIterator str) -> Bool
    go it = case uncons str it of
      EOF => True
      Character _ it' => go (assert_smaller it it')

samples : List String
samples = [ "", "a", "ab", "aλ→∀\x1F600z", "λ", "\x1F600", "\0a\0", "ü" ++ "ber"
          , "\x7F\x80\xFF\x100\x7FF\x800\xFFFF\x10000\x10FFFF" ]

partial
main : IO ()
main = do
  for_ samples $ \s => do
    printLn (codes s)
    printLn (Data.String.Iterator.foldl (\n, _ => n + 1) (the Nat 0) s == length s)
    printLn (map (\n => dropIt n s) (the (List Nat) [0, 1, 2, 3, 10]))
    printLn (steps s)
    printLn (twiceEOF s)
  -- A string read at run time (not a constant)
  line <- getLine
  printLn (codes line, length line)
  printLn (steps line)
  printLn (dropIt 3 line, dropIt 100 line)
  -- Iterators over substrings and concatenations
  let t = substr 1 4 line ++ "∀x"
  printLn (codes t, dropIt 2 t)
  printLn (sum (map (\i => length (dropIt i (line ++ line))) [0 .. 30]))
