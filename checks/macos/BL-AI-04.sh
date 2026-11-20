#!/bin/bash
. "$(dirname "$0")/../lib/common.sh"
. "$(dirname "$0")/../lib/apps.sh"
. "$(dirname "$0")/../lib/agents.sh"
. "$(dirname "$0")/../lib/editors.sh"
ID=BL-AI-04
m="$(fortkeep_managed_settings)"
claude=""; { [ -n "$(fortkeep_claude_dirs)" ] || [ -f "$m" ]; } && claude=1
cx=""; fortkeep_codex_present && cx=1
if [ -z "$claude" ] && [ -z "$cx" ]; then
  if fortkeep_claude_private_skipped; then fortkeep_claude_excluded_error "$ID"; else fortkeep_result "$ID" NA "Neither Claude Code nor Codex is set up on this Mac"; fi
  exit 0
fi
[ -z "$claude" ] || [ -f "$m" ] || { fortkeep_result "$ID" FAIL "No managed settings file" "$(fortkeep_claude_note "The root-owned copy goes in /Library/Application Support/ClaudeCode/managed-settings.json")"; exit 0; }
# Unreadable contents leave the rules undecided; ownership and Codex are still checked, and a FAIL there wins.
undecided=""; json=1
[ -n "$claude" ] || json=0
[ "$json" -eq 0 ] || jq -e 'type == "object"' "$m" >/dev/null 2>&1 || { undecided="managed-settings.json is not valid JSON"; json=0; }
if [ "$json" -eq 1 ]; then
  hooks="$(fortkeep_bash_hooks "$m")" || { undecided="Managed settings: couldn't read the hooks in them (a bad matcher?)"; json=0; }
