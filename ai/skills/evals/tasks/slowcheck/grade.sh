#!/bin/sh
. "$(dirname "$0")/../../lib.sh"

A2="the program prints exactly expected.txt"
A3="checking takes at most a fifth of the processor time of the original"
A4="the data is still in the file (all 70 prices)"

rm -rf build
assert "idris2 Prices.idr -o prices succeeds" "$IDRIS" --no-color Prices.idr -o prices
if [ ! -x build/exec/prices ]; then
  fail_rest "no executable" "$A2" "$A3" "$A4"
  exit 0
fi
./build/exec/prices >"$GRADE_TMP/act" 2>&1
same_output "$A2" "$TASK/expected.txt" "$GRADE_TMP/act"

usertime() { # file: user seconds of a check from scratch
  /usr/bin/time -f '%U' -o "$GRADE_TMP/time" "$IDRIS" --check --no-color \
    --build-dir "$GRADE_TMP/b$$" "$1" >/dev/null 2>&1
  rm -rf "$GRADE_TMP/b$$"
  cat "$GRADE_TMP/time"
}
mkdir -p "$GRADE_TMP/orig" && cp "$TASK/files/Prices.idr" "$GRADE_TMP/orig/"
before=$(cd "$GRADE_TMP/orig" && usertime Prices.idr)
after=$(usertime Prices.idr)
if awk -v b="$before" -v a="$after" 'BEGIN { exit !(a * 5 <= b) }'; then
  pass "$A3" "$before s -> $after s"
else
  fail "$A3" "$before s -> $after s"
fi

missing=0
for price in $(grep -o '(+ [0-9]* \* [0-9]*)' "$TASK/files/Prices.idr" | sed 's/(+ \([0-9]*\) .*/\1/'); do
  grep -q "\b$price\b" Prices.idr || missing=$((missing + 1))
done
if [ $missing -eq 0 ]; then pass "$A4" "all present"; else fail "$A4" "$missing of 70 prices are gone"; fi
