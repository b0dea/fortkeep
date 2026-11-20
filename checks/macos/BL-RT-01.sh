#!/bin/bash
. "$(dirname "$0")/../lib/common.sh"
. "$(dirname "$0")/../lib/apps.sh"
ID=BL-RT-01
if [ ! -d "$(fortkeep_path /Library/Objective-See/BlockBlock)" ] && ! fortkeep_app "BlockBlock Helper" BlockBlock >/dev/null; then
  fortkeep_result "$ID" FAIL "BlockBlock is not installed"; exit 0
fi
if fortkeep_running BlockBlock || fortkeep_running "BlockBlock Helper"; then fortkeep_result "$ID" PASS "BlockBlock is installed and running"
else fortkeep_result "$ID" FAIL "BlockBlock is installed but not running" "Open BlockBlock Helper and turn its protection on"; fi
