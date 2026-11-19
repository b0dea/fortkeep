#!/bin/bash
. "$(dirname "$0")/../lib/common.sh"
. "$(dirname "$0")/../lib/baselines.sh"
ID=GD-RT-02
cur="$(devward_listeners)" || { devward_result "$ID" ERROR "Could not list the programs listening on the network" "netstat -anv -p tcp gave no table"; exit 0; }
B="$(devward_baseline_dir)/listeners.txt"
devward_baseline_ready "$ID" "$B" "what listens now" || exit 0
new="$(devward_baseline_new "$B" "$cur")"
n="$(devward_count "$new")"
if [ "$n" -eq 0 ]; then devward_result "$ID" PASS "No new programs listening on the network since your baseline" "$(devward_count "$cur") program(s) accept connections from the network"
else devward_result "$ID" FAIL "$n new program(s) listening on the network since your baseline" "New: $(devward_join "$(printf '%s\n' "$new" | head -5)" ', ')"; fi
