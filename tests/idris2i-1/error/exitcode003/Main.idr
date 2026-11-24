import Data.ByteString as BS

g : String -> ByteString
g s = fromMaybe BS.empty (Just (fromString s))

main : IO ()
main = printLn (g "0a")
