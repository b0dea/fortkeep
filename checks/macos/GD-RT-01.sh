#!/bin/bash
. "$(dirname "$0")/../lib/common.sh"
. "$(dirname "$0")/../lib/apps.sh"
. "$(dirname "$0")/../lib/baselines.sh"
ID=GD-RT-01
K="$DEVWARD_REPORTS/knockknock"; B="$(devward_baseline_dir)/knockknock.json"
devward_app KnockKnock >/dev/null || { devward_result "$ID" FAIL "KnockKnock is not installed" "Install it first (BL-RT-02)"; exit 0; }
[ -f "$K/latest.json" ] || { devward_result "$ID" FAIL "No KnockKnock scan yet" "The weekly security check (BL-AU-02) runs one"; exit 0; }
mt="$(stat -f %m "$K/latest.json" 2>/dev/null)" || { devward_result "$ID" ERROR "Could not read the scan's age" "stat failed on the latest scan"; exit 0; }
days=$(( ($(date +%s) - mt) / 86400 ))
[ "$days" -le 8 ] || { devward_result "$ID" FAIL "The last KnockKnock scan is $days days old" "Check that the weekly security check runs (BL-AU-02)"; exit 0; }
devward_baseline_ready "$ID" "$B" "the scan" || exit 0
base="$(devward_knockknock_paths "$B")" || { devward_result "$ID" ERROR "Could not read your baseline" "The baseline is not valid JSON"; exit 0; }
cur="$(devward_knockknock_paths "$K/latest.json")" || { devward_result "$ID" ERROR "Could not read the latest scan" "The scan is not valid JSON"; exit 0; }
[ -n "$cur" ] || { devward_result "$ID" ERROR "The scan lists no autostart items" "The latest scan has no items at all; run the weekly check again"; exit 0; }
new="$(devward_baseline_new <(printf '%s\n' "$base") "$cur")"
n="$(devward_count "$new")"
if [ "$n" -eq 0 ]; then devward_result "$ID" PASS "No new autostart items since your baseline (scan $days day(s) old)"
else devward_result "$ID" FAIL "$n new autostart item(s) since your baseline" "New: $(devward_join "$(printf '%s\n' "$new" | head -5 | while IFS= read -r p; do basename "$p"; done)" ', ')"; fi
