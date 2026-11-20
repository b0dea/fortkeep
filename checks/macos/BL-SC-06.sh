#!/bin/bash
. "$(dirname "$0")/../lib/common.sh"
ID=BL-SC-06
found=""; bad=""; unknown=""
# A dangling symlink is not "installed" to fortkeep_real_cmd, so look for one too.
dangling() {
  local d IFS=:
  for d in $FORTKEEP_USER_PATH; do
    case "$d" in ""|"$HOME/.safe-chain"|"$HOME/.safe-chain"/*) continue ;; esac
    if [ -L "$d/$1" ]; then printf '%s\n' "$d/$1"; return 0; fi
  done
  return 1
}
for c in pnpm yarn; do
  p="$(fortkeep_real_cmd "$c")" || p="$(dangling "$c")" || continue
  found="$found $c"
  r="$(perl -MCwd=abs_path -e 'print abs_path($ARGV[0]) // ""' "$p" 2>/dev/null)" || r=""
  if [ -z "$r" ] || [ ! -e "$p" ]; then unknown="$unknown $c"; continue; fi
  case "$r" in */corepack/*) ;; *) bad="$bad $c" ;; esac
done
if [ -z "$found" ]; then fortkeep_result "$ID" NA "pnpm and yarn are not installed"
elif [ -n "$bad" ]; then fortkeep_result "$ID" FAIL "Not from corepack:$bad" "A global copy ignores each repo's pinned version${unknown:+. Could not resolve:$unknown}"
elif [ -n "$unknown" ]; then fortkeep_result "$ID" ERROR "Could not resolve:$unknown" "The file is missing or cannot be followed"
else fortkeep_result "$ID" PASS "From corepack:$found"; fi
