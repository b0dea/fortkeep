#!/bin/bash
. "$(dirname "$0")/../lib/common.sh"
ID=BL-SE-07
if fortkeep_is_private "$HOME/.ssh"; then fortkeep_result "$ID" ERROR "Could not check ~/.ssh" "a private folder was excluded"; exit 0; fi
total=0; old=""; unread=""; nu=0
for f in "$HOME/.ssh"/*; do
  [ -f "$f" ] || continue
  case "$(basename "$f")" in *.pub|known_hosts*|config|authorized_keys*|allowed_signers) continue ;; esac
  [ -r "$f" ] || { unread="$unread $(basename "$f")"; nu=$((nu + 1)); continue; }
  head -c 100 "$f" 2>/dev/null | grep -q -- '-----BEGIN .*PRIVATE KEY-----' || continue
  total=$((total + 1))
  [ -n "$(find "$f" -mtime +365 2>/dev/null)" ] && old="$old $(basename "$f")"
done
if [ -n "$old" ]; then fortkeep_result "$ID" FAIL "Key files older than a year in ~/.ssh" "Older than a year:$old${unread:+. Could not read:$unread}"
elif [ -n "$unread" ]; then fortkeep_result "$ID" ERROR "Could not read $nu file(s) in ~/.ssh" "Could not read:$unread"
elif [ "$total" -eq 0 ]; then fortkeep_result "$ID" PASS "No private key files in ~/.ssh"
else fortkeep_result "$ID" PASS "All $total key files in ~/.ssh are less than a year old"; fi
