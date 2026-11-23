# Skills for LLM agents

`ai/skills/` holds [Agent Skills](https://agentskills.io) that teach a coding agent to
write Idris 2 with the compiler in this repository. A skill is a folder with a
`SKILL.md` (YAML frontmatter with `name` and `description`, then instructions) and
optional `references/`, `scripts/` and `cases/`.

| Skill | Use it for |
|---|---|
| `idris2` | any Idris 2 code: language rules, the check loop, errors, packages |
| `idris2-proofs` | totality, equality proofs, views, quantities |
| `idris2-libraries` | files, collections, concurrency, HTTP, TLS, JSON |
| `idris2-ffi` | calling C and other foreign code |
| `idris2-performance` | slow programs and slow type checking |
| `idris2-compiler-dev` | work on the compiler in this repository |

## Using the skills

- **Claude Code in this repository**: nothing to do, `.claude/skills` points here.
- **Claude Code in your own projects**: run `ai/install.sh`; it links each skill into
  `~/.claude/skills`.
- **Other agents**: `AGENTS.md` at the repository root lists each skill with its trigger
  and path; point your agent at a `SKILL.md` when its trigger applies.

## Checking the skills

```sh
ai/skills/check.sh                      # every skill, with idris2 from PATH or ~/.idris2
ai/skills/check.sh -c build/exec/idris2 ai/skills/idris2-proofs
```

The script type-checks every Idris example in every skill file and fails when
`AGENTS.md` is out of date (`ai/skills/agents-md.sh > AGENTS.md` regenerates it). The
golden test `tests/idris2/misc/skills001` runs it, so `make test` reports a skill that
a compiler change has made wrong.

The skills describe the compiler of this tree. A compiler that is older than the tree,
such as an installed one that has not been rebuilt since, fails the files that use
newer libraries (`Deriving.Eq`, `Data.Array`, `Data.Nat.Solver`): pass the fresh one
with `-c`.

## Rules for writing a skill file

The reader is a model that knows Haskell well, Idris 1 a little, and this compiler not
at all. It will believe whatever the file says, so a file may only say what the compiler
confirms.

1. **Every Idris example compiles.** Skill files are literate Markdown: the compiler
   reads the ```` ```idris ```` fences of a `.md` file and ignores the rest.
   `check.sh` runs `idris2 --check` on each file; a warning fails it as well.
2. **Wrong forms are checked too.** Show a mistake inside a `failing` block with a
   fragment of the message; the compiler then confirms that the code fails and that the
   message is the one you quote:

   ````markdown
   ```idris
   failing "Undefined name return"
     one : IO Int
     one = return 1
   ```
   ````

   A `failing` block cannot match an error code, a warning, or a parse error that stops
   the file. Put those in `cases/NAME.idr`, with the first line `-- expect: E0201 W0003`
   (each code must be reported) or `-- expect: ok`.
3. **Fence discipline.** The compiler takes every fence whose label *starts with*
   `idris` as code, and ends it at the first ```` ``` ````.
   - shell commands: `sh`; REPL sessions and compiler output: `text`; other languages
     by their name. Never `idris2`, `idris-repl` or `idris` with options.
   - A fence inside a list item is indented, so the compiler does not see it. Keep code
     that must be checked at the left margin.
   - No ```` ``` ```` inside an Idris string or comment.
   - All imports of a file go in its first code block. An invisible block keeps them
     out of the way of the prose and is still readable in the raw file:

     ```markdown
     <!-- idris
     import Data.List
     -->
     ```

   - A file is one module (`Main`): no `module` header, and a `namespace` per example
     when names would clash.
4. **Only what is true on `devel` today.** Check against the compiler, not against
   memory of upstream Idris 2. Mark a feature that upstream 0.8 does not have as
   "(this fork)" where an agent on another compiler would trip over it.
5. **Works outside this repository.** Installed packages have no source files, so a
   skill sends the agent to `:doc`, `:browse`, `:search`, `--explain` and `--dump-api`.
   Paths into this repository appear only after "in the compiler repository".
6. **Short, with reasons.** Keep `SKILL.md` under about 300 lines; move detail into
   `references/` and say in `SKILL.md` when to read each file. Say why a rule holds: a
   model that knows the reason applies the rule to cases the file did not list. Give a
   reference file longer than 300 lines a table of contents.
7. **The description decides whether the skill is used.** It is the only part an agent
   sees before loading the skill: say what the skill covers and name the words and
   situations that should trigger it. Write it on one line (quote it when it contains
   `: `), at most 1024 characters; `name` is the folder's name.
8. `lint/lint.py` applies: no trailing whitespace, a newline at the end of the file.

## Evals

`ai/skills/evals/` holds 14 tasks that measure the skills against an agent without
them, each with a grader that builds and runs the result, and the queries used to test
whether a description triggers its skill (`triggers/`). See `ai/skills/evals/README.md`.
