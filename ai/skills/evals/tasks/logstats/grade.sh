#!/bin/sh
. "$(dirname "$0")/../../lib.sh"

REST="output for four log files matches the reference
a missing file is reported on stderr and skipped, status 0
no files: zero totals
the files are processed in threads that report over a channel"

rm -rf build
if [ -f build.sh ]; then
  IDRIS2I_1=$IDRIS PATH="$(dirname "$IDRIS"):$PATH" sh build.sh >"$GRADE_TMP/build.log" 2>&1
else
  "$IDRIS" --no-color Logstats.idr -o logstats >"$GRADE_TMP/build.log" 2>&1
fi
if [ -x build/exec/logstats ]; then
  pass "the program builds to build/exec/logstats" "$(tail -n 2 "$GRADE_TMP/build.log")"
else
  fail "the program builds to build/exec/logstats" "$(tail -n 6 "$GRADE_TMP/build.log")"
  echo "$REST" | while read -r t; do fail "$t" "no executable"; done
  exit 0
fi

python3 - "$GRADE_TMP" <<'PY'
import random, sys
random.seed(7)
d = sys.argv[1]
for n in range(4):
    with open("%s/log%d.txt" % (d, n), "w") as f:
        for i in range(3000 + 500 * n):
            r = random.random()
            if r < 0.01:
                f.write("garbage line %d\n" % i)
            elif r < 0.02:
                f.write("\n")
            elif r < 0.03:
                f.write("GET /x two00 12\n")
            else:
                status = random.choice([200, 200, 200, 301, 404, 500, 204])
                f.write("%s /p/%d %d %d\n" % (random.choice(["GET", "POST"]), i, status,
                                               random.randrange(0, 5000000)))
PY
ref() {
  python3 -c '
import sys
stats, files, bad = {}, 0, 0
for name in sys.argv[1:]:
    try:
        text = open(name).read()
    except OSError:
        continue
    files += 1
    for line in text.splitlines():
        w = line.split()
        if not w:
            continue
        if len(w) != 4 or not w[2].isdigit() or not w[3].isdigit():
            bad += 1
            continue
        c, b = stats.get(int(w[2]), (0, 0))
        stats[int(w[2])] = (c + 1, b + int(w[3]))
for s in sorted(stats):
    print(s, stats[s][0], stats[s][1])
print("files", files)
print("bad lines", bad)
' "$@"
}
L="$GRADE_TMP/log0.txt $GRADE_TMP/log1.txt $GRADE_TMP/log2.txt $GRADE_TMP/log3.txt"
# shellcheck disable=SC2086
ref $L >"$GRADE_TMP/exp"
# shellcheck disable=SC2086
timeout 60 ./build/exec/logstats $L >"$GRADE_TMP/act" 2>/dev/null
same_output "output for four log files matches the reference" "$GRADE_TMP/exp" "$GRADE_TMP/act"

ref "$GRADE_TMP/log0.txt" "$GRADE_TMP/nope.txt" "$GRADE_TMP/log1.txt" >"$GRADE_TMP/exp"
timeout 60 ./build/exec/logstats "$GRADE_TMP/log0.txt" "$GRADE_TMP/nope.txt" "$GRADE_TMP/log1.txt" \
  >"$GRADE_TMP/act" 2>"$GRADE_TMP/err"; st=$?
if diff -q "$GRADE_TMP/exp" "$GRADE_TMP/act" >/dev/null && [ $st -eq 0 ] &&
   grep -q "cannot read .*nope.txt" "$GRADE_TMP/err"; then
  pass "a missing file is reported on stderr and skipped, status 0" "$(cat "$GRADE_TMP/err")"
else
  fail "a missing file is reported on stderr and skipped, status 0" "status $st, stderr: $(cat "$GRADE_TMP/err"), $(diff "$GRADE_TMP/exp" "$GRADE_TMP/act" | head -n 4)"
fi

ref >"$GRADE_TMP/exp"
timeout 20 ./build/exec/logstats >"$GRADE_TMP/act" 2>/dev/null
same_output "no files: zero totals" "$GRADE_TMP/exp" "$GRADE_TMP/act"

src=$(sed 's/--.*$//' ./*.idr src/*.idr 2>/dev/null)
if printf '%s' "$src" | grep -q '\bfork\b' && printf '%s' "$src" | grep -q 'channelGet' &&
   printf '%s' "$src" | grep -q 'channelPut'; then
  pass "the files are processed in threads that report over a channel" "fork, channelPut and channelGet are used"
else
  fail "the files are processed in threads that report over a channel" "fork, channelPut or channelGet is missing"
fi
