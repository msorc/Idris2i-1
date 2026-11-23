#!/bin/sh
. "$(dirname "$0")/../../lib.sh"

A2="same output as the original for limits 300 and 777"
A3="at least 50 times fewer instructions than the original for limit 1200"
A4="limit 20000 finishes within 30 seconds with the right output"
A5="pure Idris: no %foreign, no believe_me"

rm -rf build
assert "idris2 Report.idr -o report succeeds" "$IDRIS" --no-color Report.idr -o report
if [ ! -x build/exec/report ]; then
  fail_rest "no executable" "$A2" "$A3" "$A4" "$A5"
  exit 0
fi

# The original, built here, gives the reference output and instruction count.
mkdir -p "$GRADE_TMP/orig" && cp "$TASK/files/Report.idr" "$GRADE_TMP/orig/"
(cd "$GRADE_TMP/orig" && "$IDRIS" --no-color Report.idr -o report >/dev/null 2>&1)
orig=$GRADE_TMP/orig/build/exec/report

ok=0
for n in 300 777; do
  "$orig" $n >"$GRADE_TMP/e"; timeout 60 ./build/exec/report $n >"$GRADE_TMP/a" 2>&1
  cmp -s "$GRADE_TMP/e" "$GRADE_TMP/a" || ok=1
done
if [ $ok -eq 0 ]; then pass "$A2" "identical"; else fail "$A2" "$(diff "$GRADE_TMP/e" "$GRADE_TMP/a" | head -n 6)"; fi

count() { # program limit: user-mode instructions, or user milliseconds when perf is unavailable
  if perf stat -x, -e instructions:u -o "$GRADE_TMP/perf" timeout 300 "$1" "$2" >/dev/null 2>&1 &&
     grep -q instructions "$GRADE_TMP/perf"; then
    grep instructions "$GRADE_TMP/perf" | cut -d, -f1
  else
    /usr/bin/time -f '%U' -o "$GRADE_TMP/time" timeout 300 "$1" "$2" >/dev/null 2>&1
    awk '{ printf "%d\n", $1 * 1000 + 1 }' "$GRADE_TMP/time"
  fi
}
before=$(count "$orig" 1200)
after=$(count ./build/exec/report 1200)
ratio=$(awk -v b="$before" -v a="$after" 'BEGIN { printf "%d", (a > 0) ? b / a : 0 }')
if [ "$ratio" -ge 50 ]; then
  pass "$A3" "$ratio times fewer ($before -> $after)"
else
  fail "$A3" "only $ratio times fewer ($before -> $after)"
fi

timeout 30 ./build/exec/report 20000 >"$GRADE_TMP/a" 2>&1
same_output "$A4" "$TASK/expected-20000.txt" "$GRADE_TMP/a"
forbid "$A5" '%foreign|believe_me' Report.idr
