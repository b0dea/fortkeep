#!/bin/bash
. "$(dirname "$0")/../lib/common.sh"
. "$(dirname "$0")/../lib/apps.sh"
. "$(dirname "$0")/../lib/agents.sh"
. "$(dirname "$0")/../lib/editors.sh"
ID=BL-AI-06
dirs="$(fortkeep_claude_dirs)"; m="$(fortkeep_managed_settings)"
claude=""; { [ -n "$dirs" ] || [ -f "$m" ]; } && claude=1
cx=""; fortkeep_codex_present && cx=1
if [ -z "$claude" ] && [ -z "$cx" ]; then
  if fortkeep_claude_private_skipped; then fortkeep_claude_excluded_error "$ID"; else fortkeep_result "$ID" NA "Neither Claude Code nor Codex is set up on this Mac"; fi
  exit 0
fi
on() {  # FILE — 0 if sandbox.enabled is true, 1 if not, 2 if the file isn't a JSON object
  local v
  v="$(jq -r 'if type == "object" then (.sandbox.enabled == true) else error("x") end' "$1" 2>/dev/null)" || return 2
  [ "$v" = true ]
}
off=""; unread=""; priv=""; managed=""
if [ -n "$claude" ]; then
  if [ -f "$m" ]; then
    rc=0; on "$m" || rc=$?
    if [ "$rc" -eq 0 ]; then managed=on
    elif [ "$rc" -eq 1 ] && jq -e '(.sandbox | type) == "object" and (.sandbox | has("enabled"))' "$m" >/dev/null 2>&1; then
      managed=off; off=" managed settings (sandbox.enabled is set, but not to true), which win over every config folder"
    fi
    [ "$rc" -ne 2 ] || unread=" managed settings"
  fi
  if [ -z "$managed" ]; then
    [ -n "$dirs" ] || [ -n "$unread" ] || off=" managed settings"
    while IFS= read -r d; do
      [ -n "$d" ] || continue
      if [ -f "$d/settings.json" ]; then
        rc=0; on "$d/settings.json" || rc=$?
        [ "$rc" -ne 2 ] || { unread="$unread $(fortkeep_tilde "$d")"; continue; }
        [ "$rc" -ne 0 ] || continue
      fi
      off="$off $(fortkeep_tilde "$d")"
    done <<EOF
$dirs
EOF
  fi
fi
# Codex runs its commands in a sandbox unless config.toml's top-level sandbox_mode is danger-full-access.
seen=0
if [ -n "$cx" ]; then
  while IFS= read -r d; do
    [ -n "$d" ] || continue
    [ "$d" != '!skipped' ] || { priv=" (a private folder was excluded)"; continue; }
    seen=$((seen + 1)); c="$d/config.toml"; [ -e "$c" ] || continue
    [ -r "$c" ] || { unread="$unread $(fortkeep_tilde "$c")"; continue; }
    mode="$(fortkeep_strip_hash_comments "$c" | perl -0777 -ne 's{^[ \t]*\[.*}{}ms; print $1 if /^[ \t]*sandbox_mode[ \t]*=[ \t]*["\x27]([^"\x27]*)["\x27]/m')"
    [ "$mode" != danger-full-access ] || off="$off $(fortkeep_tilde "$c") (sandbox_mode = \"danger-full-access\")"
  done <<EOF
$(fortkeep_codex_dirs)
EOF
fi
note() { local n; n="$(fortkeep_claude_note "$1")$priv"; printf '%s' "${n# }"; }
if [ -n "$off" ]; then
  n="Off in:$off"; [ -z "$unread" ] || n="$n. Could not read:$unread"
  fortkeep_result "$ID" FAIL "Sandbox off" "$(note "$n")"
elif [ -n "$unread" ]; then fortkeep_result "$ID" ERROR "Could not read:$unread" "$(note "")"
elif [ -z "$claude" ] && [ "$seen" -eq 0 ]; then fortkeep_result "$ID" ERROR "Could not check Codex's settings" "a private folder was excluded"
elif [ "$managed" = on ]; then fortkeep_result "$ID" PASS "Sandbox on in the managed settings${cx:+ and in Codex}" "$(note "")"
else fortkeep_result "$ID" PASS "Sandbox on in every ${claude:+Claude Code config folder}${claude:+${cx:+ and }}${cx:+Codex config}" "$(note "")"; fi
