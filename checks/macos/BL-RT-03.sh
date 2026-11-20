#!/bin/bash
. "$(dirname "$0")/../lib/common.sh"
. "$(dirname "$0")/../lib/apps.sh"
ID=BL-RT-03
if fortkeep_app "Little Snitch" >/dev/null && { fortkeep_running "Little Snitch Agent" || fortkeep_running "Little Snitch Daemon"; }; then
  fortkeep_result "$ID" PASS "Little Snitch is running"
elif fortkeep_app LuLu >/dev/null && fortkeep_running LuLu; then
  fortkeep_result "$ID" PASS "LuLu is running (the free alternative to Little Snitch)"
elif fortkeep_app "Little Snitch" LuLu >/dev/null; then
  fortkeep_result "$ID" FAIL "An outbound firewall is installed but not running" "Open it and turn it on"
else
  fortkeep_result "$ID" FAIL "No outbound firewall (Little Snitch or LuLu)"
fi
