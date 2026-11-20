#!/bin/bash
. "$(dirname "$0")/../lib/common.sh"
ID=BL-SC-05
pn="$(fortkeep_real_cmd pnpm)"; bn="$(fortkeep_real_cmd bun)"
if [ -z "$pn$bn" ]; then fortkeep_result "$ID" NA "pnpm and bun are not installed"; exit 0; fi
# pnpm 9 and older run install scripts by default: read the version of the package pnpm really runs.
ver=""
real="$(perl -MCwd=abs_path -e 'print abs_path($ARGV[0]) // ""' "$pn" 2>/dev/null)"
if [ -n "$pn" ] && [ -n "$real" ]; then
  d="$(dirname "$real")"
  for _ in 1 2 3 4 5; do
    if [ "$(jq -r '.name // empty' "$d/package.json" 2>/dev/null)" = pnpm ]; then
      ver="$(jq -r '.version // empty' "$d/package.json" 2>/dev/null)"; break
    fi
    d="$(dirname "$d")"
  done
fi
major="${ver%%.*}"; vnum=""
case "$major" in ''|*[!0-9]*) ;; *) vnum=1 ;; esac
old=""; [ -n "$vnum" ] && [ "$major" -lt 10 ] && old="$ver"
bad=""; unread=""
for f in "$HOME/.npmrc" "$HOME/Library/Preferences/pnpm/rc" "${XDG_CONFIG_HOME:-$HOME/.config}/pnpm/rc"; do
  [ -e "$f" ] || continue
  [ -r "$f" ] || { unread="$unread $(fortkeep_tilde "$f")"; continue; }
  grep -Eiq '^[[:space:]]*dangerously-allow-all-builds[[:space:]]*=[[:space:]]*true' "$f" && bad="$bad $(fortkeep_tilde "$f")"
done
tools=""; [ -n "$pn" ] && tools=pnpm
[ -n "$bn" ] && tools="${tools:+$tools and }bun"
if [ -z "$pn" ]; then pnote=""
elif [ -n "$vnum" ]; then pnote="pnpm $ver blocks install scripts by default."
else pnote="The pnpm version could not be read (corepack picks each project's version); pnpm 10 or later blocks install scripts by default."; fi
if [ -n "$bad" ]; then fortkeep_result "$ID" FAIL "pnpm is set to run every package's install scripts" "dangerously-allow-all-builds=true in:$bad${unread:+. Could not read:$unread}"
elif [ -n "$old" ]; then fortkeep_result "$ID" FAIL "pnpm $old runs install scripts by default" "Upgrade to pnpm 10 or later.${unread:+ Could not read:$unread}"
elif [ -n "$unread" ]; then fortkeep_result "$ID" ERROR "Could not read:$unread" ""
else fortkeep_result "$ID" PASS "No global setting turns install scripts back on. Tools found: $tools" "$pnote"; fi
