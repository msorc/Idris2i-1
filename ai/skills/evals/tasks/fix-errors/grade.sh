#!/bin/sh
. "$(dirname "$0")/../../lib.sh"

rm -rf build
assert "idris2 Report.idr -o report succeeds" "$IDRIS" --no-color Report.idr -o report
if [ -x build/exec/report ]; then
  ./build/exec/report >"$GRADE_TMP/act" 2>&1
  same_output "the program prints exactly expected.txt" "$TASK/files/expected.txt" "$GRADE_TMP/act"
else
  fail "the program prints exactly expected.txt" "no executable"
fi
if [ ! -x build/exec/report ]; then
  fail_rest "the program does not build" "Report.idr checks and has no holes" \
    "the functions of the original are kept under their names" \
    "no believe_me, assert_total or idris_crash"
  exit 0
fi
no_holes "Report.idr checks and has no holes" Report.idr
missing=
for f in average grade describe ranking histogram curve students; do
  grep -q "^$f :" Report.idr || missing="$missing $f"
done
if [ -z "$missing" ]; then
  pass "the functions of the original are kept under their names" "all seven present"
else
  fail "the functions of the original are kept under their names" "missing:$missing"
fi
forbid "no believe_me, assert_total or idris_crash" 'believe_me|assert_total|idris_crash' Report.idr
