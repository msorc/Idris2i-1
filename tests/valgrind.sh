#!/bin/sh

# Run a program under Valgrind: `$VALGRIND prog args`, where testutils.sh
# sets VALGRIND to run this script when Valgrind is installed.
#
# The report of Valgrind goes to output.valgrind.refc.log in the current
# directory. When it has errors (invalid reads and writes, uses of
# uninitialised values, bad frees, and leaks that are definitely or possibly
# lost), a line saying so is printed on the standard output, so that the
# output of the test differs from its expected output. Nothing is printed
# otherwise: the expected output must not depend on whether Valgrind is
# installed. The exit code is the one of the program.

log=output.valgrind.refc.log
here=$(dirname "$0")

rm -f "$log"
valgrind --leak-check=full --errors-for-leak-kinds=definite,possible -s \
    --suppressions="$here/valgrind.supp" --log-file="$log" "$@"
status=$?

errors=$(sed -n 's/^==[0-9]*== ERROR SUMMARY: \([0-9]*\) error.*/\1/p' "$log" 2>/dev/null | tail -n 1)
if [ -z "$errors" ]; then
    echo "valgrind: no report for $1 (see $log)"
elif [ "$errors" != 0 ]; then
    echo "valgrind: memory errors in $1 (see $log)"
fi

exit $status
