#!/bin/bash
. "$(dirname "$0")/../lib/common.sh"
ID=BL-SE-03
keys() {  # DIR DEPTH — key-like files, skipping Library, node_modules and .git
  devward_walk "$1" -maxdepth "$2" \( -name Library -o -name node_modules -o -name .git -o -name .ssh \) -prune -o -type f \
    \( -iname '*.pem' -o -iname '*.key' -o -iname '*.p12' -o -iname '*.pfx' -o -name credentials -o -name credentials.json \
       -o -iname 'sa-key*.json' -o -name id_rsa -o -name id_ecdsa -o -name id_ed25519 -o -name id_dsa \)
}
not_key() {  # FILE — true for a readable .pem or .key with no private key in it: a certificate, a Keynote document, a fixture
  case "$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')" in *.pem|*.key) ;; *) return 1 ;; esac
  LC_ALL=C grep -q -- '-----BEGIN [A-Z0-9 ]*PRIVATE KEY' "$1" 2>/dev/null
  [ $? -eq 1 ]  # 2, unreadable, still counts: it could hold one
}
envs() { devward_walk "$1" -maxdepth 1 -type f \( -name .env -o -name '.env.*' \) ! -name '*.example' ! -name '*.sample'; }
found=""; unread=""; asked=""; nu=0; skipped=""
for spec in "$HOME|1" "$HOME/Downloads|4" "$HOME/Desktop|4" "$HOME/Documents|4"; do
  d="${spec%|*}"; n="${spec#*|}"
  [ -d "$d" ] || continue
  if devward_is_private "$d"; then skipped=" (a private folder was excluded)"; continue; fi
  # The first read of ~/Downloads, ~/Desktop or ~/Documents makes macOS ask, and the read waits for the answer:
  # move on after 5 s and say so, rather than letting the whole check time out.
  devward_timeout 5 ls "$d" >/dev/null 2>&1; rc=$?
  case "$rc" in
    0) ;;
    142) asked="$asked $(devward_tilde "$d")"; nu=$((nu + 1)); continue ;;
    *) unread="$unread $(devward_tilde "$d")"; nu=$((nu + 1)); continue ;;
  esac
  found="$found$(keys "$d" "$n")"$'\n'
  case "$d" in "$HOME"|"$HOME/Downloads"|"$HOME/Desktop") found="$found$(envs "$d")"$'\n' ;; esac
done
why="${unread:+. macOS privacy settings blocked reading:$unread}${asked:+. macOS is asking whether this app may read:$asked; answer that prompt, then run the check again}"
list="$(printf '%s\n' "$found" | sed '/^$/d' | sort -u | while IFS= read -r f; do not_key "$f" || printf '%s\n' "$f"; done)"
n="$(printf '%s' "$list" | grep -c .)"
if [ "$n" -gt 0 ]; then
  devward_result "$ID" FAIL "$n key or secret file(s) in ~, ~/Downloads, ~/Desktop or ~/Documents" \
    "$(printf '%s\n' "$list" | head -10 | while IFS= read -r f; do devward_tilde "$f"; done | paste -sd, - | sed 's/,/, /g')$why$skipped"
elif [ -n "$why" ]; then devward_result "$ID" ERROR "Could not read $nu folder(s)" "${why#. }$skipped"
else devward_result "$ID" PASS "No key or secret files in the folders searched" "${skipped# }"; fi
