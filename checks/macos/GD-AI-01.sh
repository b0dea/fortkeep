#!/bin/bash
. "$(dirname "$0")/../lib/common.sh"
. "$(dirname "$0")/../lib/agents.sh"
. "$(dirname "$0")/../lib/baselines.sh"
ID=GD-AI-01
files="$(fortkeep_control_files)"
excl=""; case "$files" in *'!skipped'*) excl=" (a private folder was excluded)" ;; esac
cur="$(printf '%s\n' "$files" | fortkeep_control_hashes)"
B="$(fortkeep_baseline_dir)/control-files.txt"
fortkeep_baseline_ready "$ID" "$B" "your agent control files" "$excl" || exit 0
base="$(cat "$B")" || { fortkeep_result "$ID" ERROR "Could not read your baseline" "$(fortkeep_tilde "$B") is not readable$excl"; exit 0; }
diff="$(fortkeep_control_diff "$base" "$cur")"
n="$(fortkeep_count "$diff")"
list() { fortkeep_join "$(printf '%s\n' "$1" | head -8 | while IFS=$'\t' read -r how p k; do printf '%s %s\n' "$how" "$(fortkeep_control_label "$(fortkeep_tilde "$p")" "$k")"; done)" ', '; }
paths() { fortkeep_join "$(printf '%s\n' "$1" | head -8 | while IFS= read -r p; do fortkeep_tilde "$p"; done)" ', '; }
unread="$(printf '%s\n' "$cur" | awk -F'\t' '$3 == "unreadable" {print $1}')"
if [ "$n" -gt 0 ]; then
  fortkeep_result "$ID" FAIL "$n agent control file(s) changed since your baseline" "$(list "$diff")${unread:+. Could not read: $(paths "$unread")}$excl"
elif [ -n "$unread" ]; then
  fortkeep_result "$ID" ERROR "Could not read $(fortkeep_count "$unread") agent control file(s)" "$(paths "$unread")$excl"
else
  fortkeep_result "$ID" PASS "$(fortkeep_count "$cur") agent control file(s) unchanged since your baseline" "${excl# }"
fi
