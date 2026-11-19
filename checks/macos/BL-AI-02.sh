#!/bin/bash
. "$(dirname "$0")/../lib/common.sh"
. "$(dirname "$0")/../lib/apps.sh"
. "$(dirname "$0")/../lib/agents.sh"
ID=BL-AI-02
dirs="$(devward_claude_dirs)"; cx=""; devward_codex_present && cx=1
if [ -z "$dirs" ] && [ -z "$cx" ]; then
  if devward_claude_private_skipped; then devward_claude_excluded_error "$ID"; else devward_result "$ID" NA "Neither Claude Code nor Codex is set up on this Mac"; fi
  exit 0
fi
probes="$(devward_guard_probes)"
res=""; [ -z "$dirs" ] || res="$(devward_guard_folders "$probes")"
[ -z "$cx" ] || res="$res"$'\n'"$(devward_codex_guard "$probes")"
pick() { printf '%s\n' "$res" | sed -n "s/^$1 / /p" | tr -d '\n'; }  # KIND — its folders, each after a space
total="$(printf '%s\n' "$res" | grep -c '^folder ')"; good="$(printf '%s\n' "$res" | grep -c '^good ')"
weak="$(pick weak)"; offd="$(pick off)"; local_only="$(pick local)"; mflag="$(pick managed-flag)"; mflag="${mflag# }"
undecided="$(pick undecided)"; missing="$(pick missing)"
printf '%s\n' "$res" | grep -qx managed-bad && undecided=" managed settings$undecided"
priv=""; printf '%s\n' "$res" | grep -qx skipped && priv=" (a private folder was excluded)"
note=""
[ -n "$missing" ] && note="Codex is installed without a hooks.json in:$missing."
[ -n "$weak" ] && note="No working guard in:$weak. $note"
add() { note="${note:+${note% } }$1"; }
[ -n "$weak" ] && [ -n "$offd" ] && add "disableAllHooks switches off the folder's own hooks in:$offd."
[ -n "$weak" ] && [ -n "$local_only" ] && add "Hooks in settings.local.json don't count (Claude Code reads that file only inside a project):$local_only."
case "$mflag" in
  disableAllHooks) add "The managed settings set disableAllHooks, so no hook runs." ;;
  allowManagedHooksOnly) [ -n "$weak" ] && add "The managed settings set allowManagedHooksOnly, so only managed hooks count." ;;
esac
[ -n "$undecided" ] && note="${note:+$note }Could not decide (unreadable settings or plugin list, a bad hook matcher or a hook that timed out):$undecided."
note="$(devward_claude_note "${note% }")$priv"; note="${note# }"
ev="The guard refuses every test bypass in $good of $total agent config folders"
if [ -n "$weak" ] || [ -n "$missing" ]; then devward_result "$ID" FAIL "$ev" "$note"
elif [ -n "$undecided" ] || { [ -n "$priv" ] && [ "$total" -eq 0 ]; }; then devward_result "$ID" ERROR "$ev" "$note"
else devward_result "$ID" PASS "$ev" "$note"; fi
