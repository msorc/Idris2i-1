#!/bin/sh
. "$(dirname "$0")/../../lib.sh"

ref() {
  python3 -c '
import sys, re
ledger, errs = {}, []
for line in sys.stdin.read().splitlines():
    w = line.split()
    if len(w) != 3 or w[1] not in "+-" or not re.fullmatch(r"-?[0-9]+", w[2]):
        continue
    acc, k, amt = w[0], w[1], int(w[2])
    bal = ledger.get(acc, 0)
    if amt <= 0:
        errs.append("bad amount for " + acc)
    elif k == "-" and bal < amt:
        errs.append("insufficient funds in " + acc)
    else:
        ledger[acc] = bal + (amt if k == "+" else -amt)
for name, bal in sorted(ledger.items(), key=lambda kv: -kv[1]):
    print(name + ": " + str(bal))
for e in errs:
    print("error: " + e)
print("total: " + str(sum(ledger.values())))
'
}

rm -rf build
assert "idris2i-1 Bank.idr -o bank succeeds" "$IDRIS" --no-color Bank.idr -o bank
exe=./build/exec/bank
if [ ! -x "$exe" ]; then
  fail "output for the sample input matches the Haskell program" "no executable"
  fail "output for a second input matches" "no executable"
  fail "a 5000-line input is read to the end" "no executable"
else
  ref <"$TASK/files/transactions.txt" >"$GRADE_TMP/e1"
  "$exe" <"$TASK/files/transactions.txt" >"$GRADE_TMP/a1" 2>&1
  same_output "output for the sample input matches the Haskell program" "$GRADE_TMP/e1" "$GRADE_TMP/a1"

  printf 'zed + 7\namy + 9000\nzed - 8\n\namy - 1\nbob + five\nkim + 3 4\nkim + 42' >"$GRADE_TMP/in2"
  ref <"$GRADE_TMP/in2" >"$GRADE_TMP/e2"
  "$exe" <"$GRADE_TMP/in2" >"$GRADE_TMP/a2" 2>&1
  same_output "output for a second input matches" "$GRADE_TMP/e2" "$GRADE_TMP/a2"

  python3 -c '
for i in range(5000):
    print("acct%d + %d" % (i % 37, i + 1))
' >"$GRADE_TMP/in3"
  ref <"$GRADE_TMP/in3" >"$GRADE_TMP/e3"
  "$exe" <"$GRADE_TMP/in3" >"$GRADE_TMP/a3" 2>&1
  same_output "a 5000-line input is read to the end" "$GRADE_TMP/e3" "$GRADE_TMP/a3"
fi
if [ ! -x "$exe" ]; then
  fail_rest "the program does not build" "Bank.idr checks and has no holes" \
    "apply, run, parseTx and report exist" "no believe_me or idris_crash"
  exit 0
fi
no_holes "Bank.idr checks and has no holes" Bank.idr
missing=
for f in apply run parseTx report; do
  grep -q "^$f :" Bank.idr || missing="$missing $f"
done
if [ -z "$missing" ]; then
  pass "apply, run, parseTx and report exist" "all present"
else
  fail "apply, run, parseTx and report exist" "missing:$missing"
fi
forbid "no believe_me or idris_crash" 'believe_me|idris_crash' Bank.idr
