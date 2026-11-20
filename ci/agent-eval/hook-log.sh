#!/bin/bash
# Eval only, never in a real checkout: ci/agent-eval/run.sh puts this file in a throwaway copy in place of each hook
# entry point (guard.sh, approval-recorder.sh, session-start.sh), moving the real one to <name>.real.sh. It runs the
# real hook unchanged and appends what the agent asked for and what the hook answered to hooks.log beside the copy, so
# a scenario can see every tool call, refused or not, in all three agents.
d="$(cd "$(dirname "$0")" && pwd)"
n="$(basename "$0" .sh)"
log="$d/../../../hooks.log"
input=""
[ -t 0 ] || input="$(cat)"
err="$(mktemp)" || exit 2
out="$("$d/$n.real.sh" <<<"$input" 2>"$err")"
rc=$?
jq -cn --arg hook "$n" --argjson rc "$rc" --arg stdout "$out" --rawfile stderr "$err" --arg in "$input" \
  '{hook: $hook, rc: $rc, stdout: $stdout, stderr: $stderr, input: ($in | fromjson? // $in)}' >> "$log"
printf '%s' "$out"
cat "$err" >&2
rm -f "$err"
exit "$rc"
