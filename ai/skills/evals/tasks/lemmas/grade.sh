#!/bin/sh
. "$(dirname "$0")/../../lib.sh"

A1="Lemmas.idr checks and no hole is left"
A2="the five statements are proved as stated (Check.idr type-checks against them)"
A3="all five lemmas are total"
A4="%default total is kept; no believe_me, assert_total, assert_smaller, idris_crash, partial"

left=$(holes Lemmas.idr)
if [ -n "$left" ]; then
  fail_rest "not proved yet: $left" "$A1" "$A2" "$A3" "$A4"
  exit 0
fi
pass "$A1" "No holes"
cp "$TASK/Check.idr" Check.idr
assert "$A2" "$IDRIS" --no-color --check Check.idr
bad=
for f in revAppend revInvolutive mapRev sumAppend sumRev; do
  "$IDRIS" --no-color Lemmas.idr --client ":total Lemmas.$f" 2>&1 | grep -q 'is total' || bad="$bad $f"
done
if [ -z "$bad" ]; then pass "$A3" "all total"; else fail "$A3" "not total:$bad"; fi
if grep -q '^%default total' Lemmas.idr; then
  forbid "$A4" 'believe_me|assert_total|assert_smaller|idris_crash|^ *partial|^ *covering|postulate' Lemmas.idr
else
  fail "$A4" "%default total was removed"
fi
