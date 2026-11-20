#!/bin/bash
# SessionStart: greeting, last run, and whether this copy is exactly a signed release with nothing changed.
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="${CLAUDE_PROJECT_DIR:-$(cd "$HERE/../.." && pwd)}"
REPORTS="${FORTKEEP_REPORTS:-$REPO/reports}"
. "$HERE/../../checks/lib/repo.sh"
input=""
[ -t 0 ] || input="$(cat)"
say() { jq -n --arg m "$1" '{systemMessage: $m, hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $m}}'; }
if fortkeep_dev_session; then
  say "fortkeep development session (FORTKEEP_DEV=1, and the marker ~/.config/fortkeep/dev is present): the guards are the development deny-list, not a person's allow-list. Read CONTRIBUTING.md before changing anything."
  exit 0
fi
last="no previous run on this Mac"
if [ -f "$REPORTS/latest/results.json" ]; then
  last="last run $(jq -r '.run' "$REPORTS/latest/results.json"): $(jq -r '.results | group_by(.status) | map("\(.[0].status) \(length)") | join(", ")' "$REPORTS/latest/results.json")"
fi
warn=""
if fortkeep_verify_release "$REPO"; then
  if old="$(fortkeep_downgrade_from "$FORTKEEP_RELEASE_TAG")"; then
    warn=" WARNING: this copy is $FORTKEEP_RELEASE_TAG, older than $old, which this Mac ran before. Suggest updating with checks/update.sh in the Terminal app unless the person went back on purpose."
  elif ! err="$(fortkeep_note_release "$FORTKEEP_RELEASE_TAG" "$REPO" 2>&1 >/dev/null)"; then
    # Without the record, a later downgrade isn't noticed and the next release's signers aren't taken on.
    err="${err##*$'\n'}"  # its last line says what failed, in words; any line above is the shell's own error
    warn=" WARNING: fortkeep could not record this release as run on this Mac (${err:-no reason given}), so it can't warn about an older copy later. Ask the person to check that their ~/.config/fortkeep folder can be written."
  fi
else
  warn=" WARNING: this copy of fortkeep is not exactly a signed release: $FORTKEEP_RELEASE_PROBLEM. Results may not be trustworthy. Don't run fixes; reinstall a signed release unless you made these changes yourself."
fi
# Claude Code (and Codex) name the session's permission mode; in these, a fix could run without the person's prompt.
mode="$(jq -r '.permission_mode // empty' 2>/dev/null <<<"$input")"
case "$mode" in
  bypassPermissions|acceptEdits|auto)
    warn="$warn WARNING: the agent is in $mode mode, so fixes are refused until the person switches back to the default mode (shift+tab in Claude Code)." ;;
esac
[ "${FORTKEEP_DEV:-}" != 1 ] || warn="$warn FORTKEEP_DEV=1 is set, but a development session also needs the file ~/.config/fortkeep/dev, which is missing: this is a person's session."
say "fortkeep checks and hardens this Mac against fortkeep's baseline.$warn ($last.) Type /posture to start (in Codex, \$posture)."
