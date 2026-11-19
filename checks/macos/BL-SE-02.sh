#!/bin/bash
. "$(dirname "$0")/../lib/common.sh"
ID=BL-SE-02
if devward_is_private "$HOME/.ssh"; then devward_result "$ID" ERROR "Could not check ~/.ssh" "a private folder was excluded"; exit 0; fi
total=0; nb=0; bad=""; unread=""; nu=0
for f in "$HOME/.ssh"/*; do
  [ -f "$f" ] || continue
  case "$(basename "$f")" in *.pub|known_hosts*|config|authorized_keys*|allowed_signers) continue ;; esac
  [ -r "$f" ] || { unread="$unread $(basename "$f")"; nu=$((nu + 1)); continue; }
  head -c 100 "$f" 2>/dev/null | grep -q -- '-----BEGIN .*PRIVATE KEY-----' || continue
  total=$((total + 1))
  # Opens without a passphrase. A security-key (-sk) file is only a handle that works with its hardware key, so it passes.
  if pk="$(ssh-keygen -y -P '' -f "$f" 2>/dev/null)"; then
    case "$pk" in sk-*) ;; *) bad="$bad $(basename "$f")"; nb=$((nb + 1)) ;; esac
  fi
done
if [ -n "$bad" ]; then devward_result "$ID" FAIL "Key files in ~/.ssh without a passphrase: $nb of $total" "No passphrase:$bad${unread:+. Could not read:$unread}"
elif [ -n "$unread" ]; then devward_result "$ID" ERROR "Could not read $nu file(s) in ~/.ssh" "Could not read:$unread"
elif [ "$total" -eq 0 ]; then devward_result "$ID" PASS "No private key files in ~/.ssh"
else devward_result "$ID" PASS "All $total key files in ~/.ssh have a passphrase"; fi
