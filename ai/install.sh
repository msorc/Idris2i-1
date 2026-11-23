#!/bin/sh
# Link the skills into a skills directory, so that an agent finds them outside
# this repository.
#
#   ai/install.sh [DIR]      DIR defaults to ~/.claude/skills
#
# Each skill becomes a symbolic link to its folder here, so an update of the
# repository updates the installed skill. A link from an earlier run is
# replaced; anything else with the same name is left alone and reported.

here=$(cd "$(dirname "$0")" && pwd)
target=${1:-$HOME/.claude/skills}

mkdir -p "$target" || exit 1
status=0
for skill in "$here"/skills/*/SKILL.md; do
  dir=$(dirname "$skill")
  name=$(basename "$dir")
  dest=$target/$name
  if [ -L "$dest" ]; then
    rm "$dest"
  elif [ -e "$dest" ]; then
    echo "skipped $name: $dest exists and is not a link" >&2
    status=1
    continue
  fi
  ln -s "$dir" "$dest" && echo "linked $dest -> $dir"
done
exit $status
