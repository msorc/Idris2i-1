#!/bin/sh
# Check that the C functions that the RefC backend calls for the `%foreign`
# declarations of Idris source files exist: that the C files that RefC
# generates see a declaration of each (a prototype in `runtime.h` or in the
# header that the declaration names: GCC 14 and later refuse an implicit
# declaration) and that the support libraries define it.
#
# Usage:
#   check-foreign.sh <refc support dir> <c support dir> <source dir>...
# e.g., from the top of the repository, after `make support`:
#   sh support/refc/check-foreign.sh support/refc support/c \
#      libs/prelude libs/base libs/contrib libs/network libs/linear libs/http
#
# For each `%foreign` declaration (at the start of a line, with the strings on
# the lines indented below it) this takes the string that RefC uses: the first
# "RefC:" one, else the first "C:" one.  A string may be a literal or a helper
# applied to a literal, `supportC "idris2i_1_sleep"`, where the helper is defined
# in the same file as `supportC fn = "C:\{fn}, lib, header"` or
# `libc fn = "C:" ++ fn ++ ", lib"`.  A declaration with a header includes
# `runtime.h` and the header, one without includes `runtime.h` only (as the
# generated C does).  A function from a library other than the support
# libraries and libc (no `lib` or a name starting with `libidris2i_1_support`
# or `libc`) is only checked for a declaration.
#
# It prints the functions that fail, with where they are declared in Idris,
# and exits with status 1 when one does.  CC (default cc) is the C compiler.

set -u

