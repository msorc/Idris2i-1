# Helpers for the graders. A grader is run as `grade.sh WORKDIR`, where WORKDIR
# is the directory an agent worked in, and prints one line per assertion:
#
#   PASS|assertion|evidence
#   FAIL|assertion|evidence
#
# Source this file first; it changes to WORKDIR and sets $IDRIS and $TASK.

TASK=$(cd "$(dirname "$0")" && pwd)
IDRIS=${IDRIS2I_1:-$HOME/.idris2i-1/bin/idris2i-1}
if [ $# -lt 1 ] || ! cd "$1"; then
  echo "usage: grade.sh WORKDIR" >&2
  exit 2
fi
GRADE_TMP=$(mktemp -d "${TMPDIR:-/tmp}/grade.XXXXXX")
trap 'rm -rf "$GRADE_TMP"' EXIT

oneline() { tr '\n' ' ' | cut -c1-300; }
pass() { printf 'PASS|%s|%s\n' "$1" "$(printf '%s' "$2" | oneline)"; }
fail() { printf 'FAIL|%s|%s\n' "$1" "$(printf '%s' "$2" | oneline)"; }

# assert TEXT COMMAND...: passes when the command succeeds; evidence is the
# tail of what it printed.
assert() {
  text=$1; shift
  if "$@" >"$GRADE_TMP/out" 2>&1; then
    pass "$text" "$(tail -n 3 "$GRADE_TMP/out")"
  else
    fail "$text" "$(tail -n 6 "$GRADE_TMP/out")"
  fi
}

# same_output TEXT EXPECTED-FILE ACTUAL-FILE
same_output() {
  if diff "$2" "$3" >"$GRADE_TMP/diff" 2>&1; then
    pass "$1" "output is identical to the reference"
  else
    fail "$1" "$(head -n 8 "$GRADE_TMP/diff")"
  fi
}

# forbid TEXT REGEX FILE...: passes when no file contains the pattern outside
# comments (lines starting with --, and the part of a line after --).
forbid() {
  text=$1; re=$2; shift 2
  found=$(sed 's/--.*$//' "$@" 2>/dev/null | grep -n -E "$re" | head -n 3)
  if [ -z "$found" ]; then pass "$text" "not found"; else fail "$text" "$found"; fi
}

# no_holes TEXT FILE [idris2i-1 options...]: passes when the file checks and has no holes.
no_holes() {
  text=$1; file=$2; shift 2
  out=$("$IDRIS" --no-color --console-width 0 "$@" "$file" --client ':m' 2>&1)
  case $out in
    "No holes"*) pass "$text" "$out" ;;
    *) fail "$text" "$out" ;;
  esac
}

# is_total TEXT FILE NAME [idris2i-1 options...]
is_total() {
  text=$1; file=$2; name=$3; shift 3
  out=$("$IDRIS" --no-color --console-width 0 "$@" "$file" --client ":total $name" 2>&1)
  case $out in
    *"is total"*) pass "$text" "$out" ;;
    *) fail "$text" "$out" ;;
  esac
}

# fail_rest REASON TEXT...: fail every listed assertion with the same evidence.
# For the assertions that mean nothing once an earlier step has failed.
fail_rest() {
  reason=$1; shift
  for text in "$@"; do fail "$text" "$reason"; done
}

# holes FILE [idris2i-1 options...]: prints the holes, or nothing when there are none
# (also prints the error when the file does not check).
holes() {
  file=$1; shift
  out=$("$IDRIS" --no-color --console-width 0 "$@" "$file" --client ':m' 2>&1)
  case $out in "No holes"*) ;; *) printf '%s\n' "$out" ;; esac
}
