#!/bin/bash
. "$(dirname "$0")/../lib/common.sh"
. "$(dirname "$0")/../lib/apps.sh"
ID=BL-RT-03
if devward_app "Little Snitch" >/dev/null && { devward_running "Little Snitch Agent" || devward_running "Little Snitch Daemon"; }; then
  devward_result "$ID" PASS "Little Snitch is running"
elif devward_app LuLu >/dev/null && devward_running LuLu; then
  devward_result "$ID" PASS "LuLu is running (the free alternative to Little Snitch)"
elif devward_app "Little Snitch" LuLu >/dev/null; then
  devward_result "$ID" FAIL "An outbound firewall is installed but not running" "Open it and turn it on"
else
  devward_result "$ID" FAIL "No outbound firewall (Little Snitch or LuLu)"
fi
