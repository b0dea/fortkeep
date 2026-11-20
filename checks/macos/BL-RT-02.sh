#!/bin/bash
. "$(dirname "$0")/../lib/common.sh"
. "$(dirname "$0")/../lib/apps.sh"
ID=BL-RT-02
if fortkeep_app KnockKnock >/dev/null; then fortkeep_result "$ID" PASS "KnockKnock is installed" "It needs Full Disk Access to see every autostart location"
else fortkeep_result "$ID" FAIL "KnockKnock is not installed"; fi
