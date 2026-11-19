#!/bin/bash
. "$(dirname "$0")/../lib/common.sh"
. "$(dirname "$0")/../lib/apps.sh"
ID=OV-ME-03
p="$(devward_endpoint_products)"
[ -n "$p" ] || { devward_result "$ID" FAIL "No endpoint protection or antivirus found"; exit 0; }
list="$(printf '%s\n' "$p" | paste -sd, - | sed 's/,/, /g')"
if ! printf '%s\n' "$p" | grep -qx "Microsoft Defender"; then
  devward_result "$ID" NA "The agent can read behaviour monitoring only from Microsoft Defender (found: $list)" "Ask your organisation's IT or security team how it should be set"; exit 0
fi
v="$(devward_mdatp_field behavior_monitoring)"; rc=$?
case "$rc:$v" in
  142:*) devward_result "$ID" ERROR "Defender behaviour monitoring unknown" "mdatp did not answer in time" ;;
  0:enabled) devward_result "$ID" PASS "Defender behaviour monitoring: enabled" ;;
  0:) devward_result "$ID" ERROR "Defender behaviour monitoring unknown" "mdatp gave no answer" ;;
  0:disabled) devward_result "$ID" FAIL "Defender behaviour monitoring: $v" "Ask your organisation's IT or security team whether it should be on; don't change it yourself. If they want it off, tell your agent and it records that as your decision" ;;
  0:*) devward_result "$ID" ERROR "Defender gave an unexpected answer" "Behaviour monitoring reported: $v" ;;
  1:*) devward_result "$ID" ERROR "Defender behaviour monitoring unknown" "Defender's command-line tool (mdatp) is missing" ;;
  *) devward_result "$ID" ERROR "Defender behaviour monitoring unknown" "mdatp failed when asked for behaviour monitoring" ;;
esac
