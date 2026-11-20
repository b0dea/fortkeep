#!/bin/bash
# Prints the root-owned files the BL-AI-04 lesson installs, taken from the verified release, never the working tree.
#   checks/managed-settings.sh        templates/managed-settings.json, plus a deny rule for the settings.json of every
#                                     Claude Code config folder other than ~/.claude (CLAUDE_CONFIG_DIR)
#   checks/managed-settings.sh guard  templates/agent-guard.sh
# Read-only.
SELF="$(cd "$(dirname "$0")/.." && pwd)"
. "$SELF/checks/lib/repo.sh"
fortkeep_release_gate "$SELF" || exit 4
. "$(dirname "$0")/lib/common.sh"
. "$(dirname "$0")/lib/agents.sh"
release_file() {  # PATH — the file as the release has it; the working tree only in a development session
  if [ -n "${FORTKEEP_RELEASE_TAG:-}" ]; then fortkeep_git "$SELF" cat-file blob "$FORTKEEP_RELEASE_TAG:$1"
  else cat "$SELF/$1"; fi
}
case "${1:-}" in
  guard) release_file templates/agent-guard.sh; exit ;;
  '') ;;
  *) echo "usage: $0 [guard]" >&2; exit 2 ;;
esac
home="$( (cd "$HOME/.claude" 2>/dev/null && pwd -P) || true)"
extra="$(fortkeep_claude_dirs | while IFS= read -r d; do [ "$d" = "$home" ] || printf 'Edit(/%s/settings.json)\n' "$d"; done)"
template="$(release_file templates/managed-settings.json)" || { echo "could not read templates/managed-settings.json" >&2; exit 1; }
jq --arg x "$extra" '.permissions.deny += ($x | split("\n") | map(select(. != "")))' <<<"$template"
