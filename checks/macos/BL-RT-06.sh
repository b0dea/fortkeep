#!/bin/bash
. "$(dirname "$0")/../lib/common.sh"
ID=BL-RT-06
if devward_real_cmd tirith >/dev/null; then devward_result "$ID" PASS "tirith is installed"
else devward_result "$ID" FAIL "tirith is not installed"; fi
