#!/bin/bash
# Records the person's deliberate decision to leave a control unmet: right after their Accept <ID> answer to the
# question naming this reason (checks/ask.sh ID accept "reason", recorded by the approval hook), or typed by them in a
# terminal app. Taking a decision back needs neither.
# Usage: checks/accept.sh ID "reason" | --remove ID
. "$(dirname "$0")/lib/common.sh"
. "$(dirname "$0")/lib/agent.sh"
. "$(dirname "$0")/lib/approval.sh"
APPROVALS="$(cd "$(dirname "$0")/.." && pwd -P)/reports/.approvals"  # from this file's place, never the environment
CONTROLS="${FORTKEEP_CONTROLS:-$FORTKEEP_REPO/controls/controls.json}"
ACCEPTED="${FORTKEEP_ACCEPTED:-$FORTKEEP_REPO/accepted.json}"
usage() { echo "usage: $0 ID \"reason\" | --remove ID" >&2; exit 2; }
known() { jq -e --arg id "$1" 'any(.[]; .id == $id)' "$CONTROLS" >/dev/null; }
[ -f "$ACCEPTED" ] || echo '{}' > "$ACCEPTED"
tmp="$ACCEPTED.tmp"
case "${1:-}" in
  --remove)
    [ -n "${2:-}" ] || usage
    jq --arg id "$2" 'del(.[$id])' "$ACCEPTED" > "$tmp" && mv "$tmp" "$ACCEPTED"
    echo "removed $2" ;;
  ''|-*) usage ;;
  *)
    [ -n "${2:-}" ] || usage
    fortkeep_accept_reason "$2" || { echo "give the reason as one line of at most 300 characters, without backslashes" >&2; exit 2; }
    known "$1" || { echo "unknown control: $1" >&2; exit 2; }
    # /bin/ps is fixed here on purpose: no environment variable may switch the person check off.
    fortkeep_is_person /bin/ps || fortkeep_take_approval "$APPROVALS" "$1" accept "$2" || exit 4
    jq --arg id "$1" --arg r "$2" --arg d "$(date -u +%F)" '.[$id] = {reason: $r, date: $d}' "$ACCEPTED" > "$tmp" && mv "$tmp" "$ACCEPTED"
    echo "accepted $1" ;;
esac
