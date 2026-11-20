#!/bin/bash
. "$(dirname "$0")/../lib/common.sh"
. "$(dirname "$0")/../lib/launchd.sh"
ID=BL-AU-01
# fortkeep's own weekly job (BL-AU-02's) only reports and never upgrades, though its notification names
# `brew upgrade`: it is skipped by its label and by this repo's launcher and script, under either spelling of the path.
rp="$(cd "$FORTKEEP_REPO" 2>/dev/null && pwd -P)"
own() {  # PATH — true for this repo's weekly launcher or script
  case "$1" in "$FORTKEEP_REPO"/checks/fortkeep-weekly|"$FORTKEEP_REPO"/checks/weekly.sh|"$rp"/checks/fortkeep-weekly|"$rp"/checks/weekly.sh) return 0 ;; esac
  return 1
}
agents="$(fortkeep_user_agents)" || { fortkeep_result "$ID" ERROR "Could not check the weekly jobs" "a private folder was excluded"; exit 0; }
found=""; unloaded=""; unread=""; priv=""
while IFS="$(printf '\t')" read -r l p; do
  [ -n "$l" ] || continue
  [ "$l" != io.github.b0dea.fortkeep.weekly ] || continue
  fortkeep_agent_weekly "$p" || continue
  c="$(fortkeep_agent_command "$p")"
  if [ -n "$c" ]; then
    printf '%s\n' "$c" | grep -Eqs 'brew[[:space:]]+upgrade' || continue
  else
    s="$(fortkeep_agent_script "$p")"
    case "$s" in '~'/*) s="$HOME/${s#\~/}" ;; esac
    own "$s" && continue
    if [ -n "$s" ] && fortkeep_is_private "$s"; then priv=" (a private folder was excluded)"; continue; fi
    [ -f "$s" ] || continue
    if [ ! -r "$s" ]; then unread="$unread, $l"; continue; fi
    grep -Eqs 'brew[[:space:]]+upgrade' "$s" || continue
  fi
  if fortkeep_agent_loaded "$l"; then found="$found, $l"; else unloaded="$unloaded, $l"; fi
done <<EOF
$agents
EOF
if [ -n "$found" ]; then fortkeep_result "$ID" PASS "Weekly update job: ${found#, }" "${priv# }"
elif [ -n "$unread" ]; then fortkeep_result "$ID" ERROR "Could not read the script of the weekly job: ${unread#, }" "Check the script's permissions$priv"
elif [ -n "$priv" ]; then fortkeep_result "$ID" ERROR "Could not check every weekly job's script" "${priv# }"
elif [ -n "$unloaded" ]; then fortkeep_result "$ID" FAIL "A weekly update job exists but is not loaded: ${unloaded#, }" "Log out and back in, or load it with launchctl bootstrap gui/$(id -u) <its plist>"
else fortkeep_result "$ID" FAIL "No weekly job that runs brew upgrade" "fortkeep's own weekly check only reports, it never upgrades; see the lesson for a ready-made job"; fi
