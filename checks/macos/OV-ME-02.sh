#!/bin/bash
. "$(dirname "$0")/../lib/common.sh"
. "$(dirname "$0")/../lib/apps.sh"
ID=OV-ME-02
p="$(fortkeep_endpoint_products)"
[ -n "$p" ] || { fortkeep_result "$ID" FAIL "No endpoint protection or antivirus found"; exit 0; }
list="$(printf '%s\n' "$p" | paste -sd, - | sed 's/,/, /g')"
if ! printf '%s\n' "$p" | grep -qx "Microsoft Defender"; then
  fortkeep_result "$ID" NA "The agent can read tamper protection only from Microsoft Defender (found: $list)" "Ask your organisation's IT or security team to confirm it's on"; exit 0
fi
v="$(fortkeep_mdatp_field tamper_protection)"; rc=$?
case "$rc:$v" in
  142:*) fortkeep_result "$ID" ERROR "Defender tamper protection unknown" "mdatp did not answer in time" ;;
  0:block) fortkeep_result "$ID" PASS "Defender tamper protection: block" ;;
  0:) fortkeep_result "$ID" ERROR "Defender tamper protection unknown" "mdatp gave no answer" ;;
  0:audit|0:disabled) fortkeep_result "$ID" FAIL "Defender tamper protection: $v" "Only your organisation's IT or security team can change this; tell them" ;;
  0:*) fortkeep_result "$ID" ERROR "Defender gave an unexpected answer" "Tamper protection reported: $v" ;;
  1:*) fortkeep_result "$ID" ERROR "Defender tamper protection unknown" "Defender's command-line tool (mdatp) is missing" ;;
  *) fortkeep_result "$ID" ERROR "Defender tamper protection unknown" "mdatp failed when asked for tamper protection" ;;
esac
