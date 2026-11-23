#!/bin/sh
. "$(dirname "$0")/../../lib.sh"

rm -rf build
cp "$TASK/files/Check.idr" Check.idr
assert "Check.idr compiles unchanged against Matrix.idr" "$IDRIS" --no-color Check.idr -o check
if [ -x build/exec/check ]; then
  ./build/exec/check >"$GRADE_TMP/act" 2>&1
  same_output "the results are correct" "$TASK/expected.txt" "$GRADE_TMP/act"
else
  fail "the results are correct" "no executable"
fi
if [ ! -x build/exec/check ] || [ -n "$(holes Matrix.idr)" ]; then
  fail_rest "Check.idr does not build, or Matrix.idr has holes" "Matrix.idr has %default total" \
    "transposeM is total" "mulM is total" "identityM is total" \
    "no assert_total, assert_smaller, believe_me, partial or covering" \
    "transpose from the library is not used"
  exit 0
fi
if grep -q '^%default total' Matrix.idr 2>/dev/null; then
  pass "Matrix.idr has %default total" "present"
else
  fail "Matrix.idr has %default total" "not found"
fi
for f in transposeM mulM identityM; do
  is_total "$f is total" Matrix.idr "$f"
done
forbid "no assert_total, assert_smaller, believe_me, partial or covering" \
  'assert_total|assert_smaller|believe_me|idris_crash|^ *partial|^ *covering' Matrix.idr
forbid "transpose from the library is not used" '(^|[^A-Za-z_])transpose([^A-Za-z_M]|$)' Matrix.idr
