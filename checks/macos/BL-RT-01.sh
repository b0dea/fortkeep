#!/bin/bash
. "$(dirname "$0")/../lib/common.sh"
. "$(dirname "$0")/../lib/apps.sh"
ID=BL-RT-01
if [ ! -d "$(devward_path /Library/Objective-See/BlockBlock)" ] && ! devward_app "BlockBlock Helper" BlockBlock >/dev/null; then
  devward_result "$ID" FAIL "BlockBlock is not installed"; exit 0
fi
if devward_running BlockBlock || devward_running "BlockBlock Helper"; then devward_result "$ID" PASS "BlockBlock is installed and running"
else devward_result "$ID" FAIL "BlockBlock is installed but not running" "Open BlockBlock Helper and turn its protection on"; fi
