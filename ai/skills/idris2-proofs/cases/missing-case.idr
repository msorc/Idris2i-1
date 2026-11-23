-- expect: E0601
-- covering is the default, so a missing clause is an error without any annotation.

headM : List a -> a
headM (x :: _) = x
