#!/usr/bin/env python3
"""Grade one run of an eval task and write grading.json next to the work directory.

    grade.py TASK WORKDIR [OUT.json]

Runs tasks/TASK/grade.sh on WORKDIR and turns its PASS|text|evidence lines into the
grading.json that the skill-creator viewer reads (fields text, passed, evidence).
The compiler is $IDRIS2, or ~/.idris2/bin/idris2.
"""
import json
import os
import subprocess
import sys


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    task, work = sys.argv[1], os.path.abspath(sys.argv[2])
    here = os.path.dirname(os.path.abspath(__file__))
    out = sys.argv[3] if len(sys.argv) > 3 else os.path.join(os.path.dirname(work), "grading.json")
    run = subprocess.run([os.path.join(here, "tasks", task, "grade.sh"), work],
                         capture_output=True, text=True, timeout=1800)
    expectations = []
    for line in run.stdout.splitlines():
        parts = line.split("|", 2)
        if len(parts) == 3 and parts[0] in ("PASS", "FAIL"):
            expectations.append({"text": parts[1], "passed": parts[0] == "PASS", "evidence": parts[2]})
    passed = sum(e["passed"] for e in expectations)
    total = len(expectations)
    result = {
        "expectations": expectations,
        "summary": {"passed": passed, "failed": total - passed, "total": total,
                    "pass_rate": round(passed / total, 2) if total else 0.0},
    }
    with open(out, "w") as f:
        json.dump(result, f, indent=2)
        f.write("\n")
    print("%s: %d/%d" % (task, passed, total))


main()
