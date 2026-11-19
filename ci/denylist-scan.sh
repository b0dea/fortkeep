#!/bin/bash
# Fails if tracked (or staged) files contain a denylisted term: one you never want committed, such as an employer
# or client name. The list lives outside the repo, one term per line; `make scan-private` and `make release` run it.
# Usage: ci/denylist-scan.sh [--staged]   Exit: 0 clean, 1 hits or no terms, 2 scan error.
cd "$(dirname "$0")/.." || exit 1
list="${DEVWARD_DENYLIST:-$HOME/.config/devward/denylist}"
if [ ! -s "$list" ]; then echo "denylist-scan: no denylist at $list" >&2; exit 1; fi
terms="$(mktemp)" || exit 2
trap 'rm -f "$terms"' EXIT
grep -E -v '^[[:space:]]*(#|$)' "$list" > "$terms"
if [ ! -s "$terms" ]; then echo "denylist-scan: denylist has no terms" >&2; exit 1; fi
where=(); [ "${1:-}" = --staged ] && where=(--cached)
skip=(); [ -e ci/markers.b64 ] && skip=(':!ci/markers.b64')
out="$(git grep ${where[@]+"${where[@]}"} -n -i -I -F -f "$terms" -- . ${skip[@]+"${skip[@]}"})"
rc=$?
if [ "$rc" -eq 0 ]; then
  echo "denylist-scan: denylisted terms found at:"; echo "$out" | cut -d: -f1,2; exit 1
elif [ "$rc" -ne 1 ]; then
  echo "denylist-scan: scan failed" >&2; exit 2
fi
echo "denylist-scan: clean"
