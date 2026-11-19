#!/bin/bash
# Shows status changes between the two latest runs, or between two given results.json files.
. "$(dirname "$0")/lib/common.sh"
if [ $# -eq 2 ]; then
  prev="$1"; cur="$2"
else
  # shellcheck disable=SC2012  # run dirs are timestamp-named
  runs="$(ls -1d "$DEVWARD_REPORTS"/2*/ 2>/dev/null | sort | tail -2)"
  if [ "$(printf '%s\n' "$runs" | grep -c .)" -lt 2 ]; then echo "no previous run to compare with"; exit 0; fi
  prev="$(printf '%s\n' "$runs" | head -1)results.json"
  cur="$(printf '%s\n' "$runs" | tail -1)results.json"
fi
out="$(jq -rn --slurpfile a "$prev" --slurpfile b "$cur" '
  ($a[0].results | map({(.id): .status}) | add // {}) as $p
  | $b[0].results[] | select(($p[.id] // "NEW") != .status)
  | "\(.id): \($p[.id] // "NEW") → \(.status)  \(.title)"')"
if [ -n "$out" ]; then echo "$out"; else echo "no changes since the previous run"; fi
