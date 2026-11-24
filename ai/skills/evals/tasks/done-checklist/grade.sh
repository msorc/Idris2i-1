#!/bin/sh
. "$(dirname "$0")/../../lib.sh"

if [ ! -s ANSWER.md ]; then
  fail_rest "no ANSWER.md" "rebuilds the compiler with the repository's make target" \
    "runs only the affected tests (make test only=... or make retest)" \
    "reviews each changed expected file instead of accepting in bulk" \
    "points to the error-message rules (docs/source/implementation/error-messages.rst)" \
    "checks the error-code reference (error-codes.rst / --explain) for the old wording" \
    "looks for failing blocks and other places that match on the message text" \
    "adds a CHANGELOG_NEXT.md entry" "runs the lint check" \
    "gives the commit message style used on this branch"
  exit 0
fi
has() { # assertion, regex
  hit=$(grep -n -i -E -m1 -e "$2" ANSWER.md)
  if [ -n "$hit" ]; then pass "$1" "$hit"; else fail "$1" "nothing matches /$2/"; fi
}
has "rebuilds the compiler with the repository's make target" 'make +(idris2i-1-exec|all\b)|IDRIS2I_1_BOOT'
has "runs only the affected tests (make test only=... or make retest)" 'make +(re)?test.*only=|make +retest'
has "reviews each changed expected file instead of accepting in bulk" 'git diff.*expected|expected.*(one by one|each|review|read)|(review|read|inspect).*expected'
has "points to the error-message rules (docs/source/implementation/error-messages.rst)" 'error-messages\.rst'
has "checks the error-code reference (error-codes.rst / --explain) for the old wording" 'error-codes\.rst|--explain|ErrorCode'
has "looks for failing blocks and other places that match on the message text" 'failing'
has "adds a CHANGELOG_NEXT.md entry" 'CHANGELOG_NEXT'
has "runs the lint check" 'lint'
has "gives the commit message style used on this branch" '\[ [a-z]+ \]'
