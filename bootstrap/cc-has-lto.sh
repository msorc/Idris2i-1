#!/bin/sh

# Succeeds when the C compiler $1 (default: cc) can compile and link a program
# with -flto=auto, used to build big RefC programs (the compiler) in parts
# without losing the inlining across them.

CC="${1:-cc}"
DIR="$(mktemp -d 2>/dev/null || echo "${TMPDIR:-/tmp}/cc-has-lto.$$")"
mkdir -p "$DIR"
trap 'rm -rf "$DIR"' EXIT

printf 'int f(void);\nint main(void) { return f(); }\n' > "$DIR/a.c"
printf 'int f(void) { return 0; }\n' > "$DIR/b.c"
"$CC" -flto=auto -c "$DIR/a.c" -o "$DIR/a.o" >/dev/null 2>&1 &&
    "$CC" -flto=auto -c "$DIR/b.c" -o "$DIR/b.o" >/dev/null 2>&1 &&
    "$CC" -flto=auto "$DIR/a.o" "$DIR/b.o" -o "$DIR/a.out" >/dev/null 2>&1 &&
    "$DIR/a.out"
