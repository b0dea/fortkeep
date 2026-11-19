#!/bin/bash
. "$(dirname "$0")/../lib/common.sh"
. "$(dirname "$0")/../lib/agents.sh"
ID=OV-VL-03
dirs="$(devward_claude_dirs)"
if [ -z "$dirs" ]; then
  if devward_claude_private_skipped; then devward_claude_excluded_error "$ID"; else devward_result "$ID" NA "Claude Code is not set up on this Mac"; fi
  exit 0
fi
res="$(devward_guard_folders "$(devward_varlock_guard_probes)")"
pick() { printf '%s\n' "$res" | sed -n "s/^$1 / /p" | tr -d '\n'; }  # KIND — its folders, each after a space
total="$(printf '%s\n' "$res" | grep -c '^folder ')"; good="$(printf '%s\n' "$res" | grep -c '^good ')"
weak="$(pick weak)"; undecided="$(pick undecided)"
printf '%s\n' "$res" | grep -qx managed-bad && undecided=" managed settings$undecided"
ev="The guard refuses varlock printenv and load --format env, and lets varlock run through, in $good of $total Claude Code config folders"
if [ -n "$weak" ]; then
  devward_result "$ID" FAIL "$ev" "$(devward_claude_note "No working varlock rule in:$weak. Install this repo's templates/agent-guard.sh (BL-AI-02 shows how).${undecided:+ Could not decide:$undecided.}")"
elif [ -n "$undecided" ]; then
  devward_result "$ID" ERROR "$ev" "$(devward_claude_note "Could not decide (unreadable settings or plugin list, a bad hook matcher or a hook that timed out):$undecided.")"
else devward_result "$ID" PASS "$ev" "$(devward_claude_note "")"; fi
