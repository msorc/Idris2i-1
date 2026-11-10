module Main

import Data.String

-- Strings hold Unicode code points, like with the other backends
s : String
s = "aλ→∀\x1F600z"

partial
main : IO ()
main = do
  printLn (length s)
  printLn (map ord (unpack s))
  putStrLn (pack (reverse (unpack s)))
  putStrLn (reverse s)
  printLn (strIndex s 2)
  putStrLn (substr 1 3 s)
  putStrLn (substr 4 10 s)
  putStrLn (strCons 'ü' "ber")
  printLn (strUncons s)
  putStrLn (singleton '∀' ++ cast 'λ')
  printLn (map (\x => ord (cast {to = Char} x)) [the Int 955, 0xD800, 0x10FFFF, 0x110000, -1])
  printLn (foldl (\acc, c => acc * 33 + ord c) 5381 (unpack s))
  putChar 'λ'
  putChar '\n'
  printLn (String.length "\x7F\x80\xFF")
  putStrLn (show "\x7F\x80\xFF")
