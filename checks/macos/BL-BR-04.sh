#!/bin/bash
. "$(dirname "$0")/../lib/common.sh"
. "$(dirname "$0")/../lib/browsers.sh"
ID=BL-BR-04
WALLETS='nkbihfbeogaeaoehlefnkodbefgpgknn bfnaelmomeimhlpmgjnjophhpkkoljpa hnfanknocfeofbddgcijnmhnfnkdnaad egjidjbpglichdcondbcbdnbeeppgdph acmacodkjbdgmoleebolmdjonilkdbch mcohilncbfahbmgdjkbpemcciiolgcge aholpfdialjgjfhomihkjbmgjidlcdno dmkamcknogkgcdfhhbddcghachkejeap ibnejdfjmmkpcnlpebklmnkoeoihofec fhbohimaelbohpjbbldcngcnapndodjp bhhhlbepdkbapadjdnnojkbgioiodbic aflkmfhebedbjioipglgcbcmnbpgliof webextension@metamask.io'
NAMES='wallet|metamask|phantom|coinbase|rabby|keplr|exodus|tronlink|solflare|backpack|okx'
profiles="$(devward_profiles)"; pn="$(devward_profiles_note)"
[ -n "$profiles" ] || { devward_result "$ID" NA "No Chrome-family or Firefox profiles" "${pn# }"; exit 0; }
command -v jq >/dev/null 2>&1 || { devward_result "$ID" ERROR "Couldn't read browser extensions" "jq is not available$pn"; exit 0; }
n=0; found=""; unread=""
while IFS="$(printf '\t')" read -r b p; do
  [ -n "$b" ] || continue
  devward_extensions_readable "$b" "$p" || { unread="$unread, $b ($(basename "$p"))"; continue; }
  while IFS="$(printf '\t')" read -r id name; do
    [ -n "$id" ] || continue
    n=$((n + 1))
    hit=0
    case " $WALLETS " in *" $id "*) hit=1 ;; esac
    printf '%s' "$name" | grep -Eiq "$NAMES" && hit=1
    [ "$hit" -eq 1 ] && found="$found, $name ($b)"
  done <<EOT
$(devward_extensions "$b" "$p")
EOT
done <<EOF2
$profiles
EOF2
if [ -n "$found" ]; then devward_result "$ID" FAIL "Crypto wallet extensions found ($n extension(s) in all)" "Wallets: ${found#, }${unread:+. Could not read: ${unread#, }}$pn"
elif [ -n "$unread" ]; then devward_result "$ID" ERROR "Couldn't read the extensions of ${unread#, }" "The extension list is unreadable or damaged$pn"
else devward_result "$ID" PASS "No crypto wallet extensions ($n extension(s) in all; remove any you don't use)" "${pn# }"; fi
