#!/bin/bash
. "$(dirname "$0")/../lib/common.sh"
. "$(dirname "$0")/../lib/browsers.sh"
ID=BL-BR-05
counts="$(fortkeep_profiles | cut -f1 | sort | uniq -c)"; pn="$(fortkeep_profiles_note)"
[ -n "$counts" ] || { fortkeep_result "$ID" NA "No Chrome-family or Firefox profiles" "${pn# }"; exit 0; }
multi="$(printf '%s\n' "$counts" | awk '$1 >= 2 {print $2 " (" $1 " profiles)"}' | paste -sd, - | sed 's/,/, /g')"
if [ -n "$multi" ]; then fortkeep_result "$ID" PASS "More than one profile in: $multi" "The agent can't tell which one you use for development; keep personal logins out of it$pn"
else fortkeep_result "$ID" FAIL "Every browser has a single profile" "Create a separate profile for development, with no personal logins$pn"; fi
