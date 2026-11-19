#!/bin/bash
. "$(dirname "$0")/../lib/common.sh"
. "$(dirname "$0")/../lib/apps.sh"
ID=BL-RT-02
if devward_app KnockKnock >/dev/null; then devward_result "$ID" PASS "KnockKnock is installed" "It needs Full Disk Access to see every autostart location"
else devward_result "$ID" FAIL "KnockKnock is not installed"; fi
