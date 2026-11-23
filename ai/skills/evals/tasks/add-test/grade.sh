#!/bin/sh
# WORKDIR is the git worktree the agent worked in; $EVAL_REPO (default: this
# repository) is the checkout with the built compiler and test environment.
. "$(dirname "$0")/../../lib.sh"
REPO=${EVAL_REPO:-$(cd "$TASK/../../../../.." && pwd)}

A1="one new test directory with run and expected"
A2="it is in a category that the suite collects"
A3="run uses testutils.sh"
A4="the suite's runner passes the new test"
A5="expected shows the Interpolation Nat error with its code"
A6="new files pass lint (no trailing whitespace, final newline)"
A7="nothing else in the worktree changed"

# New files, whether left untracked or staged with `git add`.
added() { git status --porcelain --untracked-files=all | sed -n -e 's/^?? //p' -e 's/^A[ M] //p'; }

new=$(added | grep '^tests/' | grep '/run$' | xargs -r -n1 dirname)
n=$(printf '%s\n' "$new" | grep -c .)
if [ "$n" -ne 1 ] || [ ! -f "$new/expected" ]; then
  fail "$A1" "found $n new test directories: $new"
  fail_rest "no single new test to grade" "$A2" "$A3" "$A4" "$A5" "$A6" "$A7"
  exit 0
fi
pass "$A1" "$new"

category=${new#tests/}; category=$(dirname "$category")
if grep -q "testsInDir \"$category\"" tests/Main.idr; then
  pass "$A2" "$category is a pool in tests/Main.idr"
else
  fail "$A2" "$category is not collected by tests/Main.idr"
fi

if grep -q 'testutils\.sh' "$new/run"; then pass "$A3" "$(grep testutils "$new/run")"
else fail "$A3" "$(head -n 3 "$new/run")"; fi

# The same environment as `make test`: the prefix of the test libraries, and the
# name of the directory in it (testutils.sh builds the package path from it).
version=$("$REPO/build/exec/idris2" --version | sed 's/.*version \([0-9.]*\).*/\1/')
out=$(cd tests && NAME_VERSION=idris2-$version IDRIS2_PREFIX=$REPO/build/env timeout 300 "$REPO/tests/build/exec/runtests" \
  "$REPO/build/exec/idris2" --threads 1 --failure-file "$GRADE_TMP/failures" \
  --only "$(basename "$new")" </dev/null 2>&1)
find "$new" -name output -delete 2>/dev/null
rm -rf "$new/build"
if printf '%s' "$out" | grep -q "${new#tests/}: success"; then
  pass "$A4" "$(printf '%s' "$out" | grep -e success -e successful | tail -n 2)"
else
  fail "$A4" "$(printf '%s' "$out" | tail -n 8)"
fi

if grep -q 'Interpolation Nat' "$new/expected" && grep -q '\[E0401\]' "$new/expected"; then
  pass "$A5" "$(grep -m1 'Interpolation Nat' "$new/expected")"
else
  fail "$A5" "$(head -n 3 "$new/expected")"
fi

bad=
for f in $(added); do
  [ -f "$f" ] || continue
  grep -q '[[:space:]]$' "$f" && bad="$bad $f(trailing whitespace)"
  [ -n "$(tail -c 1 "$f")" ] && bad="$bad $f(no final newline)"
done
if [ -z "$bad" ]; then pass "$A6" "clean"; else fail "$A6" "$bad"; fi

other=$(git status --porcelain --untracked-files=all | grep -v "^?? $new/" | grep -v "^A[ M] $new/" | grep -v 'CHANGELOG_NEXT.md')
if [ -z "$other" ]; then pass "$A7" "only $new"; else fail "$A7" "$other"; fi
