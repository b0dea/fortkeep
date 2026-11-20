#!/bin/bash
. "$(dirname "$0")/../lib/common.sh"
. "$(dirname "$0")/../lib/apps.sh"
ID=BL-BR-06
if fortkeep_app NextDNS >/dev/null && fortkeep_running NextDNS; then fortkeep_result "$ID" PASS "The NextDNS app is running"; exit 0; fi
raw="$(fortkeep_timeout "${FORTKEEP_SCUTIL_TIMEOUT:-15}" scutil --dns 2>/dev/null)"; rc=$?
[ "$rc" -eq 0 ] || { fortkeep_result "$ID" ERROR "Couldn't read the DNS settings" "scutil --dns failed or timed out"; exit 0; }
# Default resolvers only: blocks without a "domain" line, from the first section (not scoped queries).
ns="$(printf '%s\n' "$raw" | awk '
  /^DNS configuration \(for scoped/ { exit }
  /^resolver #/ { if (!dom) for (i = 1; i <= n; i++) print s[i]; n = 0; dom = 0; next }
  /^[[:space:]]*domain[[:space:]]*:/ { dom = 1 }
  /nameserver\[[0-9]+\]/ { s[++n] = $3 }
  END { if (!dom) for (i = 1; i <= n; i++) print s[i] }' | sort -u)"
[ -n "$ns" ] || { fortkeep_result "$ID" ERROR "Couldn't find which DNS servers this Mac uses" "scutil --dns listed no default DNS servers"; exit 0; }
bad=""
while IFS= read -r a; do
  case "$a" in
    1.1.1.2|1.0.0.2|1.1.1.3|1.0.0.3|2606:4700:4700::1112|2606:4700:4700::1002|2606:4700:4700::1113|2606:4700:4700::1003) ;;
    9.9.9.9|149.112.112.112|2620:fe::fe|2620:fe::9|45.90.28.*|45.90.30.*|2a07:a8c0:*|2a07:a8c1:*) ;;
    *) bad="$bad $a" ;;
  esac
done <<EOF
$ns
EOF
list="$(printf '%s\n' "$ns" | paste -sd, - | sed 's/,/, /g')"
if [ -z "$bad" ]; then fortkeep_result "$ID" PASS "DNS goes to filtering resolvers: $list"; exit 0; fi

# Any other set-up (Control D, AdGuard, MagicDNS, WARP, an encrypted-DNS profile, a filtering router) is judged by what
# it does. One lookup through the system resolver, as apps make it: malware.testcategory.com, Cloudflare's published
# malware test name. It resolves to Cloudflare's own addresses unless a filter blocks it. Only when that lookup gets no
# answer at all, a second one for example.com tells a block from no network.
lookup() { fortkeep_timeout 10 dscacheutil -q host -a name "$1" 2>/dev/null | awk '/^ip(v6)?_address:/ { print $2 }'; }
answer="$(lookup malware.testcategory.com)"
blocked=""
if [ -z "$answer" ]; then
  [ -n "$(lookup example.com)" ] || { fortkeep_result "$ID" ERROR "Couldn't test DNS filtering: this Mac's DNS answered nothing" "Connect to the network, then run the check again"; exit 0; }
  blocked="returned no address for"
elif ! printf '%s\n' "$answer" | grep -Eq '^(104\.(1[6-9]|2[0-3])\.|172\.(6[4-9]|7[01])\.|2606:4700:)'; then
  blocked="blocked"
fi
if [ -n "$blocked" ]; then
  fortkeep_result "$ID" PASS "DNS filtering works: the DNS this Mac uses ($list) $blocked a malware test name" "The check looked up malware.testcategory.com, Cloudflare's published test name"
  exit 0
fi
note="Use Cloudflare 1.1.1.2 (free) or NextDNS, as in the lesson. The DNS this Mac uses resolved malware.testcategory.com, a published malware test name, so it doesn't filter."
case "$bad" in *127.0.2.*) note="$note Cloudflare WARP's resolver filters only if WARP or your organisation turns that on." ;; esac
case "$bad" in *" 10."*|*" 192.168."*|*" 172."*|*" 127."*|*" fe80:"*|*" fd"*) note="$note If your router or local resolver filters with a list that lacks this test name, tell your agent and it will record that as your decision." ;; esac
fortkeep_result "$ID" FAIL "DNS goes to: $list" "$note"
