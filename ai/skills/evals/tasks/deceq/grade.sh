#!/bin/sh
. "$(dirname "$0")/../../lib.sh"

A1="Syntax.idr checks and has no holes"
A2="DecEq exists for Ty, Op, Term n, Rose and Pos, and each is total (Check.idr type-checks)"
A3="decEq answers correctly on 814 pairs of values"
A4="%default total is kept; no believe_me, assert_total, assert_smaller, idris_crash, partial, covering"
A5="the five data declarations are unchanged"

left=$(holes Syntax.idr -p contrib)
if [ -n "$left" ]; then
  fail_rest "does not check: $left" "$A1" "$A2" "$A3" "$A4" "$A5"
  exit 0
fi
pass "$A1" "No holes"
cp "$TASK/Check.idr" Check.idr
rm -rf build/exec
assert "$A2" "$IDRIS" --no-color -p contrib Check.idr -o check
if [ -x build/exec/check ]; then
  timeout 60 ./build/exec/check >"$GRADE_TMP/a" 2>&1
  same_output "$A3" "$TASK/expected.txt" "$GRADE_TMP/a"
else
  fail "$A3" "the check program was not built"
fi
if grep -q '^%default total' Syntax.idr; then
  forbid "$A4" 'believe_me|assert_total|assert_smaller|idris_crash|^ *partial|^ *covering|postulate|%foreign' Syntax.idr
else
  fail "$A4" "%default total was removed"
fi
# the declarations, without comments and blank lines, must still be in the file in order
decls() { sed -n '/^data Ty/,/^-- TODO/p' "$1" | grep -v -E '^ *(\|\|\||--)|^ *$|^public export$'; }
decls "$TASK/files/Syntax.idr" >"$GRADE_TMP/want"
missing=$(grep -v -x -F -f Syntax.idr "$GRADE_TMP/want" | head -n 3)
if [ -z "$missing" ]; then pass "$A5" "all declaration lines present"; else fail "$A5" "missing: $missing"; fi
