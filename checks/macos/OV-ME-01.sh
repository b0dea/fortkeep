#!/bin/bash
. "$(dirname "$0")/../lib/common.sh"
. "$(dirname "$0")/../lib/apps.sh"
ID=OV-ME-01
p="$(devward_endpoint_products)"
[ -n "$p" ] || { devward_result "$ID" FAIL "No endpoint protection or antivirus found" "This Mac is set up as managed by your organisation's endpoint protection"; exit 0; }
list="$(printf '%s\n' "$p" | paste -sd, - | sed 's/,/, /g')"
if ! printf '%s\n' "$p" | grep -qx "Microsoft Defender"; then
  devward_result "$ID" PASS "Installed: $list; its health can't be read by a command, check its own window" "The agent can read health only from Microsoft Defender"; exit 0
fi
v="$(devward_mdatp_field healthy)"; rc=$?
case "$rc:$v" in
  142:*) devward_result "$ID" ERROR "Installed: $list" "mdatp did not answer in time" ;;
  0:true) devward_result "$ID" PASS "Installed: $list; Defender reports healthy" ;;
  0:false) devward_result "$ID" FAIL "Installed: $list; Defender reports a problem" "Run mdatp health in Terminal and tell your organisation's IT or security team" ;;
  0:*) devward_result "$ID" ERROR "Installed: $list" "Defender gave no usable answer for its health" ;;
  1:*) devward_result "$ID" ERROR "Installed: $list" "Defender's command-line tool (mdatp) is missing" ;;
  *) devward_result "$ID" ERROR "Installed: $list" "Could not read Defender's health" ;;
esac
