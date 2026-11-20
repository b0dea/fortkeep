#!/bin/bash
. "$(dirname "$0")/../lib/common.sh"
. "$(dirname "$0")/../lib/baselines.sh"
ID=GD-RT-02
cur="$(fortkeep_listeners)" || { fortkeep_result "$ID" ERROR "Could not list the programs listening on the network" "netstat -anv -p tcp gave no table"; exit 0; }
B="$(fortkeep_baseline_dir)/listeners.txt"
fortkeep_baseline_ready "$ID" "$B" "what listens now" || exit 0
new="$(fortkeep_baseline_new "$B" "$cur")"
n="$(fortkeep_count "$new")"
if [ "$n" -eq 0 ]; then fortkeep_result "$ID" PASS "No new programs listening on the network since your baseline" "$(fortkeep_count "$cur") program(s) accept connections from the network"
else fortkeep_result "$ID" FAIL "$n new program(s) listening on the network since your baseline" "New: $(fortkeep_join "$(printf '%s\n' "$new" | head -5)" ', ')"; fi
