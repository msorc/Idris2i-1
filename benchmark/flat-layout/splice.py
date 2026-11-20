#!/usr/bin/env python3
"""Make a hand-edited copy of a RefC generated C file from an edit file.

    splice.py GENERATED.c EDITS.c OUT.c

The edit file has blocks, each introduced by a line

    //@@ types          inserted before the prototypes of the generated code
    //@@ add            inserted before the first function definition
    //@@ replace NAME   the new definition of the function NAME (its
                        prototype is replaced by the new header too)

This is only the tool used to write the edits; what is kept and applied by
run.sh are the patches (diff -u of GENERATED.c and OUT.c).
"""
import re
import sys


def main():
    gen_path, edits_path, out_path = sys.argv[1:4]
    src = open(gen_path).read()
    edits = open(edits_path).read()

    blocks = []
    cur = None
    for line in edits.splitlines(keepends=True):
        m = re.match(r"//@@ (types|add|replace)(?: (\S+))?\s*$", line)
        if m:
            cur = [m.group(1), m.group(2), ""]
            blocks.append(cur)
        elif cur is not None:
            cur[2] += line

    for kind, name, text in blocks:
        if kind != "replace":
            continue
        text = text.strip("\n") + "\n"
        header = re.match(r"(.*?\n\))", text, re.S)
        if not header:
            sys.exit(f"no header in the replacement of {name}")
        header = header.group(1)
        hdr_re = r"^[^\n]*[ *]" + re.escape(name) + r"\n\((?:\n(?:    |,   )[^\n]*)*\n\)"
        # the definition
        dm = None
        for m in re.finditer(hdr_re + r"\n\{\n", src, re.M):
            dm = m
            break
        if not dm:
            sys.exit(f"no definition of {name}")
        end = src.index("\n}\n", dm.end() - 1) + 3
        src = src[: dm.start()] + text + src[end:]
        # the prototype
        pm = re.search(hdr_re + r";\n", src, re.M)
        if pm:
            src = src[: pm.start()] + header + ";\n" + src[pm.end():]

    types = "".join(t for k, _, t in blocks if k == "types")
    adds = "".join(t for k, _, t in blocks if k == "add")
    if types:
        marker = "// function definitions\n"
        i = src.index(marker)
        src = src[:i] + types + "\n" + src[i:]
    if adds:
        m = re.search(r"^[^\n]*\n\((?:\n(?:    |,   )[^\n]*)*\n\)\n\{\n", src[src.index("// constant value definitions"):], re.M)
        i = src.index("// constant value definitions") + m.start()
        src = src[:i] + adds + "\n" + src[i:]
    open(out_path, "w").write(src)


main()
