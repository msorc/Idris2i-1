#!/bin/sh
. "$(dirname "$0")/../../lib.sh"

A2="same output as the original for 1000 and 77777 rounds"
A3="2000000 rounds: right output, peak memory under 16 MB"
A4="memory does not grow with the rounds (peak for 400000 within 8 MB of the peak for 50000)"
A5="nothing is left allocated at exit (IDRIS2I_1_REFC_LEAKCHECK reports 0 leaked values)"
A6="pure Idris: no %foreign, no believe_me"

rm -rf build
assert "idris2i-1 Hub.idr -o hub succeeds" "$IDRIS" --no-color Hub.idr -o hub
if [ ! -x build/exec/hub ]; then
  fail_rest "no executable" "$A2" "$A3" "$A4" "$A5" "$A6"
  exit 0
fi

mkdir -p "$GRADE_TMP/orig" && cp "$TASK/files/Hub.idr" "$GRADE_TMP/orig/"
(cd "$GRADE_TMP/orig" && "$IDRIS" --no-color Hub.idr -o hub >/dev/null 2>&1)
orig=$GRADE_TMP/orig/build/exec/hub

ok=0
for n in 1000 77777; do
  "$orig" $n >"$GRADE_TMP/e"; timeout 60 ./build/exec/hub $n >"$GRADE_TMP/a" 2>&1
  cmp -s "$GRADE_TMP/e" "$GRADE_TMP/a" || ok=1
done
if [ $ok -eq 0 ]; then pass "$A2" "identical"; else fail "$A2" "$(diff "$GRADE_TMP/e" "$GRADE_TMP/a" | head -n 6)"; fi

peak() { # rounds: peak resident memory in KB; the output goes to $GRADE_TMP/a
  /usr/bin/time -f '%M' -o "$GRADE_TMP/mem" timeout 120 ./build/exec/hub "$1" >"$GRADE_TMP/a" 2>&1
  tail -n 1 "$GRADE_TMP/mem"
}
big=$(peak 2000000)
if cmp -s "$TASK/expected-2000000.txt" "$GRADE_TMP/a" && [ "$big" -lt 16000 ] 2>/dev/null; then
  pass "$A3" "peak $big KB"
else
  fail "$A3" "peak $big KB; $(diff "$TASK/expected-2000000.txt" "$GRADE_TMP/a" | head -n 4)"
fi
small=$(peak 50000); mid=$(peak 400000)
if [ $((mid - small)) -lt 8192 ] 2>/dev/null; then
  pass "$A4" "$small KB for 50000 rounds, $mid KB for 400000"
else
  fail "$A4" "$small KB for 50000 rounds, $mid KB for 400000"
fi
IDRIS2I_1_REFC_LEAKCHECK=1 timeout 60 ./build/exec/hub 5000 >/dev/null 2>"$GRADE_TMP/leak"
if grep -q 'leak check: 0 leaked values' "$GRADE_TMP/leak"; then
  pass "$A5" "$(head -n 1 "$GRADE_TMP/leak")"
else
  fail "$A5" "$(head -n 2 "$GRADE_TMP/leak")"
fi
forbid "$A6" '%foreign|believe_me' Hub.idr
