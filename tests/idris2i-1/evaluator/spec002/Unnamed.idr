-- %spec on a name that is not an argument (the argument has no name)
%spec order
mergeBy : (a -> a -> Ordering) -> List a -> List a -> List a
mergeBy order xs ys = xs ++ ys
