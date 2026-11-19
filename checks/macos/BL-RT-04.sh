#!/bin/bash
. "$(dirname "$0")/../lib/common.sh"
. "$(dirname "$0")/../lib/apps.sh"
ID=BL-RT-04
if a="$(devward_app "Micro Snitch" OverSight)"; then devward_result "$ID" PASS "$(basename "$a" .app) is installed"
else devward_result "$ID" FAIL "No microphone and camera monitor (Micro Snitch or OverSight)"; fi
