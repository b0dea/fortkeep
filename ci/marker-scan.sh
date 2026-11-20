#!/bin/bash
# Fails if any tracked (or staged) file contains a full malware marker. Markers are decoded only in memory.
# Usage: ci/marker-scan.sh [--staged]   (markers: $FORTKEEP_MARKERS, default ci/markers.b64)
# Exit: 0 clean, 1 hits or no markers, 2 scan error.
cd "$(dirname "$0")/.." || exit 1
markers="${FORTKEEP_MARKERS:-ci/markers.b64}"
if [ ! -s "$markers" ]; then echo "marker-scan: no markers file at $markers" >&2; exit 1; fi
decoded() { while IFS= read -r l; do [ -n "$l" ] && { printf '%s' "$l" | base64 --decode; echo; }; done < "$markers"; }
if [ -z "$(decoded | tr -d '[:space:]')" ]; then echo "marker-scan: no markers decoded" >&2; exit 1; fi
where=(); [ "${1:-}" = --staged ] && where=(--cached)
skip=(); [ -e ci/markers.b64 ] && skip=(':!ci/markers.b64')
out="$(git grep ${where[@]+"${where[@]}"} -n -I -F -f <(decoded) -- . ${skip[@]+"${skip[@]}"})"
rc=$?
if [ "$rc" -eq 0 ]; then
  echo "marker-scan: malware marker strings found at:"; echo "$out" | cut -d: -f1,2; exit 1
elif [ "$rc" -ne 1 ]; then
  echo "marker-scan: scan failed" >&2; exit 2
fi
echo "marker-scan: clean"
