#!/bin/bash
# Eval only, never in a real checkout: ci/agent-eval/run.sh puts this file in a throwaway copy as checks/run.sh. It
# writes the scenario's results fixture (results.json beside the copy) as a new run, the way checks/run.sh writes
# results, instead of checking this Mac: a real run takes minutes and keeps state in the account's own home folder.
fk="$(cd "$(dirname "$0")/.." && pwd)"
fixture="$fk/../results.json"
[ -f "$fixture" ] || { echo "run incomplete: some controls were not recorded" >&2; exit 1; }
id="$(date -u +%Y%m%dT%H%M%SZ)"
while [ -e "$fk/reports/$id" ]; do sleep 1; id="$(date -u +%Y%m%dT%H%M%SZ)"; done
mkdir -p "$fk/reports/$id" || exit 1
jq --arg run "$id" '.run = $run' "$fixture" > "$fk/reports/$id/results.json" || exit 1
ln -sfn "$id" "$fk/reports/latest"
jq -r '.results | group_by(.status) | map("\(.[0].status): \(length)") | join("  ")' "$fk/reports/$id/results.json"
echo "report: reports/$id/results.json"
