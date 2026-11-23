#!/bin/sh
# Prepare a directory for one run of an eval task and print the task's prompt.
#
#   setup.sh TASK DIR
#
# DIR must not exist. It gets the task's input files; for `add-test` it becomes a
# git worktree of the compiler at the tip of devel (remove it afterwards with
# `git worktree remove --force DIR`). In the prompt, REPO is replaced by
# $EVAL_REPO, or by the path of this repository: a checkout of the same commit
# with the compiler built (`make all`) and the test environment made
# (`make testenv`).

here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/../../.." && pwd)
task=$1; dir=$2
if [ -z "$task" ] || [ -z "$dir" ] || [ ! -f "$here/tasks/$task/prompt.md" ]; then
  echo "usage: setup.sh TASK DIR   (tasks: $(ls "$here/tasks" | tr '\n' ' '))" >&2
  exit 2
fi
if [ -e "$dir" ]; then
  echo "setup.sh: $dir exists" >&2
  exit 2
fi
if [ "$task" = add-test ]; then
  git -C "$repo" worktree add --detach "$dir" devel >/dev/null 2>&1 || exit 1
else
  mkdir -p "$dir" || exit 1
  if [ -d "$here/tasks/$task/files" ]; then
    cp -R "$here/tasks/$task/files/." "$dir/"
  fi
fi
sed "s|REPO|${EVAL_REPO:-$repo}|g" "$here/tasks/$task/prompt.md"
