#!/bin/bash
. "$(dirname "$0")/../lib/common.sh"
ID=BL-RT-06
if fortkeep_real_cmd tirith >/dev/null; then fortkeep_result "$ID" PASS "tirith is installed"
else fortkeep_result "$ID" FAIL "tirith is not installed"; fi
