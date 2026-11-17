-- Reading a directory as a file fails (EISDIR): the functions that read until
-- the end of the file, which they never reach, return an error instead of
-- running forever.
import Control.App
import Control.App.FileIO
import System.File
import System.REPL

result : Either FileError a -> String
result (Left _) = "an error"
result (Right _) = "no error"

appRead : App Init String
appRead = handle (readFile "adir")
                 (\_ => pure "no error")
                 (\_ : IOError => pure "an error")

main : IO ()
main = do
    putStrLn ("readFile: " ++ result !(readFile "adir"))
    putStrLn ("readFilePage: " ++ result !(readFilePage 0 (limit 5) "adir"))
    Right f <- openFile "adir" Read
        | Left err => putStrLn "openFile failed"
    putStrLn ("fGetLine: " ++ result !(fGetLine f))
    putStrLn ("fRead: " ++ result !(fRead f))
    putStrLn ("fGetChars: " ++ result !(fGetChars f 10))
    putStrLn ("fGetChar: " ++ result !(fGetChar f))
    putStrLn ("fSeekLine: " ++ result !(fSeekLine f))
    closeFile f
    putStrLn ("Control.App readFile: " ++ !(run appRead))
    -- stdin is the directory (see run)
    repl "> " (\s => "[" ++ s ++ "]\n")
    putStrLn ""
    putStrLn "done"