fi
rootonly() {  # PATH — owned by root and not writable by group or others
  local o p
  o="$(stat -L -f %Su "$1" 2>/dev/null)"; p="$(stat -L -f %Sp "$1" 2>/dev/null)"
  [ "$o" = root ] && [ "${p:5:1}" != w ] && [ "${p:8:1}" != w ]
}
rootchain() {  # PATH — it and every folder above it, as named and with symlinks resolved, pass rootonly
  # Whoever can write any folder on the way (Homebrew's /usr/local on Intel Macs) can swap what's below it.
  local p s
  for s in "$1" "$(fortkeep_realpath "$1")" "$(fortkeep_realpath "$(dirname "$1")")"; do
    case "$s" in /*) p="$s" ;; *) return 1 ;; esac
    while :; do rootonly "$p" || return 1; [ "$p" = / ] && break; p="$(dirname "$p")"; done
  done
}
codex_modes() {  # REQUIREMENTS_TOML — ok, missing or danger: its top-level allowed_sandbox_modes, which may span lines
  [ -r "$1" ] || return 1  # nothing printed: undecided
  fortkeep_strip_hash_comments "$1" | perl -0777 -ne '
    s{^[ \t]*\[.*}{}ms;  # top level only: the text before the first [table] header
    /^[ \t]*allowed_sandbox_modes[ \t]*=[ \t]*\[((?:"(?:\\.|[^"\\])*"|\x27[^\x27]*\x27|[^"\x27\]])*)\]/m or do { print "missing"; exit };
    print $1 =~ /["\x27]danger-full-access["\x27]/ ? "danger" : "ok"'
}
bad=""; priv=""
[ -z "$claude" ] || rootchain "$m" || bad="$bad The file or a folder above it isn't root-owned and read-only for you."
if [ "$json" -eq 1 ]; then
  [ "$(jq -r '.permissions.disableBypassPermissionsMode // ""' "$m")" = disable ] || bad="$bad It doesn't disable bypass mode."
  if [ -z "$hooks" ]; then bad="$bad It has no pre-command hook."
  else
    while IFS= read -r h; do
      [ -n "$h" ] || continue
      exe="$(fortkeep_hook_script "$h")"
      case "$exe" in "$HOME"/*) bad="$bad A hook script is inside your home folder."; continue ;; esac
      { [ -n "$exe" ] && rootchain "$exe"; } || bad="$bad A hook script, or a folder above it, is missing or not root-owned."
    done <<EOT
$hooks
EOT
  fi
fi
# Updating only your own copy of a guard leaves the root copy stale: the same file name must mean the same bytes.
typed() {  # PATH — quoted for the person to type, a home path as ~/ outside the quoting
  # shellcheck disable=SC2088 # a literal ~ for the person to type, followed by the quoted rest of the path
  case "$1" in "$HOME"/*) printf '~/%q' "${1#"$HOME"/}" ;; *) printf '%q' "$1" ;; esac
}
if [ "$json" -eq 1 ] && [ -n "$hooks" ]; then
  mine=""
  while IFS= read -r d; do
    [ -n "$d" ] && [ -f "$d/settings.json" ] || continue
    s="$(fortkeep_hook_scripts "$d/settings.json" Bash Write)" || { undecided="${undecided:+$undecided; }couldn't read the hooks in $(fortkeep_tilde "$d")/settings.json"; continue; }
    mine="$mine"$'\n'"$s"
  done <<EOT
$(fortkeep_claude_dirs)
EOT
  while IFS= read -r rs; do
    [ -n "$rs" ] || continue
    while IFS= read -r us; do
      [ -n "$us" ] && [ "$us" != "$rs" ] && [ "${us##*/}" = "${rs##*/}" ] || continue
      if fortkeep_is_private "$us"; then fortkeep_claude_private_skipped || priv=" (a private folder was excluded)"; continue; fi
      cmp -s "$rs" "$us"; rc=$?
      [ "$rc" -eq 0 ] && continue
      if [ "$rc" -ne 1 ]; then undecided="${undecided:+$undecided; }couldn't compare $(fortkeep_tilde "$us") with its root-owned copy"; continue; fi
      # Your copy is the one anything running as you can change, so it is never the source of a root copy: this
      # repo's template of the same name is, and without one the person compares the two first.
      u="$(typed "$us")"; r="$(printf '%q' "${rs#"$FORTKEEP_SYSROOT"}")"; tpl="$FORTKEEP_REPO/templates/${rs##*/}"
      if [ -f "$tpl" ] && cmp -s "$tpl" "$rs"; then
        bad="$bad Your copy of ${rs##*/} differs from the root-owned one, which matches this repo's template: replace yours with the template. In the Terminal app, type: install -m 755 $(typed "$tpl") $u"
      elif [ -f "$tpl" ]; then
        bad="$bad The root-owned copy of ${rs##*/} differs from this repo's template: re-copy the template. In the Terminal app, type: sudo install -o root -g wheel -m 755 $(typed "$tpl") $r"
        cmp -s "$tpl" "$us" || bad="$bad, then update your copy from it: install -m 755 $(typed "$tpl") $u"
      else
        bad="$bad The root-owned copy of ${rs##*/} differs from your copy. Anything running as you can change your copy, so compare them first: diff $r $u. Only when you have checked your copy, re-copy it in the Terminal app: sudo install -o root -g wheel -m 755 $u $r"
      fi
    done <<EOT
$(printf '%s\n' "$mine" | awk 'NF && !s[$0]++')
EOT
  done <<EOT
$(fortkeep_hook_scripts "$m" Bash Write)
EOT
fi
if [ -n "$cx" ]; then
  r="$(fortkeep_path /etc/codex/requirements.toml)"
  if [ -f "$r" ] && rootchain "$r"; then
    case "$(codex_modes "$r")" in
      ok) ;;
      missing) bad="$bad /etc/codex/requirements.toml doesn't set allowed_sandbox_modes = [\"read-only\", \"workspace-write\"]." ;;
      danger) bad="$bad /etc/codex/requirements.toml lets Codex run with danger-full-access: allow only \"read-only\" and \"workspace-write\"." ;;
      *) undecided="${undecided:+$undecided; }couldn't read /etc/codex/requirements.toml" ;;
    esac
  else bad="$bad Codex is installed without a root-owned /etc/codex/requirements.toml."; fi
fi
if [ -z "$claude" ]; then ok="Root-owned /etc/codex/requirements.toml limits Codex to sandboxed modes"; what="The root-owned Codex requirements are incomplete"
else ok="Root-owned managed settings with bypass disabled and a root-owned guard"; what="Managed settings found, but incomplete"; fi
if [ -n "$bad" ]; then fortkeep_result "$ID" FAIL "$what" "$(fortkeep_claude_note "${bad# }${undecided:+ Also: $undecided.}$priv")"
elif [ -n "$undecided" ]; then fortkeep_result "$ID" ERROR "$undecided" "$(fortkeep_claude_note "${priv# }")"
else fortkeep_result "$ID" PASS "$ok" "$(fortkeep_claude_note "${priv# }")"; fi
