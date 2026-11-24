import Data.ByteString

f : ByteString -> String
f p = case p of
  "/a" => "a"
  _ => "other"
