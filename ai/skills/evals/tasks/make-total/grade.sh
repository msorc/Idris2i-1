#!/bin/sh
. "$(dirname "$0")/../../lib.sh"

rm -rf build
cp "$TASK/files/Check.idr" Check.idr
assert "Check.idr compiles unchanged against Util.idr" "$IDRIS" --no-color Check.idr -o check
if [ -x build/exec/check ]; then
  timeout 60 ./build/exec/check >"$GRADE_TMP/act" 2>&1
  same_output "the functions still compute the same results" "$TASK/files/expected.txt" "$GRADE_TMP/act"
else
  fail "the functions still compute the same results" "no executable"
fi
if grep -q '^%default total' Util.idr 2>/dev/null; then
  pass "Util.idr has %default total" "present"
else
  fail "Util.idr has %default total" "not found"
fi
left=$(holes Util.idr)
for f in toBinary chunksOf "gcd'" msort collatzSteps; do
  if [ -n "$left" ]; then
    fail "$f is total" "Util.idr does not check or has holes: $left"
  else
    is_total "$f is total" Util.idr "Util.$f"
  fi
done
if ! grep -q '^%default total' Util.idr 2>/dev/null || [ -n "$left" ]; then
  fail_rest "the module is not total yet" \
    "no assert_total, assert_smaller, believe_me, idris_crash, partial or covering"
  exit 0
fi
forbid "no assert_total, assert_smaller, believe_me, idris_crash, partial or covering" \
  'assert_total|assert_smaller|believe_me|idris_crash|^ *partial|^ *covering' Util.idr
