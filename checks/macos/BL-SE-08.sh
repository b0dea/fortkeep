#!/bin/bash
. "$(dirname "$0")/../lib/common.sh"
. "$(dirname "$0")/../lib/agents.sh"
ID=BL-SE-08
case "$(tmutil destinationinfo 2>&1)" in *"No destinations configured"*|'') fortkeep_result "$ID" NA "Time Machine is not set up"; exit 0 ;; esac
targets="$(fortkeep_claude_dirs | sed 's#$#/projects#')"$'\n'"$HOME/.codex/sessions"$'\n'"$HOME/.local/share/opencode"
total=0; inc=""; err=""
while IFS= read -r t; do
  [ -n "$t" ] && [ -d "$t" ] || continue
  total=$((total + 1))
  out="$(tmutil isexcluded "$t" 2>/dev/null)"; rc=$?
  if [ "$rc" -ne 0 ]; then err="$err $(fortkeep_tilde "$t")"
  else
    case "$out" in
      *"[Excluded]"*) ;;
      *"[Included]"*) inc="$inc $(fortkeep_tilde "$t")" ;;
      *) err="$err $(fortkeep_tilde "$t")" ;;
    esac
  fi
done <<EOT
$targets
EOT
if [ "$total" -eq 0 ] && fortkeep_claude_private_skipped; then fortkeep_claude_excluded_error "$ID"
elif [ "$total" -eq 0 ]; then fortkeep_result "$ID" NA "No AI-agent transcript folders"
elif [ -n "$inc" ]; then fortkeep_result "$ID" FAIL "Agent transcripts are backed up by Time Machine" "$(fortkeep_claude_note "Included:$inc")"
elif [ -n "$err" ]; then fortkeep_result "$ID" ERROR "Could not ask Time Machine about:$err" "$(fortkeep_claude_note "tmutil isexcluded failed")"
else fortkeep_result "$ID" PASS "All $total agent transcript folders are excluded from Time Machine" "$(fortkeep_claude_note "")"; fi
