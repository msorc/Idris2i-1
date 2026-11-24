#!/bin/sh
. "$(dirname "$0")/../../lib.sh"

ALL="output for 0 0 3 4 3 10 is as specified
output for a single point is as specified
output for no points is as specified
90 points go through without a crash
polyline_free and free are called (no leak of library allocations)
geom.c and geom.h are unchanged"

rm -rf build
if [ ! -f build.sh ]; then
  fail "sh build.sh produces build/exec/geom" "no build.sh"
  echo "$ALL" | while read -r t; do fail "$t" "nothing was built"; done
  exit 0
fi
IDRIS2I_1=$IDRIS PATH="$(dirname "$IDRIS"):$PATH" sh build.sh >"$GRADE_TMP/build.log" 2>&1
if [ -x build/exec/geom ]; then
  pass "sh build.sh produces build/exec/geom" "$(tail -n 2 "$GRADE_TMP/build.log")"
else
  fail "sh build.sh produces build/exec/geom" "$(tail -n 6 "$GRADE_TMP/build.log")"
  echo "$ALL" | while read -r t; do fail "$t" "nothing was built"; done
  exit 0
fi

ref() {
  python3 -c '
import sys, math
v = [float(a) for a in sys.argv[1:]]
pts = list(zip(v[0::2], v[1::2]))
def show(d):
    return repr(float(d))
print("count", len(pts))
for i, (x, y) in enumerate(pts):
    print("point %d: %s %s" % (i, show(x), show(y)))
print("last: %s %s" % (show(pts[-1][0]), show(pts[-1][1])) if pts else "last: none")
print("get 99: none")
length = sum(math.hypot(b[0] - a[0], b[1] - a[1]) for a, b in zip(pts, pts[1:]))
print("length", show(length))
print("polyline(%d points, length %.2f)" % (len(pts), length))
' "$@"
}

try() { # assertion, args...
  text=$1; shift
  ref "$@" >"$GRADE_TMP/exp"
  timeout 20 ./build/exec/geom "$@" >"$GRADE_TMP/act" 2>&1
  same_output "$text" "$GRADE_TMP/exp" "$GRADE_TMP/act"
}
try "output for 0 0 3 4 3 10 is as specified" 0 0 3 4 3 10
try "output for a single point is as specified" 1.5 -2
try "output for no points is as specified"
# 90 points (fewer than 99, so "get 99" is still none) on a 3-4-5 staircase:
# every length is exact in floating point.
args=$(python3 -c 'print(" ".join("%d %d" % (3 * i, 4 * i) for i in range(90)))')
# shellcheck disable=SC2086
try "90 points go through without a crash" $args

src=$(cat ./*.idr src/*.idr 2>/dev/null)
if printf '%s' "$src" | grep -q 'polyline_free' &&
   printf '%s' "$src" | grep -E -q '"C:free[,"]|prim__free|free\b'; then
  pass "polyline_free and free are called (no leak of library allocations)" "both are bound"
else
  fail "polyline_free and free are called (no leak of library allocations)" "polyline_free or free is not bound"
fi
if cmp -s geom.c "$TASK/files/geom.c" && cmp -s geom.h "$TASK/files/geom.h"; then
  pass "geom.c and geom.h are unchanged" "identical"
else
  fail "geom.c and geom.h are unchanged" "the library was modified"
fi
