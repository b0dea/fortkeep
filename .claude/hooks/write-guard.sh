#!/bin/bash
# PreToolUse(Edit|Write|MultiEdit|NotebookEdit, and apply_patch for Codex and OpenCode), run through guard.sh: edits
# stay in the agent's own scratch and plan folders, plus this repo and its memory in a development session. Anything else on
# this Mac changes only through a fix script, and a person's agent writes nothing in this repo: checks/configure.sh
# saves settings and checks/run.sh writes results.
set -o pipefail
# shellcheck source=.claude/hooks/lib.sh
. "$(dirname "$0")/lib.sh"
input="$(cat)"
[ -n "$input" ] || block "guard could not read the request"
f="$(printf '%s' "$input" | jq -r '.tool_input.file_path // .tool_input.notebook_path // ""')" || block "guard could not read the request"
patch="$(printf '%s' "$input" | jq -r '.tool_input.command // "" | strings')" || block "guard could not read the request"
if [ -n "$patch" ]; then
  # apply_patch (Codex, OpenCode) carries its patch here: every file it names, including a move's destination, is
  # checked like a single edit. Codex and OpenCode trim each line of any Unicode space (and OpenCode a byte-order
  # mark) before reading a header, so this does too; a line that starts like a header (*** and a word) but isn't one
  # it knows is refused. Codex 0.170's grammar names paths only in Add, Update and Delete File and Move to; its
  # Environment ID header picks another environment, whose folders aren't these, so it is refused too.
  f="$(printf '%s\n' "$patch" | perl -CSD -ne '
    s/^[\p{Space}\x{FEFF}]+|[\p{Space}\x{FEFF}]+$//g;
    next unless /^\*\*\*\s*\p{L}/;
    if (/^\*\*\*\s*(?:Add|Update|Delete)\s+File\s*:\s*(.+)$/ || /^\*\*\*\s*Move\s+to\s*:\s*(.+)$/) { print "$1\n"; next }
    next if /^\*\*\*\s*(?:Begin Patch|End Patch|End of File)$/;
    print STDERR "unknown header\n"; exit 1')" || block "guard could not read the patch"
  [ -n "$f" ] || block "guard could not read the patch"
fi
[ -n "$f" ] || exit 0
cwd="$(printf '%s' "$input" | jq -r '.cwd // empty')" || block "guard could not read the request"
repo="$(real "$REPO")" || block "guard could not find this repo"
# The repo's own guards, checks and fixes run later without a prompt, so they change only in a development session:
# a maintainer starts the agent with DEVWARD_DEV=1 and the marker ~/.config/devward/dev (devward_dev_session).
dev=""; devward_dev_session && dev=1
if [ -n "$dev" ]; then allowed="$repo/"$'\n'"$(agent_dirs dev)"; else allowed="$(agent_dirs write)"; fi
while IFS= read -r one; do
  [ -n "$dev" ] || ascii "$one" || block "non-ASCII characters are refused in a person's session"
  t="$(real "$one")" || block "guard could not read the request"
  if ! under "$t" "$allowed"; then
    case "$t/" in "$repo/"*) block "a person's agent writes nothing in this repo: settings go through checks/configure.sh and results come only from checks/run.sh (a maintainer starts the agent with DEVWARD_DEV=1, after creating the file ~/.config/devward/dev, to change the repo)" ;; esac
    block "edits outside this repo go through fix scripts after the person's answer"
  fi
  # Claude Code also denies these in .claude/settings.json; Codex and OpenCode rely on this check alone.
  case "$t/" in "$repo/reports/.approvals/"*|"$repo/reports/knockknock/"*)
    block "approval tokens and KnockKnock scans are written only by the hooks and checks" ;;
  esac
done <<EOF
$f
EOF
exit 0
