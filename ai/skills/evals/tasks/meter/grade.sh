#!/bin/sh
. "$(dirname "$0")/../../lib.sh"

A2="same output as the original for 300 and 7777 readings"
A3="at least 8 times fewer instructions than the original for 200000 readings"
A4="2000000 readings finish within 30 seconds with the right output"
A5="pure Idris: no %foreign, no believe_me, no %cg directive"

rm -rf build
assert "idris2 Meter.idr -o meter succeeds" "$IDRIS" --no-color Meter.idr -o meter
if [ ! -x build/exec/meter ]; then
  fail_rest "no executable" "$A2" "$A3" "$A4" "$A5"
  exit 0
fi

mkdir -p "$GRADE_TMP/orig" && cp "$TASK/files/Meter.idr" "$GRADE_TMP/orig/"
(cd "$GRADE_TMP/orig" && "$IDRIS" --no-color Meter.idr -o meter >/dev/null 2>&1)
orig=$GRADE_TMP/orig/build/exec/meter

ok=0
for n in 300 7777; do
  "$orig" $n >"$GRADE_TMP/e"; timeout 60 ./build/exec/meter $n >"$GRADE_TMP/a" 2>&1
  cmp -s "$GRADE_TMP/e" "$GRADE_TMP/a" || ok=1
done
if [ $ok -eq 0 ]; then pass "$A2" "identical"; else fail "$A2" "$(diff "$GRADE_TMP/e" "$GRADE_TMP/a" | head -n 6)"; fi

count() { # program readings: user-mode instructions, or user milliseconds when perf is unavailable
  if perf stat -x, -e instructions:u -o "$GRADE_TMP/perf" timeout 300 "$1" "$2" >/dev/null 2>&1 &&
     grep -q instructions "$GRADE_TMP/perf"; then
    grep instructions "$GRADE_TMP/perf" | cut -d, -f1
  else
    /usr/bin/time -f '%U' -o "$GRADE_TMP/time" timeout 300 "$1" "$2" >/dev/null 2>&1
    awk '{ printf "%d\n", $1 * 1000 + 1 }' "$GRADE_TMP/time"
  fi
}
before=$(count "$orig" 200000)
after=$(count ./build/exec/meter 200000)
ratio=$(awk -v b="$before" -v a="$after" 'BEGIN { printf "%.1f", (a > 0) ? b / a : 0 }')
if awk -v r="$ratio" 'BEGIN { exit !(r >= 8) }'; then
  pass "$A3" "$ratio times fewer ($before -> $after)"
else
  fail "$A3" "only $ratio times fewer ($before -> $after)"
fi

timeout 30 ./build/exec/meter 2000000 >"$GRADE_TMP/a" 2>&1
same_output "$A4" "$TASK/expected-2000000.txt" "$GRADE_TMP/a"
forbid "$A5" '%foreign|believe_me|%cg' Meter.idr
