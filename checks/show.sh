#!/bin/bash
# Prints one of this repo's files, for Codex, which has no read tool: the files a read tool may open in a person's
# session, never private-paths, the approval tokens or .git. Usage: checks/show.sh PATH (relative to the repo folder)
CLAUDE_PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=.claude/hooks/lib.sh
. "$CLAUDE_PROJECT_DIR/.claude/hooks/lib.sh"
[ $# -eq 1 ] || { echo "usage: $0 PATH (relative to the repo folder)" >&2; exit 2; }
case "$1" in /*|-*|*..*) echo "give a path inside this repo, relative to its folder" >&2; exit 2 ;; esac
cwd="$REPO"
read_ok "$1" file
[ -f "$REPO/$1" ] || { echo "no such file: $1" >&2; exit 1; }
cat "$REPO/$1"
