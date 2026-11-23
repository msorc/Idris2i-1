#!/bin/sh
. "$(dirname "$0")/../../lib.sh"

ALL="output for 'hello world' matches zlib
output for a long repetitive string matches zlib
output for a non-ASCII string matches zlib
the program calls zlib through %foreign"

rm -rf build
if [ ! -f build.sh ]; then
  fail "sh build.sh produces build/exec/zcheck" "no build.sh"
  echo "$ALL" | while read -r t; do fail "$t" "nothing was built"; done
  exit 0
fi
IDRIS2=$IDRIS PATH="$(dirname "$IDRIS"):$PATH" sh build.sh >"$GRADE_TMP/build.log" 2>&1
if [ -x build/exec/zcheck ]; then
  pass "sh build.sh produces build/exec/zcheck" "$(tail -n 2 "$GRADE_TMP/build.log")"
else
  fail "sh build.sh produces build/exec/zcheck" "$(tail -n 6 "$GRADE_TMP/build.log")"
  echo "$ALL" | while read -r t; do fail "$t" "nothing was built"; done
  exit 0
fi

ref() {
  python3 -c '
import sys, zlib
b = sys.argv[1].encode("utf-8")
print("%08x" % (zlib.crc32(b) & 0xffffffff))
print("compressed", len(zlib.compress(b)))
print("roundtrip ok")
' "$1"
}

try() { # assertion, input
  ref "$2" >"$GRADE_TMP/exp"
  timeout 20 ./build/exec/zcheck "$2" >"$GRADE_TMP/act" 2>&1
  same_output "$1" "$GRADE_TMP/exp" "$GRADE_TMP/act"
}
try "output for 'hello world' matches zlib" "hello world"
try "output for a long repetitive string matches zlib" \
  "$(python3 -c 'print("abcabcabc" * 400, end="")')"
try "output for a non-ASCII string matches zlib" "naïve café ☕ données"

n=$(cat ./*.idr src/*.idr src/*/*.idr 2>/dev/null | grep -c '%foreign')
if [ "$n" -ge 3 ] && cat ./*.idr src/*.idr src/*/*.idr 2>/dev/null | grep -q 'crc32' &&
   cat ./*.idr src/*.idr src/*/*.idr 2>/dev/null | grep -q 'uncompress'; then
  pass "the program calls zlib through %foreign" "$n %foreign declarations"
else
  fail "the program calls zlib through %foreign" "$n %foreign declarations"
fi
