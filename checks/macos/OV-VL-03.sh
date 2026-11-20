#!/bin/bash
. "$(dirname "$0")/../lib/common.sh"
. "$(dirname "$0")/../lib/agents.sh"
ID=OV-VL-03
dirs="$(fortkeep_claude_dirs)"
if [ -z "$dirs" ]; then
  if fortkeep_claude_private_skipped; then fortkeep_claude_excluded_error "$ID"; else fortkeep_result "$ID" NA "Claude Code is not set up on this Mac"; fi
  exit 0
fi
res="$(fortkeep_guard_folders "$(fortkeep_varlock_guard_probes)")"
pick() { printf '%s\n' "$res" | sed -n "s/^$1 / /p" | tr -d '\n'; }  # KIND — its folders, each after a space
total="$(printf '%s\n' "$res" | grep -c '^folder ')"; good="$(printf '%s\n' "$res" | grep -c '^good ')"
weak="$(pick weak)"; undecided="$(pick undecided)"
printf '%s\n' "$res" | grep -qx managed-bad && undecided=" managed settings$undecided"
ev="The guard refuses varlock printenv and load --format env, and lets varlock run through, in $good of $total Claude Code config folders"
if [ -n "$weak" ]; then
  fortkeep_result "$ID" FAIL "$ev" "$(fortkeep_claude_note "No working varlock rule in:$weak. Install this repo's templates/agent-guard.sh (BL-AI-02 shows how).${undecided:+ Could not decide:$undecided.}")"
elif [ -n "$undecided" ]; then
  fortkeep_result "$ID" ERROR "$ev" "$(fortkeep_claude_note "Could not decide (unreadable settings or plugin list, a bad hook matcher or a hook that timed out):$undecided.")"
else fortkeep_result "$ID" PASS "$ev" "$(fortkeep_claude_note "")"; fi
