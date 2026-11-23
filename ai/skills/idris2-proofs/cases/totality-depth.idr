-- expect: E0704
-- Accepted with the default depth (5); rejected when the checker looks only 2 deep.

%totality_depth 2

total
h : Maybe (Maybe (Maybe (List Nat))) -> Nat
h (Just (Just (Just (x :: y :: xs)))) = h (Just (Just (Just xs)))
h _ = 0
