#!/bin/bash
# Source it, don't run it. One-use approval tokens: the approval hook writes reports/.approvals/<ID>.<action> when the
# person answers Apply, Undo or Accept <ID> or Add private folder, and the script that acts on the answer consumes the
# token here. A private-folder token holds the folder its question named, an accept token the reason.
FORTKEEP_APPROVAL_TTL=300  # seconds an answer stays good for; set here, never by the caller

fortkeep_take_approval() {  # DIR ID ACTION [SUBJECT] — consumes a fresh token from DIR, made for SUBJECT when given, or
  # prints why not (never SUBJECT, which can be a private folder) and returns 1. Every failure returns 1: an unchecked
  # expansion error would make bash abandon the caller's whole command, its `|| exit 4` included.
  local tok="$1/$2.$3" claimed="$1/$2.$3.$$" mtime="" now="" age held="" what=folder
  # Claim it by renaming: when two runs take one token at once, only one rename succeeds.
  if ! /bin/mv "$tok" "$claimed" 2>/dev/null; then
    echo "REFUSED: no approval for $2 $3. Ask the person first." >&2; return 1
  fi
  if [ -f "$claimed" ]; then
    mtime="$(/usr/bin/stat -f %m "$claimed" 2>/dev/null)" || mtime=""
    now="$(/bin/date +%s)" || now=""
    if [ $# -ge 4 ]; then held="$(/bin/cat "$claimed" 2>/dev/null)" || held=""; fi
  fi
  /bin/rm -f "$claimed"
  case "${mtime:-x}${now:-x}" in *[!0-9]*)
    echo "REFUSED: could not read the approval for $2 $3. Ask again." >&2; return 1 ;;
  esac
  age=$(( now - mtime ))
  if [ "$age" -lt 0 ] || [ "$age" -gt "$FORTKEEP_APPROVAL_TTL" ]; then
    echo "REFUSED: approval for $2 $3 expired (${age}s old). Ask again." >&2; return 1
  fi
  if [ $# -ge 4 ] && [ "$held" != "$4" ]; then
    [ "$3" != accept ] || what=reason
    echo "REFUSED: the person's answer was for another $what. Ask again, naming this one." >&2; return 1
  fi
}
