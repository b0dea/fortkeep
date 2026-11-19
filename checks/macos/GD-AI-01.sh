#!/bin/bash
. "$(dirname "$0")/../lib/common.sh"
. "$(dirname "$0")/../lib/agents.sh"
. "$(dirname "$0")/../lib/baselines.sh"
ID=GD-AI-01
files="$(devward_control_files)"
excl=""; case "$files" in *'!skipped'*) excl=" (a private folder was excluded)" ;; esac
cur="$(printf '%s\n' "$files" | devward_control_hashes)"
B="$(devward_baseline_dir)/control-files.txt"
devward_baseline_ready "$ID" "$B" "your agent control files" "$excl" || exit 0
base="$(cat "$B")" || { devward_result "$ID" ERROR "Could not read your baseline" "$(devward_tilde "$B") is not readable$excl"; exit 0; }
diff="$(devward_control_diff "$base" "$cur")"
n="$(devward_count "$diff")"
list() { devward_join "$(printf '%s\n' "$1" | head -8 | while IFS=$'\t' read -r how p k; do printf '%s %s\n' "$how" "$(devward_control_label "$(devward_tilde "$p")" "$k")"; done)" ', '; }
paths() { devward_join "$(printf '%s\n' "$1" | head -8 | while IFS= read -r p; do devward_tilde "$p"; done)" ', '; }
unread="$(printf '%s\n' "$cur" | awk -F'\t' '$3 == "unreadable" {print $1}')"
if [ "$n" -gt 0 ]; then
  devward_result "$ID" FAIL "$n agent control file(s) changed since your baseline" "$(list "$diff")${unread:+. Could not read: $(paths "$unread")}$excl"
elif [ -n "$unread" ]; then
  devward_result "$ID" ERROR "Could not read $(devward_count "$unread") agent control file(s)" "$(paths "$unread")$excl"
else
  devward_result "$ID" PASS "$(devward_count "$cur") agent control file(s) unchanged since your baseline" "${excl# }"
fi
