#!/bin/bash
# VS Code-family settings discovery, shared by the BL-RC-01 check and fix, and readers for JSON with comments and for # comments.
FORTKEEP_EDITORS='Code
Code - Insiders
VSCodium
Cursor
Windsurf'
fortkeep_editor_dirs() {  # each installed editor's User folder, private or not; never lists inside one
  local app base
  while IFS= read -r app; do
    base="$HOME/Library/Application Support/$app/User"
    [ -d "$base" ] && printf '%s\n' "$base"
  done <<EOF
$FORTKEEP_EDITORS
EOF
  return 0
}
fortkeep_editor_settings() {  # every settings file outside the private folders: the editor's own and each profile's
  local base pf
  while IFS= read -r base; do
    [ -n "$base" ] || continue
    fortkeep_is_private "$base" && continue  # never listed
    printf '%s\n' "$base/settings.json"
    fortkeep_is_private "$base/profiles" && continue  # never listed either
    for pf in "$base"/profiles/*/settings.json; do
      [ -f "$pf" ] && ! fortkeep_is_private "$pf" && printf '%s\n' "$pf"
    done
  done <<EOF
$(fortkeep_editor_dirs)
EOF
  return 0
}
fortkeep_editor_private_skipped() {  # true when a private folder holds, or sits inside, an editor's User folder
  local p base
  while IFS= read -r base; do
    [ -n "$base" ] || continue
    while IFS= read -r p; do
      [ -n "$p" ] || continue
      case "$p" in "$base"|"$base"/*) return 0 ;; esac
      case "$base" in "$p"/*) return 0 ;; esac
    done <<EOF2
$(fortkeep_private_list)
EOF2
  done <<EOF
$(fortkeep_editor_dirs)
EOF
  return 1
}

fortkeep_jsonc() {  # FILE — its JSON with comments and trailing commas removed (string-aware), as VS Code, Cursor and Zed write it
  perl -0777 -pe 's#("(?:\\.|[^"\\])*")|//[^\n]*|/\*.*?\*/#defined $1 ? $1 : ""#gse; s#("(?:\\.|[^"\\])*")|,(\s*[\}\]])#defined $1 ? $1 : $2#gse' "$1" 2>/dev/null
}

fortkeep_strip_hash_comments() {  # FILE — its text with # comments removed and quoted strings kept, as TOML and Codex rules are written
  perl -0777 -pe 's{("(?:\\.|[^"\\])*"|\x27(?:\\.|[^\x27\\])*\x27)|#[^\n]*}{defined $1 ? $1 : ""}ge' "$1" 2>/dev/null
}

# FILE → off|on|prompt|unset|error. Only top-level keys count.
fortkeep_auto_tasks() {
  local f="$1" json v
  [ -e "$f" ] || { echo unset; return; }
  [ -r "$f" ] || { echo error; return; }
  json="$(fortkeep_jsonc "$f")" || { echo error; return; }
  [ -n "$(printf '%s' "$json" | tr -d '[:space:]')" ] || { echo unset; return; }
  v="$(printf '%s' "$json" | jq -r 'if type == "object" then (."task.allowAutomaticTasks" | if type == "string" and length > 0 then . else "unset" end) else "unset" end' 2>/dev/null)" || { echo error; return; }
  echo "${v:-unset}"
}
