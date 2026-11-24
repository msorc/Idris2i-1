-- The copy of a %spec function whose static argument is given to a case block
-- with a wildcard alternative (`_` is a pattern variable with a machine name)
%spec order
mergeBy : (order : a -> a -> Ordering) -> List a -> List a -> List a
mergeBy order [] right = right
mergeBy order left [] = left
mergeBy order (x::xs) (y::ys) =
  case order x y of
       LT => x :: mergeBy order xs (y::ys)
       _  => y :: mergeBy order (x::xs) ys

main : IO ()
main = printLn (mergeBy compare [1, 3, 5] [2, 4, the Integer 6])
