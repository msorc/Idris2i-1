#!/bin/sh
# Type-check every Idris example in the skills.
#
#   check.sh [-q] [-c IDRIS2I_1] [PATH...]
#
#   -q         print only failures and one final line
#   -c IDRIS2I_1  compiler to use (default: $IDRIS2I_1, idris2i-1 on PATH, ~/.idris2i-1/bin/idris2i-1)
#   PATH       skill folders or files to check (default: all skills)
#
# Two kinds of file are checked:
#
#   *.md with an ```idris fence or an <!-- idris block: literate Markdown,
#       it must type-check as it stands, without warnings.
#   cases/*.idr: the first line says what the compiler must report,
#       `-- expect: E0201 W0003` (each code must appear) or `-- expect: ok`.
#
# Without PATH it also checks each skill's frontmatter and that AGENTS.md at the
# repository root matches agents-md.sh.
#
# Exit status is 1 when any file fails.

here=$(cd "$(dirname "$0")" && pwd)
quiet=0
idris=${IDRIS2I_1:-}

while getopts qc: opt; do
  case $opt in
    q) quiet=1 ;;
    c) idris=$OPTARG ;;
    *) echo "usage: check.sh [-q] [-c IDRIS2I_1] [PATH...]" >&2; exit 2 ;;
  esac
done
shift $((OPTIND - 1))

if [ -z "$idris" ]; then
  if command -v idris2i-1 >/dev/null 2>&1; then
    idris=idris2i-1
  elif [ -x "$HOME/.idris2i-1/bin/idris2i-1" ]; then
    idris=$HOME/.idris2i-1/bin/idris2i-1
  else
    echo "check.sh: no idris2i-1 found; pass -c PATH" >&2
    exit 2
  fi
fi

tmp=$(mktemp -d "${TMPDIR:-/tmp}/skills-check.XXXXXX") || exit 2
trap 'rm -rf "$tmp"' EXIT INT TERM

# -p is not transitive, so every installed package the examples may use is named.
installed=$("$idris" --list-packages 2>/dev/null)
pkgs=
for p in contrib network linear test http tls http-tls; do
  if printf '%s\n' "$installed" | grep -q "^$p "; then
    pkgs="$pkgs -p $p"
  fi
done
have_tls=0
case " $pkgs " in *" -p tls "*) have_tls=1 ;; esac

full=0
if [ $# -eq 0 ]; then
  full=1
  set -- "$here"
fi

failed=0
count=0

report() { # status file [output-file]
  if [ "$1" = ok ]; then
    [ $quiet -eq 1 ] || echo "ok    $2"
  elif [ "$1" = skip ]; then
    [ $quiet -eq 1 ] || echo "skip  $2 ($3)"
  else
    echo "FAIL  $2"
    sed 's/^/      /' "$3"
    failed=$((failed + 1))
  fi
}

run_idris() { # file build-number extra-options...
  f=$1; n=$2; shift 2
  # $pkgs is split on purpose.
  # shellcheck disable=SC2086
  (cd "$(dirname "$f")" &&
   "$idris" --check --no-color --console-width 0 --build-dir "$tmp/b$n" \
     $pkgs "$@" "$(basename "$f")") >"$tmp/out" 2>&1
}

needs_tls() { grep -q 'Network\.TLS\|Network\.HTTP\.TLS' "$1"; }

check_md() {
  f=$1
  grep -q '^```idris\|^~~~idris\|^<!-- idris' "$f" || return 0
  count=$((count + 1))
  if [ $have_tls -eq 0 ] && needs_tls "$f"; then
    report skip "$2" "tls is not installed"
    return 0
  fi
  # A warning fails the file too: an example should not teach code that warns.
  if run_idris "$f" "$count" && ! grep -q '^Warning:' "$tmp/out"; then
    report ok "$2"
  else
    report fail "$2" "$tmp/out"
  fi
}

check_case() {
  f=$1
  count=$((count + 1))
  expect=$(sed -n '1s/^-- expect: *//p' "$f")
  if [ -z "$expect" ]; then
    echo "first line must be '-- expect: CODES' or '-- expect: ok'" >"$tmp/out"
    report fail "$2" "$tmp/out"
    return 0
  fi
  if [ $have_tls -eq 0 ] && needs_tls "$f"; then
    report skip "$2" "tls is not installed"
    return 0
  fi
  run_idris "$f" "$count" --error-format json
  status=$?
  if [ "$expect" = ok ]; then
    if [ $status -eq 0 ] && ! grep -q '"code":"' "$tmp/out"; then
      report ok "$2"
    else
      report fail "$2" "$tmp/out"
    fi
    return 0
  fi
  missing=
  for code in $expect; do
    grep -q "\"code\":\"$code\"" "$tmp/out" || missing="$missing $code"
  done
  if [ -z "$missing" ]; then
    report ok "$2"
  else
    { echo "expected but not reported:$missing"; echo "reported:"
      grep -o '"code":"[A-Z][0-9]*"' "$tmp/out" | sort -u; } >"$tmp/out2"
    report fail "$2" "$tmp/out2"
  fi
}

for target in "$@"; do
  if [ -f "$target" ]; then
    list=$target
  else
    list=$(find "$target" \( -name '*.md' -o -path '*/cases/*.idr' \) -type f | LC_ALL=C sort)
  fi
  for f in $list; do
    name=${f#"$here"/}
    case $f in
      *.md) check_md "$f" "$name" ;;
      *.idr) check_case "$f" "$name" ;;
    esac
  done
done

# With no PATH, also check what ties the skills together: the frontmatter of
# each skill, and the index in AGENTS.md.
if [ $full -eq 1 ]; then
  for dir in "$here"/*/; do
    name=$(basename "$dir")
    [ "$name" = evals ] && continue
    skill=$dir/SKILL.md
    count=$((count + 1))
    if [ ! -f "$skill" ]; then
      echo "no SKILL.md" >"$tmp/out"
      report fail "$name/SKILL.md" "$tmp/out"
    elif [ "$(sed -n '1p' "$skill")" != "---" ] ||
         ! sed -n '/^---$/,/^---$/p' "$skill" | grep -q "^name: $name\$" ||
         ! sed -n '/^---$/,/^---$/p' "$skill" | grep -q '^description: *[^>| ]..*'; then
      echo "frontmatter must have 'name: $name' and a one-line 'description:'" >"$tmp/out"
      report fail "$name/SKILL.md" "$tmp/out"
    else
      report ok "$name/SKILL.md frontmatter"
    fi
  done
  agents=$here/../../AGENTS.md
  if [ -f "$agents" ]; then
    count=$((count + 1))
    if "$here/agents-md.sh" | diff - "$agents" >"$tmp/out" 2>&1; then
      report ok "AGENTS.md"
    else
      echo "run: ai/skills/agents-md.sh > AGENTS.md" >>"$tmp/out"
      report fail "AGENTS.md is out of date" "$tmp/out"
    fi
  fi
fi

if [ $failed -ne 0 ]; then
  echo "skills: $failed of $count files failed"
  exit 1
fi
if [ $quiet -eq 1 ]; then
  echo "skills: all examples check"
else
  echo "skills: $count files check"
fi
