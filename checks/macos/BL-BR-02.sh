#!/bin/bash
. "$(dirname "$0")/../lib/common.sh"
. "$(dirname "$0")/../lib/browsers.sh"
ID=BL-BR-02
# A password manager's own extension: 1Password, Bitwarden and Apple's iCloud Passwords, each in the Chrome Web
# Store, Edge Add-ons and Firefox Add-ons (the ids their stores and vendors publish).
IDS='aeblfdkhhhdcdjpifhhbdiojplfjncoa dppgmdbiimibapkepcbdbmkaabgiofem {d634138d-c276-4fc8-924b-40a0ea21d284}
nngceckbapebfimnlniiiahkandclblb jbkfoedolllekgbhcbcoahefnbanhhlh {446900e4-71c2-419f-a6a7-df9c091e268b}
pejdijmoenmkgeppbflobdenhhabjlaj mfbcdcnpokpoajjciilocoachedjkima password-manager-firefox-extension@apple.com'
IDS="$(printf '%s' "$IDS" | tr '\n' ' ')"
profiles="$(devward_profiles)"; pn="$(devward_profiles_note)"
[ -n "$profiles" ] || { devward_result "$ID" NA "No Chrome-family or Firefox profiles" "${pn# }"; exit 0; }
command -v jq >/dev/null 2>&1 || { devward_result "$ID" ERROR "Couldn't read browser extensions" "jq is not available$pn"; exit 0; }
total=0; without=""; unread=""
while IFS="$(printf '\t')" read -r b p; do
  [ -n "$b" ] || continue
  total=$((total + 1)); ok=0
  devward_extensions_readable "$b" "$p" || { unread="$unread, $b ($(basename "$p"))"; continue; }
  while IFS="$(printf '\t')" read -r id name; do
    case " $IDS " in *" $id "*) ok=1 ;; esac
    case "$name" in 1Password*|Bitwarden*|"iCloud Passwords"*) ok=1 ;; esac
  done <<EOT
$(devward_enabled_extensions "$b" "$p")
EOT
  [ "$ok" -eq 1 ] || without="$without, $b ($(basename "$p"))"
done <<EOF2
$profiles
EOF2
if [ -n "$without" ]; then devward_result "$ID" FAIL "No password manager extension (1Password, Bitwarden or iCloud Passwords) in some browser profiles" "Missing in: ${without#, }${unread:+. Could not read: ${unread#, }}$pn"
elif [ -n "$unread" ]; then devward_result "$ID" ERROR "Couldn't read the extensions of ${unread#, }" "The extension list is unreadable or damaged$pn"
else devward_result "$ID" PASS "A password manager extension in all $total browser profiles" "${pn# }"; fi