if [ $# -lt 3 ]; then
    echo "usage: $0 <refc support dir> <c support dir> <source dir>..." >&2
    exit 2
fi

refc=$1
csup=$2
shift 2

CC=${CC:-cc}
work=$(mktemp -d "${TMPDIR:-/tmp}/check-foreign.XXXXXX") || exit 2
trap 'rm -rf "$work"' EXIT INT TERM

# The declarations: one line each, "name<TAB>lib<TAB>header<TAB>where".
find "$@" -name '*.idr' -type f | LC_ALL=C sort | while read -r f; do
    awk -v file="$f" '
    function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
    # the string that RefC uses, of the strings of a declaration
    function flush(   i, s, lang, body, n, opts, k, hdr, lib) {
        if (!infor) return
        infor = 0
        pick = ""
        for (i = 1; i <= ns; i++) if (strs[i] ~ /^RefC:/) { pick = strs[i]; break }
        if (pick == "")
            for (i = 1; i <= ns; i++) if (strs[i] ~ /^C:/) { pick = strs[i]; break }
        if (pick == "") return
        lang = substr(pick, 1, index(pick, ":") - 1)
        body = substr(pick, index(pick, ":") + 1)
        n = split(body, opts, ",")
        for (k = 1; k <= n; k++) opts[k] = trim(opts[k])
        lib = (n >= 2) ? opts[2] : ""
        # (RefC includes the header only when there are a library and a header)
        hdr = (n == 3) ? opts[3] : ""
        if (lang == "RefC") { lib = ""; hdr = "" }
        printf "%s\t%s\t%s\t%s:%d\n", opts[1], lib, hdr, file, line0
    }
    # the strings of a line: literals, and helpers applied to literals
    function strings(s,   pre, lit, w, nw) {
        while (match(s, /"[^"]*"/)) {
            pre = substr(s, 1, RSTART - 1)
            lit = substr(s, RSTART + 1, RLENGTH - 2)
            s = substr(s, RSTART + RLENGTH)
            nw = split(pre, w, /[ \t(]+/)
            while (nw > 0 && w[nw] == "") nw--
            if (nw > 0 && (w[nw] in helper)) lit = "C:" lit helper[w[nw]]
            strs[++ns] = lit
        }
    }
    # pass 1: the helpers
    FNR == NR {
        if (match($0, /^[A-Za-z_][A-Za-z0-9_]* [A-Za-z_][A-Za-z0-9_]* = "C:\\\{[A-Za-z_][A-Za-z0-9_]*\}[^"]*"[ \t]*$/)) {
            split($0, p, " ")
            s = $0; sub(/^[^"]*"C:\\\{[^}]*\}/, "", s); sub(/"[ \t]*$/, "", s)
            helper[p[1]] = s
        } else if (match($0, /^[A-Za-z_][A-Za-z0-9_]* [A-Za-z_][A-Za-z0-9_]* = "C:" \+\+ [A-Za-z_][A-Za-z0-9_]* \+\+ "[^"]*"[ \t]*$/)) {
            split($0, p, " ")
            s = $0; sub(/^.*\+\+ "/, "", s); sub(/"[ \t]*$/, "", s)
            helper[p[1]] = s
        }
        next
    }
    # pass 2: the declarations
    /^%foreign/ { flush(); infor = 1; ns = 0; line0 = FNR; strings(substr($0, 9)); next }
    infor && /^[ \t]/ { strings($0); next }
    { flush() }
    END { flush() }
    ' "$f" "$f"
done > "$work/decls"

if [ ! -s "$work/decls" ]; then
    echo "no %foreign declaration found" >&2
    exit 2
fi

# Declarations: a C file per header, with every name (a function-like macro
# is fine: the generated C calls it).
cut -f3 "$work/decls" | LC_ALL=C sort -u > "$work/headers"
fail=0
i=0
: > "$work/undeclared"
while read -r h; do
    i=$((i + 1))
    c="$work/decl$i.c"
    {
        echo '#include <runtime.h>'
        [ -n "$h" ] && echo "#include <$h>"
        awk -F '\t' -v h="$h" '$3 == h { print $1 }' "$work/decls" | LC_ALL=C sort -u |
            while read -r n; do
                printf '#ifndef %s\nvoid *idris2i_1_check_%s = (void *)&%s;\n#endif\n' "$n" "$n" "$n"
            done
    } > "$c"
    if ! $CC -fsyntax-only -I"$refc" -I"$csup" "$c" > "$work/decl$i.log" 2>&1; then
        # the names that the compiler does not know
        # (GCC: 'x' undeclared, clang: use of undeclared identifier 'x')
        sed -n -e "s/.*error: [‘'\`]\([A-Za-z_][A-Za-z0-9_]*\)[’'] undeclared.*/\1/p" \
               -e "s/.*error: use of undeclared identifier [‘'\`]\([A-Za-z_][A-Za-z0-9_]*\)[’'].*/\1/p" \
               "$work/decl$i.log" |
            while read -r n; do printf '%s\t%s\n' "$n" "$h"; done >> "$work/undeclared"
        if ! grep -q 'undeclared' "$work/decl$i.log"; then
            echo "cannot compile the declarations of header '${h:-runtime.h}':"
            cat "$work/decl$i.log"
            fail=1
        fi
    fi
done < "$work/headers"

# The support library: next to its headers in the repository, in lib/ of an
# installation (<prefix>/idris2i-1-<version>/{lib,support/c}).
suplib=$csup/libidris2i_1_support.a
[ -f "$suplib" ] || suplib=$csup/../../lib/libidris2i_1_support.a

# Definitions: a program that refers to every name of the support libraries
# and libc that is a function, linked as RefC links programs.
{
    echo '#include <runtime.h>'
    cut -f3 "$work/decls" | LC_ALL=C sort -u | while read -r h; do
        [ -n "$h" ] && echo "#include <$h>"
    done
    awk -F '\t' '$2 == "" || $2 ~ /^libidris2i_1_support/ || $2 ~ /^libc( |$)/ { print $1 }' "$work/decls" |
        LC_ALL=C sort -u | while read -r n; do
            if ! cut -f1 "$work/undeclared" | grep -qx "$n"; then
                printf '#ifndef %s\nvoid *volatile idris2i_1_check_%s = (void *)&%s;\n#endif\n' "$n" "$n" "$n"
            fi
        done
    echo 'int main(void) { return 0; }'
} > "$work/link.c"
: > "$work/undefined"
if ! $CC -o "$work/link" -I"$refc" -I"$csup" "$work/link.c" \
        "$suplib" -L"$refc" -lidris2i_1_refc -lgmp -lm -pthread \
        > "$work/link.log" 2>&1; then
    sed -n "s/.*undefined reference to [\`‘']\([A-Za-z_][A-Za-z0-9_]*\)['’].*/\1/p" "$work/link.log" |
        LC_ALL=C sort -u > "$work/undefined"
    if [ ! -s "$work/undefined" ]; then
        echo "cannot link the program that refers to the functions:"
        cat "$work/link.log"
        fail=1
    fi
fi

# The report, by Idris declaration.
report() { # file of names (and headers), message
    while IFS='	' read -r n h; do
        awk -F '\t' -v n="$n" -v h="${h-}" -v m="$2" '$1 == n && (h == "" || $3 == h) {
            printf "%s: %s %s (%s)\n", $4, n, m, ($3 == "" ? "runtime.h" : $3) }' "$work/decls"
    done < "$1"
}
if [ -s "$work/undeclared" ]; then
    LC_ALL=C sort -u "$work/undeclared" | report /dev/stdin "is not declared in"
    fail=1
fi
if [ -s "$work/undefined" ]; then
    report "$work/undefined" "is not defined by the support libraries, declared in"
    fail=1
fi

total=$(cut -f1 "$work/decls" | LC_ALL=C sort -u | wc -l)
if [ "$fail" = 0 ]; then
    echo "$total C functions of %foreign declarations: all declared and defined"
fi
exit $fail
