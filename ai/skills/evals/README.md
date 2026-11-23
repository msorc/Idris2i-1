# Evals for the skills

Each task is something a user would ask for, with a grader that checks the result by
running it. A task is given to an agent twice, once with the skills available and
once without, and the two results are compared: a skill earns its place when the first
agent does better, or does as well with less work.

| File | What it is |
|---|---|
| `evals.json` | the tasks: name, the skill each one measures, one line on what it tests |
| `tasks/NAME/prompt.md` | what the agent is asked |
| `tasks/NAME/files/` | what the agent starts with |
| `tasks/NAME/grade.sh` | the grader: `grade.sh WORKDIR` prints `PASS\|assertion\|evidence` lines |
| `setup.sh TASK DIR` | makes the work directory and prints the prompt |
| `grade.py TASK WORKDIR` | runs the grader and writes `grading.json` for the skill-creator viewer |
| `lib.sh` | helpers shared by the graders |
| `triggers/SKILL.json` | queries that should and should not make an agent load the skill, in the format of the skill-creator's `run_eval` |

## Running a task

```sh
export IDRIS2=/path/to/idris2          # the compiler under test, for agent and grader
ai/skills/evals/setup.sh matrix /tmp/run/matrix/with_skill/work > /tmp/run/matrix/prompt.txt
# give prompt.txt to an agent whose working directory is .../work
ai/skills/evals/grade.py matrix /tmp/run/matrix/with_skill/work
```

Rules that keep the comparison fair:

- Both agents get the same prompt, the same compiler path, and a working directory
  outside this repository. Neither may read this repository, except that the agent
  with skills may read `ai/skills/<skill>/` (never `ai/skills/evals/`). The two
  `idris2-compiler-dev` tasks are about this repository, so there both may read it,
  apart from `ai/`.
- The agent with skills gets the list of all six skills with their descriptions and
  paths, and chooses what to read, as it would in real use.
- A grader builds from the sources the agent left, so a stale executable cannot pass.
- The graders use `curl`, `python3`, `cc`, zlib and, for `speedup`, `perf` (it falls
  back to processor time).

Every grader was run against a reference solution (all assertions pass) and against the
untouched starting files (the assertions about the result fail).
