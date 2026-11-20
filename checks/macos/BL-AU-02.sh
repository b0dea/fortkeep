#!/bin/bash
. "$(dirname "$0")/../lib/common.sh"
. "$(dirname "$0")/../lib/launchd.sh"
ID=BL-AU-02
L=io.github.b0dea.fortkeep.weekly
[ -f "$HOME/Library/LaunchAgents/$L.plist" ] || { fortkeep_result "$ID" FAIL "No weekly security check job" "The agent can install one"; exit 0; }
fortkeep_agent_loaded "$L" || { fortkeep_result "$ID" FAIL "The weekly security check is installed but not loaded" "Log out and back in, or run its fix again"; exit 0; }
# weekly-last is touched by checks/weekly.sh only, so a manual review never hides a dead job.
# weekly.sh sets FORTKEEP_WEEKLY_RUN while its own review runs, so the run that ends a gap isn't flagged.
[ -z "${FORTKEEP_WEEKLY_RUN:-}" ] || { fortkeep_result "$ID" PASS "The weekly review is running now"; exit 0; }
last="$FORTKEEP_REPORTS/weekly-last"; never=""
[ -e "$last" ] || { last="$HOME/Library/LaunchAgents/$L.plist"; never=1; }
t="$(stat -f %m "$last" 2>/dev/null)"
case "$t" in ''|*[!0-9]*) fortkeep_result "$ID" ERROR "Could not tell when the weekly review last ran" "Could not read the date of the weekly-last file or the job"; exit 0 ;; esac
days=$(( ($(date +%s) - t) / 86400 ))
if [ -n "$never" ]; then
  if [ "$days" -gt 8 ]; then fortkeep_result "$ID" FAIL "The weekly job was installed $days days ago and has never completed a review" "See ~/Library/Logs/fortkeep-weekly.log"
  else fortkeep_result "$ID" PASS "Weekly security check installed and loaded" "It has not completed its first review yet"; fi
elif [ "$days" -gt 8 ]; then fortkeep_result "$ID" FAIL "The weekly check is overdue: the last review was $days days ago" "See ~/Library/Logs/fortkeep-weekly.log"
else fortkeep_result "$ID" PASS "Weekly security check installed and loaded; last review $days day(s) ago"; fi
