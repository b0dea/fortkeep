#!/bin/bash
. "$(dirname "$0")/../lib/common.sh"
. "$(dirname "$0")/../lib/browsers.sh"
ID=BL-BR-03
IDS='cjpalhdlnbpafiamejdnhcphjbkeiagm ddkjiahejlhfcafbddmgiahcphecmpfh odfafepnkmbhccpbejgmiehpchacaeak uBlock0@raymondhill.net'
profiles="$(devward_profiles)"; pn="$(devward_profiles_note)"
[ -n "$profiles" ] || { devward_result "$ID" NA "No Chrome-family or Firefox profiles" "${pn# }"; exit 0; }
command -v jq >/dev/null 2>&1 || { devward_result "$ID" ERROR "Couldn't read browser extensions" "jq is not available$pn"; exit 0; }
total=0; without=""; unread=""
while IFS="$(printf '\t')" read -r b p; do
  [ -n "$b" ] || continue
  total=$((total + 1)); ok=0
  devward_extensions_readable "$b" "$p" || { unread="$unread, $b ($(basename "$p"))"; continue; }
  case "$b" in Brave*) ok=1 ;; esac
  while IFS="$(printf '\t')" read -r id name; do
    case " $IDS " in *" $id "*) ok=1 ;; esac
    case "$name" in "uBlock Origin"*) ok=1 ;; esac
  done <<EOT
$(devward_enabled_extensions "$b" "$p")
EOT
  [ "$ok" -eq 1 ] || without="$without, $b ($(basename "$p"))"
done <<EOF2
$profiles
EOF2
if [ -n "$without" ]; then devward_result "$ID" FAIL "No content blocker in some browser profiles" "Missing in: ${without#, }${unread:+. Could not read: ${unread#, }}$pn"
elif [ -n "$unread" ]; then devward_result "$ID" ERROR "Couldn't read the extensions of ${unread#, }" "The extension list is unreadable or damaged$pn"
else devward_result "$ID" PASS "uBlock Origin or Brave shields in all $total browser profiles" "${pn# }"; fi
