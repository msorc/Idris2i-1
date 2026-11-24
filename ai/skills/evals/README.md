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
export IDRIS2I_1=/path/to/idris2i-1          # the compiler under test, for agent and grader
ai/skills/evals/setup.sh matrix /tmp/run/matrix/with_skill/work > /tmp/run/matrix/prompt.txt
# give prompt.txt to an agent whose working directory is .../work
ai/skills/evals/grade.py matrix /tmp/run/matrix/with_skill/work
```

Rules that keep the comparison fair:

- Both agents get the same prompt, the same compiler path, and a working directory
  outside this repository. Neither may read this repository, except that the agent
  with skills may read `ai/skills/<skill>/` (never `ai/skills/evals/`). The two
  `idris2i-1-compiler-dev` tasks are about this repository, so there both may read it,
  apart from `ai/`.
- The agent with skills gets the list of all six skills with their descriptions and
  paths, and chooses what to read, as it would in real use.
- A grader builds from the sources the agent left, so a stale executable cannot pass.
- An agent started from a session that has the skills installed (`~/.claude/skills`,
  or this repository's `.claude/skills`) sees their descriptions whatever its prompt
  says, and the descriptions name tools such as `solveNat` and
  `IDRIS2I_1_REFC_LEAKCHECK`. For an arm with no skills at all, start it from a session
  without them.
- The graders use `curl`, `python3`, `cc`, zlib, `/usr/bin/time` (for `leak`) and, for
  `speedup` and `meter`, `perf` (they fall back to processor time).

Every grader was run against a reference solution (all assertions pass) and against the
untouched starting files (the assertions about the result fail).

## What help to expect

Measured on 2026-11-23 with the compiler at 4e89d479f, by Claude Opus 5.5 and Claude
Haiku 5.5 agents, one run per task and arm. Tasks take an agent one to seven minutes.

**The skills seldom decide whether a task gets done; they decide how much work it
takes, and only where the task needs something that this compiler alone has.** Both
models write working Idris2i-1 without them, and the compiler's error codes and import
suggestions correct most wrong guesses within a run or two.

The first 14 tasks, where the agent without skills saw nothing of them. Seconds for
the tasks of each skill, with skills | without:

| Skill | Tasks | Opus | Haiku | Reading |
|---|---|---|---|---|
| `idris2i-1-libraries` | `sumsvc`, `logstats` | 131 \| 245 | 110 \| 231 | about 2 times faster |
| `idris2i-1-ffi` | `zlib`, `geom` | 171 \| 269 | 194 \| 405 | 1.5 to 2 times faster |
| `idris2i-1-compiler-dev` | `add-test`, `done-checklist` | 196 \| 296 | 110 \| 127 | faster; one assertion gained on Haiku |
| `idris2i-1` | `wordfreq`, `bank`, `fix-errors`, `matrix` | 242 \| 207 | 179 \| 181 | no gain |
| `idris2i-1-proofs` | `lemmas`, `make-total` | 187 \| 191 | 119 \| 130 | no gain |
| `idris2i-1-performance` | `speedup`, `slowcheck` | 153 \| 114 | 192 \| 158 | no gain, slower |

Assertions passed over these tasks: Opus 88 of 88 in both arms; Haiku 88 of 88 with
the skills and 87 without. Tokens with the skills: about 15% more (Opus 828k against
729k, Haiku 971k against 835k), the price of reading them.

Four harder tasks, written to need what only the skills say (`leak`, `meter`, `arith`,
`deceq`). Here the agent without skills could still see the six descriptions, so its
arm is "descriptions only". Assertions passed and seconds:

| Task | Opus, with | Opus, descriptions | Haiku, with | Haiku, descriptions |
|---|---|---|---|---|
| `arith` | 4/4, 60 s | 4/4, 88 s | 4/4, 81 s | 0/4, 416 s |
| `deceq` | 5/5, 55 s | 5/5, 115 s | 5/5, 76 s | 3/5, 118 s |
| `leak` | 6/6, 68 s | 6/6, 58 s | 6/6, 55 s | 6/6, 68 s |
| `meter` | 5/5, 79 s | 5/5, 94 s | 5/5, 110 s | 5/5, 97 s |

So, by skill:

- `idris2i-1-libraries`, `idris2i-1-ffi`, `idris2i-1-compiler-dev`: expect the same result in
  about half the time and with far fewer compiler runs (the HTTP service on Haiku:
  one run against about twenty).
- `idris2i-1-proofs`: nothing on textbook induction and totality. On `solveNat` and
  deriving it is the difference between done and not done for the smaller model, and
  1.5 to 2 times the speed for the larger one.
- `idris2i-1`: nothing measurable on short tasks. Its value there is as the entry point
  that the other skills build on.
- `idris2i-1-performance`: nothing measurable on any of its four tasks. For the larger
  model its description alone was enough to reach for the leak check and to know
  that `Lazy` is not memoised.

What these numbers do not cover: long work over many files, where one wrong
assumption costs more than a compiler run; tasks run more than once (differences of
20 seconds are noise); and other models. A skill that shows no gain here is a
candidate for cutting down to what is specific to this compiler, not evidence that
its content is wrong or right: one claim of `idris2i-1-performance` was wrong and was
found only when a task was calibrated against it.
