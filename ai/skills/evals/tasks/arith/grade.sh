#!/bin/sh
. "$(dirname "$0")/../../lib.sh"

A1="Arith.idr checks and no hole is left"
A2="the six facts and four functions have the given types and are total (Check.idr type-checks)"
A3="interleave, flatten, frame and thirds return the right values"
A4="%default total is kept; no believe_me, assert_total, assert_smaller, idris_crash, partial"

left=$(holes Arith.idr -p contrib)
if [ -n "$left" ]; then
  fail_rest "not done yet: $left" "$A1" "$A2" "$A3" "$A4"
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
if grep -q '^%default total' Arith.idr; then
  forbid "$A4" 'believe_me|assert_total|assert_smaller|idris_crash|^ *partial|^ *covering|postulate|%foreign' Arith.idr
else
  fail "$A4" "%default total was removed"
fi
