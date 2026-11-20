#!/bin/bash
. "$(dirname "$0")/../lib/common.sh"
. "$(dirname "$0")/../lib/apps.sh"
. "$(dirname "$0")/../lib/agents.sh"
ID=BL-AI-03
dirs="$(fortkeep_claude_dirs)"; cx=""; fortkeep_codex_present && cx=1
if [ -z "$dirs" ] && [ -z "$cx" ]; then
  if fortkeep_claude_private_skipped; then fortkeep_claude_excluded_error "$ID"; else fortkeep_result "$ID" NA "Neither Claude Code nor Codex is set up on this Mac"; fi
  exit 0
fi
rcfiles=".zshrc .zprofile .zshenv .zlogin .bashrc .bash_profile .config/fortkeep/path-front.sh"
m="$(fortkeep_managed_settings)"
phys() {  # PATH — the same path with its folder's symlinks resolved, when that folder exists
  local d; d="$(dirname "$1")"
  case "$d" in *[*?[]*) return 0 ;; esac
  [ -d "$d" ] && printf '%s/%s\n' "$(cd "$d" && pwd -P)" "$(basename "$1")"
  return 0
}
deny_rules() {  # SETTINGS BASE — its Edit deny rules as absolute glob patterns
  jq -r '.permissions.deny // [] | .[] | strings | select(test("^Edit\\(.+\\)$"))' "$1" 2>/dev/null \
    | while IFS= read -r r; do
        p="${r#*(}"; p="${p%)}"
        case "$p" in
          '~'/*) p="$HOME/${p#\~/}" ;;
          '//'*) p="${p#/}" ;;
          /*) p="$2$p" ;;
          *) continue ;;
        esac
        p="${p//\*\*/*}"; printf '%s\n' "$p"
        phys "$p"
      done
}
covered() {  # FILE RULES — true if a deny rule matches FILE, as named or by its real path
  local pat real
  real="$(phys "$1")"
  while IFS= read -r pat; do
    [ -n "$pat" ] || continue
    # shellcheck disable=SC2254 # deny rules are glob patterns on purpose
    case "$1" in $pat) return 0 ;; esac
    # shellcheck disable=SC2254
    [ -n "$real" ] && case "$real" in $pat) return 0 ;; esac
  done <<EOF
$2
EOF
  return 1
}
good_json() { jq -e 'type == "object"' "$1" >/dev/null 2>&1; }
mrules=""; mbad=0
if [ -f "$m" ]; then
  if good_json "$m"; then mrules="$(deny_rules "$m" "$(dirname "$m")")"; else mbad=1; fi
fi
total=0; good=0; missing=""; cmissing=""; undecided=""; priv=""
[ "$mbad" -eq 0 ] || [ -z "$dirs" ] || undecided=" managed settings"
while IFS= read -r d; do
  [ -n "$d" ] || continue
  s="$d/settings.json"
  rules="$mrules"; need="$s"; hl=""
  if [ -f "$s" ]; then
    if good_json "$s" && hl="$(fortkeep_bash_hooks "$s")"; then rules="$rules"$'\n'"$(deny_rules "$s" "$d")"
    else undecided="$undecided $(fortkeep_tilde "$d")"; continue; fi
  fi
  for f in $rcfiles; do
    [ -f "$HOME/$f" ] && need="$need"$'\n'"$HOME/$f"
  done
  while IFS= read -r h; do
    [ -n "$h" ] || continue
    exe="$(fortkeep_hook_script "$h")"; [ -n "$exe" ] && need="$need"$'\n'"$exe"
  done <<EOF
$hl
EOF
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    total=$((total + 1))
    if covered "$f" "$rules"; then good=$((good + 1)); else missing="$missing"$'\n'"$(fortkeep_tilde "$f")"; fi
  done <<EOF
$need
EOF
done <<EOF
$dirs
EOF
# Codex has no deny rules: its apply_patch hooks must refuse an edit to each file that controls it.
if [ -n "$cx" ]; then
  while IFS= read -r d; do
    [ -n "$d" ] || continue
    [ "$d" != '!skipped' ] || { priv=" (a private folder was excluded)"; continue; }
    hj="$d/hooks.json"; hw=""; need="$hj"$'\n'"$d/config.toml"
    if [ -f "$hj" ]; then
      if good_json "$hj" && hw="$(fortkeep_tool_hooks "$hj" apply_patch)" && s="$(fortkeep_hook_scripts "$hj")"; then need="$need"$'\n'"$s"
      else undecided="$undecided $(fortkeep_tilde "$d")"; continue; fi
    fi
    for f in "$d"/rules/*.rules; do [ -f "$f" ] && need="$need"$'\n'"$f"; done
    for f in $rcfiles; do [ -f "$HOME/$f" ] && need="$need"$'\n'"$HOME/$f"; done
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      total=$((total + 1)); r=1
      [ -z "$hw" ] || { fortkeep_hooks_refuse "$hw" apply_patch "$f"; r=$?; }
      case "$r" in
        0) good=$((good + 1)) ;;
        2) undecided="$undecided $(fortkeep_tilde "$d") (a hook timed out)"; break ;;
        *) cmissing="$cmissing"$'\n'"$(fortkeep_tilde "$f")" ;;
      esac
    done <<EOF
$(printf '%s\n' "$need" | awk 'NF && !s[$0]++')
EOF
  done <<EOF
$(fortkeep_codex_dirs)
EOF
fi
ev="$good of $total agent control files are protected from agent edits"
list() { printf '%s\n' "$1" | sed '/^$/d' | awk '!s[$0]++' | paste -sd, - | sed 's/,/, /g'; }
note=""
[ -z "$missing" ] || note="Add Edit(…) deny rules for: $(list "$missing")"
[ -z "$cmissing" ] || note="${note:+$note. }Make the apply_patch guard in Codex's hooks.json refuse edits to: $(list "$cmissing")"
note="$(fortkeep_claude_note "$note")$priv"; note="${note# }"
if [ -n "$missing$cmissing" ]; then
  [ -z "$undecided" ] || note="$note. Could not read settings in:$undecided"
  fortkeep_result "$ID" FAIL "$ev" "$note"
elif [ -n "$undecided" ]; then fortkeep_result "$ID" ERROR "$ev" "Could not read these settings (invalid JSON or a bad hook matcher):$undecided${note:+. $note}"
elif [ -n "$priv" ] && [ "$total" -eq 0 ]; then fortkeep_result "$ID" ERROR "$ev" "$note"
else fortkeep_result "$ID" PASS "$ev" "$note"; fi
