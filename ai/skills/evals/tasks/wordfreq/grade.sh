#!/bin/sh
. "$(dirname "$0")/../../lib.sh"

assert "idris2 --build wordfreq.ipkg succeeds" "$IDRIS" --build wordfreq.ipkg
exe=./build/exec/wordfreq
if [ ! -x "$exe" ]; then
  for t in "output on the sample text matches the reference" \
           "a text with fewer than 10 words prints them all" \
           "no argument: usage on stderr, status 2" \
           "unreadable file: message on stderr, status 1"; do
    fail "$t" "no executable build/exec/wordfreq"
  done
  exit 0
fi

ref() {
  python3 -c '
import re, sys, collections
words = re.findall(r"[A-Za-z]+", open(sys.argv[1]).read())
c = collections.Counter(w.lower() for w in words)
for w, n in sorted(c.items(), key=lambda kv: (-kv[1], kv[0]))[:10]:
    print(n, w)
' "$1"
}

ref "$TASK/sample.txt" >"$GRADE_TMP/exp1"
"$exe" "$TASK/sample.txt" >"$GRADE_TMP/act1" 2>/dev/null
same_output "output on the sample text matches the reference" "$GRADE_TMP/exp1" "$GRADE_TMP/act1"

printf 'b a, B! c\n' >"$GRADE_TMP/small.txt"
ref "$GRADE_TMP/small.txt" >"$GRADE_TMP/exp2"
"$exe" "$GRADE_TMP/small.txt" >"$GRADE_TMP/act2" 2>/dev/null
same_output "a text with fewer than 10 words prints them all" "$GRADE_TMP/exp2" "$GRADE_TMP/act2"

"$exe" >"$GRADE_TMP/o" 2>"$GRADE_TMP/e"; st=$?
if [ $st -eq 2 ] && grep -q 'usage: wordfreq FILE' "$GRADE_TMP/e" && [ ! -s "$GRADE_TMP/o" ]; then
  pass "no argument: usage on stderr, status 2" "status 2, stderr: $(cat "$GRADE_TMP/e")"
else
  fail "no argument: usage on stderr, status 2" "status $st, stdout: $(cat "$GRADE_TMP/o"), stderr: $(cat "$GRADE_TMP/e")"
fi

"$exe" "$GRADE_TMP/does-not-exist" >"$GRADE_TMP/o" 2>"$GRADE_TMP/e"; st=$?
if [ $st -eq 1 ] && [ -s "$GRADE_TMP/e" ] && [ ! -s "$GRADE_TMP/o" ]; then
  pass "unreadable file: message on stderr, status 1" "status 1, stderr: $(cat "$GRADE_TMP/e")"
else
  fail "unreadable file: message on stderr, status 1" "status $st, stdout: $(cat "$GRADE_TMP/o"), stderr: $(cat "$GRADE_TMP/e")"
fi
