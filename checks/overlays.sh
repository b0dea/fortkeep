#!/bin/bash
# Usage: checks/overlays.sh new | list. Read-only.
#   new   each overlay this Mac hasn't been offered yet, one JSON object per line ({"overlay": name, "suggested":
#         bool}), and nothing when there are none
#   list  every overlay's name, one per line
. "$(dirname "$0")/lib/common.sh"
CONTROLS="${FORTKEEP_CONTROLS:-$FORTKEEP_REPO/controls/controls.json}"
CONFIG="${FORTKEEP_CONFIG:-$FORTKEEP_REPORTS/config.json}"
if [ $# -ne 1 ] || { [ "$1" != new ] && [ "$1" != list ]; }; then echo "usage: $0 new | list" >&2; exit 2; fi
known="$(jq -c '[.[].layer | select(startswith("overlay:")) | ltrimstr("overlay:")] | unique' "$CONTROLS" 2>/dev/null)" \
  || { echo "could not read controls: $CONTROLS" >&2; exit 2; }
if [ "$1" = list ]; then jq -r '.[]' <<<"$known"; exit 0; fi
offered='[]'
if [ -f "$CONFIG" ]; then
  # A config from before `offered` existed counts its chosen overlays as offered.
  offered="$(jq -c '(.offered // .overlays // []) | [.[] | strings]' "$CONFIG" 2>/dev/null)" \
    || { echo "config.json is not valid JSON" >&2; exit 2; }
fi
new="$(jq -cn --argjson k "$known" --argjson o "$offered" '$k - $o')"
[ "$new" != '[]' ] || exit 0
suggest="$(/bin/bash "$(dirname "$0")/detect.sh" 2>/dev/null | jq -c '.suggest_overlays // []' 2>/dev/null)"
case "$suggest" in '['*) ;; *) suggest='[]' ;; esac
jq -c --argjson s "$suggest" '.[] | {overlay: ., suggested: (. as $n | $s | index($n) != null)}' <<<"$new"
