-- expect: E0101
record Reply where
  constructor MkReply
  sum : Integer

reply : List Integer -> Reply
reply xs = MkReply (sum xs)
