#!/bin/bash
# Source it, don't run it. One-use approval tokens: the approval hook writes reports/.approvals/<ID>.<action> when the
# person answers Apply, Undo or Accept <ID> or Add private folder, and the script that acts on the answer consumes the
# token here. A private-folder token holds the folder its question named, an accept token the reason.
FORTKEEP_APPROVAL_TTL=300  # seconds an answer stays good for; set here, never by the caller

fortkeep_take_approval() {  # DIR ID ACTION [SUBJECT] — consumes a fresh token from DIR, made for SUBJECT when given, or
  # prints why not (never SUBJECT, which can be a private folder) and returns 1
  local tok="$1/$2.$3" age held="" what=folder
  if [ ! -f "$tok" ]; then echo "REFUSED: no approval for $2 $3. Ask the person first." >&2; return 1; fi
  age=$(( $(/bin/date +%s) - $(/usr/bin/stat -f %m "$tok") ))
  [ $# -lt 4 ] || held="$(/bin/cat "$tok")"
  /bin/rm -f "$tok"
  if [ "$age" -lt 0 ] || [ "$age" -gt "$FORTKEEP_APPROVAL_TTL" ]; then
    echo "REFUSED: approval for $2 $3 expired (${age}s old). Ask again." >&2; return 1
  fi
  if [ $# -ge 4 ] && [ "$held" != "$4" ]; then
    [ "$3" != accept ] || what=reason
    echo "REFUSED: the person's answer was for another $what. Ask again, naming this one." >&2; return 1
  fi
}
